#!/usr/bin/env bash
# The one standard procedure that updates the development environment after a merge.
# The pre-merge rehearsal runs the same steps in the worktree, with the same compose file,
# commands and a fresh copy of the development data, so the post-merge run only repeats
# what has already passed.
#
#   deploy.sh rehearse <worktree>      [--bootstrap]  pre-merge rehearsal in a feature worktree
#   deploy.sh apply    <dev checkout>  [--bootstrap]  post-merge update of the development environment
#
# --bootstrap is for the first merge of a project (initer), before a development
# environment exists: data services start empty instead of being copied or backed up, and the
# seed command runs after the migrations.
#
# Steps (both modes, same order):
#   checks   rehearse: branch contains origin/development, clean tree, migrations already in
#            origin/development unchanged, development .env can take the new variables
#            apply: on development and equal to origin/development, clean tree
#   env      add variables from .env.example missing in .env (fails if a new one has no default)
#   data     start the data services; rehearse: back up the worktree data and replace it with
#            a copy of development; apply: no backup (failures are fixed forward with a new task)
#   build    docker compose build
#   migrate  MIGRATE_CMD in APP_SERVICE
#   up       docker compose up -d --wait
#   health   HTTP checks from HEALTH_CHECKS on localhost and the Tailscale IP
#   test     rehearse only: TEST_CMD in APP_SERVICE
#
# Project settings come from .claude/stack.toml (see the initer skill). Exit: 0 ok, 1 failed.
set -uo pipefail
source "$HOME/.claude/scripts/devenv-lib.sh"

DB="$HOME/.claude/scripts/db.sh"
mode=${1:-}; target=${2:-}; bootstrap=0
[[ ${3:-} == --bootstrap ]] && bootstrap=1
[[ $mode == rehearse || $mode == apply ]] && [[ -d $target ]] || { sed -n '2,28p' "$0" >&2; exit 2; }
devenv_load "$target" || exit 2
cd "$dir" || exit 2

logs=$(mktemp -d); trap 'rm -rf "$logs"' EXIT

# Scrub values of secret-looking .env keys from logs before printing them.
redact() {
  python3 -c '
import re, sys
secrets = []
for path in sys.argv[1:]:
    try:
        for line in open(path):
            m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)", line)
            if m and re.search(r"PASS|SECRET|TOKEN|KEY|URL", m.group(1)) and len(m.group(2).strip()) >= 6:
                secrets.append(m.group(2).strip().strip("\"\x27"))
    except OSError:
        pass
for line in sys.stdin:
    for s in secrets:
        line = line.replace(s, "****")
    sys.stdout.write(line)
' "$dir/.env" "$main_dir/.env"
}

fail() { echo "RESULT: fail step=$1"; [[ -n ${2:-} ]] && echo "reason: $2"; exit 1; }

step() {  # step <name> <command...>
  local name=$1; shift
  printf 'STEP %-8s ' "$name"
  if "$@" >"$logs/$name.log" 2>&1; then
    echo ok
  else
    echo FAIL
    echo "--- last output of '$name':"
    tail -n 40 "$logs/$name.log" | redact
    fail "$name"
  fi
}

env_get() { sed -n "s/^[[:space:]]*$1=//p" "$2" 2>/dev/null | tail -1 | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'; }

# env_keys <mode> <env file>: "sync" appends keys from .env.example missing in the file and
# prints the ones without a default; "check" only prints keys that would lack a value.
env_keys() {
  python3 - "$1" "$dir/.env.example" "$2" <<'EOF'
import re, sys, os
mode, example, target = sys.argv[1:4]
def parse(p):
    out = {}
    if os.path.exists(p):
        for line in open(p):
            m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)", line)
            if m: out[m.group(1)] = m.group(2).strip()
    return out
ex, cur = parse(example), parse(target)
missing = [(k, v) for k, v in ex.items() if k not in cur]
empty = [k for k, v in missing if v in ("", '""', "''")]
if mode == "sync":
    with open(target, "a") as f:
        for k, v in missing:
            if k not in empty: f.write(f"{k}={v}\n")
print(" ".join(empty))
EOF
}

# ---- checks -----------------------------------------------------------------------------
[[ -f $stack_file ]] || fail checks "missing .claude/stack.toml (run the initer skill)"
[[ -f $dir/compose.yaml || -f $dir/compose.yml || -f $dir/docker-compose.yml || -f $dir/docker-compose.yaml ]] || fail checks "no compose file"
[[ -f $dir/.env ]] || fail checks "missing .env"
dirty=$(git status --porcelain --untracked-files=normal | grep -vE '^.. (docs/reports/|\.env$)' || true)
[[ -z $dirty ]] || fail checks "uncommitted changes; the deployed state must be committed"
git fetch -q origin || fail checks "git fetch failed"

if [[ $mode == rehearse ]]; then
  [[ $is_dev == 0 && -n $branch && $branch != main && $branch != development ]] || fail checks "rehearse runs in a feature worktree"
  git merge-base --is-ancestor origin/development HEAD || fail checks "branch is behind origin/development; update it first (push skill)"
  if [[ -n ${C[MIGRATIONS_DIR]:-} ]]; then
    changed=$(git diff --name-status origin/development...HEAD -- "${C[MIGRATIONS_DIR]}" | awk '$1 !~ /^A/ {print $NF}')
    [[ -z $changed ]] || fail checks "migrations already in origin/development were changed (write a new migration instead): $changed"
  fi
  if [[ $bootstrap == 0 ]]; then
    [[ -f $main_dir/.env && -f $main_dir/.claude/stack.toml ]] || fail checks "the development environment is not set up yet; the first merge of a project (initer) uses --bootstrap"
    dev_missing=$(env_keys check "$main_dir/.env")
    [[ -z $dev_missing ]] || fail checks "development .env needs values before merge for: $dev_missing"
  fi
else
  [[ $is_dev == 1 && $branch == development ]] || fail checks "apply runs in the development checkout on 'development'"
  [[ $(git rev-parse HEAD) == $(git rev-parse origin/development) ]] || fail checks "local development is not equal to origin/development"
fi
echo "STEP checks   ok"

# ---- env --------------------------------------------------------------------------------
empty=$(env_keys sync "$dir/.env")
[[ -z $empty ]] || fail env "new variables without a default in .env.example need values: $empty"
echo "STEP env      ok"

# ---- data -------------------------------------------------------------------------------
data() {
  local svc engine
  while read -r svc engine; do
    [[ -n $svc ]] || continue
    dc_in "$dir" up -d --wait "$svc" || return 1
    [[ $bootstrap == 0 ]] && copyable "$engine" || continue
    if [[ $mode == rehearse ]]; then
      "$DB" backup "$dir" "$svc" && "$DB" copy-from-dev "$dir" "$svc" || return 1
    fi
  done < <(data_services)
}
if [[ -n ${C[DATA_SERVICES]:-} ]]; then step data data; else echo "STEP data     skipped (no data services)"; fi

# ---- build, migrate, up -----------------------------------------------------------------
step build docker compose build
if [[ -n ${C[MIGRATE_CMD]:-} ]]; then
  step migrate docker compose run --rm "${C[APP_SERVICE]}" sh -c "${C[MIGRATE_CMD]}"
else
  echo "STEP migrate  skipped (no MIGRATE_CMD)"
fi
if [[ $bootstrap == 1 && -n ${C[SEED_CMD]:-} ]]; then
  step seed docker compose run --rm "${C[APP_SERVICE]}" sh -c "${C[SEED_CMD]}"
fi
step up docker compose up -d --remove-orphans --wait --wait-timeout "${C[HEALTH_TIMEOUT]}"

# ---- health -----------------------------------------------------------------------------
health() {
  local hosts=(127.0.0.1) host check port_var path port deadline
  command -v tailscale >/dev/null && host=$(tailscale ip -4 2>/dev/null | head -1) && [[ -n $host ]] && hosts+=("$host")
  for check in ${C[HEALTH_CHECKS]}; do
    port_var=${check%%:*}; path=${check#*:}; [[ $path == "$check" ]] && path=/
    port=$(env_get "$port_var" "$dir/.env")
    [[ -n $port ]] || { echo "no value for $port_var in .env"; return 1; }
    for host in "${hosts[@]}"; do
      deadline=$((SECONDS + ${C[HEALTH_TIMEOUT]}))
      until curl -fsS -o /dev/null -m 5 "http://$host:$port$path"; do
        (( SECONDS < deadline )) || { echo "http://$host:$port$path did not respond"; return 1; }
        sleep 2
      done
      echo "http://$host:$port$path ok"
    done
  done
}
if [[ -n ${C[HEALTH_CHECKS]:-} ]]; then step health health; else echo "STEP health   skipped (no health checks)"; fi

# ---- test (rehearse only) ---------------------------------------------------------------
if [[ $mode == rehearse ]]; then
  if [[ -n ${C[TEST_CMD]:-} ]]; then
    step test docker compose run --rm "${C[APP_SERVICE]}" sh -c "${C[TEST_CMD]}"
  else
    echo "STEP test     skipped (no TEST_CMD)"
  fi
  # Record what was rehearsed so the merge can check that nothing moved since.
  git -C "$main_dir" config "branch.$branch.rehearsedHead" "$(git rev-parse HEAD)"
  git -C "$main_dir" config "branch.$branch.rehearsedBase" "$(git rev-parse origin/development)"
  echo "rehearsed: head=$(git rev-parse --short HEAD) base=$(git rev-parse --short origin/development)"
fi

echo "RESULT: ok"

#!/usr/bin/env bash
# The one standard procedure that updates the development environment after a merge.
# The pre-merge rehearsal runs the same steps in the worktree, with the same compose file,
# commands and a fresh copy of the development database, so the post-merge run only repeats
# what has already passed.
#
#   deploy.sh rehearse <worktree>      pre-merge rehearsal in a feature worktree
#   deploy.sh apply    <dev checkout>  post-merge update of the development environment
#
# Steps (both modes, same order):
#   checks   rehearse: branch contains origin/development, clean tree, migrations already in
#            origin/development unchanged, development .env can take the new variables
#            apply: on development, clean tree
#   env      add variables from .env.example missing in .env (fails if a new one has no default)
#   data     rehearse: back up and re-clone worktree databases from <project>_dev
#            apply: back up <project>_dev
#   build    docker compose build
#   migrate  MIGRATE_CMD in APP_SERVICE
#   up       docker compose up -d --wait
#   health   HTTP check on localhost and the Tailscale IP
#   test     rehearse only: TEST_CMD in APP_SERVICE
#
# Project settings come from .claude/devenv.conf (see the dev-env skill). Exit: 0 ok, 1 failed.
set -uo pipefail

DB="$HOME/.claude/scripts/db.sh"
mode=${1:-}; target=${2:-}
[[ $mode == rehearse || $mode == apply ]] && [[ -d $target ]] || { sed -n '2,23p' "$0" >&2; exit 2; }
dir=$(cd "$target" && pwd)
cd "$dir" || exit 2

logs=$(mktemp -d); trap 'rm -rf "$logs"' EXIT

# Values of secret-looking .env keys, used to scrub logs before printing them.
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
' "$dir/.env" "${main_dir:-$dir}/.env"
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

# ---- project settings -------------------------------------------------------------------
conf_file="$dir/.claude/devenv.conf"
[[ -f $conf_file ]] || fail checks "missing .claude/devenv.conf (create it with the dev-env skill)"
[[ -f $dir/compose.yaml || -f $dir/docker-compose.yml || -f $dir/compose.yml ]] || fail checks "no compose file"
declare -A C=([APP_SERVICE]=app [HEALTH_PATH]=/ [HEALTH_TIMEOUT]=90)
while IFS= read -r line; do
  [[ $line =~ ^[[:space:]]*([A-Z_]+)=(.*)$ ]] || continue
  key=${BASH_REMATCH[1]} val=${BASH_REMATCH[2]}
  # Quoted values may be followed by a comment; unquoted values end at " #".
  if [[ $val =~ ^\"([^\"]*)\"[[:space:]]*(#.*)?$ ]] || [[ $val =~ ^\'([^\']*)\'[[:space:]]*(#.*)?$ ]]; then
    val=${BASH_REMATCH[1]}
  else
    val=$(sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' <<<"$val")
  fi
  C[$key]=$val
done < "$conf_file"

common=$(git rev-parse --path-format=absolute --git-common-dir)
main_dir=$(dirname "$common")
project=$(basename "$main_dir")
branch=$(git branch --show-current)

env_get() { sed -n "s/^[[:space:]]*$1=//p" "$2" 2>/dev/null | tail -1 | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'; }

# sync_env <env file>: append keys from .env.example that are missing. Prints keys that are
# missing and have no default in .env.example (these need a real value from the user).
sync_env() {
  python3 - "$dir/.env.example" "$1" <<'EOF'
import re, sys, os
example, target = sys.argv[1:3]
def parse(p):
    out = {}
    if os.path.exists(p):
        for line in open(p):
            m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)", line)
            if m: out[m.group(1)] = m.group(2).strip()
    return out
ex, cur = parse(example), parse(target)
add, empty = [], []
for k, v in ex.items():
    if k in cur: continue
    (add if v not in ("", '""', "''") else empty).append((k, v))
if add:
    with open(target, "a") as f:
        for k, v in add: f.write(f"{k}={v}\n")
print(" ".join(k for k, _ in empty))
EOF
}

# Like sync_env but read-only: keys the development .env would still lack after a sync.
missing_without_default() {
  python3 - "$dir/.env.example" "$1" <<'EOF'
import re, sys, os
example, target = sys.argv[1:3]
def parse(p):
    out = {}
    if os.path.exists(p):
        for line in open(p):
            m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)", line)
            if m: out[m.group(1)] = m.group(2).strip()
    return out
ex, cur = parse(example), parse(target)
print(" ".join(k for k, v in ex.items() if k not in cur and v in ("", '""', "''")))
EOF
}

sql_engines() { for s in ${C[SHARED_SERVICES]:-}; do [[ $s == postgres || $s == mysql ]] && echo "$s"; done; }

# ---- checks -----------------------------------------------------------------------------
dirty=$(git status --porcelain --untracked-files=normal | grep -vE '^.. (docs/reports/|\.env$)' || true)
[[ -z $dirty ]] || fail checks "uncommitted changes; the rehearsed state must be committed"
[[ -f $dir/.env ]] || fail checks "missing .env"
git fetch -q origin || fail checks "git fetch failed"

if [[ $mode == rehearse ]]; then
  [[ $branch != main && $branch != development && -n $branch ]] || fail checks "rehearse runs in a feature worktree, not on '$branch'"
  git merge-base --is-ancestor origin/development HEAD || fail checks "branch is behind origin/development; update it first (push skill)"
  if [[ -n ${C[MIGRATIONS_DIR]:-} ]]; then
    changed=$(git diff --name-status origin/development...HEAD -- "${C[MIGRATIONS_DIR]}" | awk '$1 !~ /^A/ {print $NF}')
    [[ -z $changed ]] || fail checks "migrations already in origin/development were changed (write a new migration instead): $changed"
  fi
  dev_missing=$(missing_without_default "$main_dir/.env")
  [[ -z $dev_missing ]] || fail checks "development .env needs values before merge for: $dev_missing"
else
  [[ $branch == development ]] || fail checks "apply runs in the development checkout, not on '$branch'"
  [[ $(git rev-parse HEAD) == $(git rev-parse origin/development) ]] || fail checks "local development is not equal to origin/development"
fi
echo "STEP checks   ok"

# ---- env --------------------------------------------------------------------------------
empty=$(sync_env "$dir/.env")
[[ -z $empty ]] || fail env "new variables without a default in .env.example need values: $empty"
echo "STEP env      ok"

# ---- data -------------------------------------------------------------------------------
data() {
  local s
  for s in ${C[SHARED_SERVICES]:-}; do
    if [[ $mode == rehearse ]]; then "$DB" refresh "$s" "$project" "$branch" --env-file "$dir/.env" || return 1; fi
  done
  if [[ $mode == apply && -n ${C[MIGRATE_CMD]:-} ]]; then
    for s in $(sql_engines); do "$DB" backup "$s" "$project" || return 1; done
  fi
}
step data data

# ---- build, migrate, up -----------------------------------------------------------------
step build docker compose build
if [[ -n ${C[MIGRATE_CMD]:-} ]]; then
  step migrate docker compose run --rm "${C[APP_SERVICE]}" sh -c "${C[MIGRATE_CMD]}"
else
  echo "STEP migrate  skipped (no MIGRATE_CMD)"
fi
step up docker compose up -d --remove-orphans --wait --wait-timeout "${C[HEALTH_TIMEOUT]}"

# ---- health -----------------------------------------------------------------------------
health() {
  local port_var=${C[HEALTH_PORT_VAR]:-APP_PORT} port path=${C[HEALTH_PATH]} deadline host
  port=$(env_get "$port_var" "$dir/.env")
  [[ -n $port ]] || { echo "no value for $port_var in .env"; return 1; }
  local hosts=(127.0.0.1)
  command -v tailscale >/dev/null && host=$(tailscale ip -4 2>/dev/null | head -1) && [[ -n $host ]] && hosts+=("$host")
  for host in "${hosts[@]}"; do
    deadline=$((SECONDS + ${C[HEALTH_TIMEOUT]}))
    until curl -fsS -o /dev/null -m 5 "http://$host:$port$path"; do
      (( SECONDS < deadline )) || { echo "http://$host:$port$path did not respond"; return 1; }
      sleep 2
    done
    echo "http://$host:$port$path ok"
  done
}
step health health

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

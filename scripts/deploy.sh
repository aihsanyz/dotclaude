#!/usr/bin/env bash
# The one standard procedure that updates the development environment after a merge.
# The pre-merge rehearsal runs the same steps in the worktree with the same compose file and
# commands, on a fresh database (all migrations from scratch, then the seed), so the
# post-merge run only repeats what has already passed.
#
#   deploy.sh rehearse <worktree>                     pre-merge rehearsal in a feature worktree
#   deploy.sh apply    <dev checkout> [--bootstrap]   post-merge update of the development environment
#
# --bootstrap is for the first setup of the development environment: the seed runs after the
# migrations.
#
# Steps:
#   checks   rehearse: branch contains origin/development, clean tree, migrations already in
#            origin/development unchanged, development .env can take the new variables
#            apply: on development and equal to origin/development, clean tree
#   env      add variables from .env.example missing in .env (fails if a new one has no default)
#   reset    rehearse only: remove the worktree's containers and volumes (fresh database)
#   build    docker compose build
#   migrate  migrate command (after starting the image-only services such as databases)
#   seed     rehearse, and apply --bootstrap: seed command
#   up       docker compose up -d --wait (waits for the compose healthchecks)
#   health   published ports accept connections on localhost and on the Tailscale IP
#   test     rehearse only: test command
#
# Commands come from the "## Komutlar" section of the project's CLAUDE.md:
#   - service: `app`   - migrate: `...`   - test: `...`   - seed: `...`   - migrations: `dir`
# Services and ports come from the compose file that COMPOSE_FILE in .env selects (compose.dev.yaml).
# Exit: 0 ok, 1 failed, 2 usage.
set -uo pipefail

mode=${1:-}; target=${2:-}; bootstrap=0
[[ ${3:-} == --bootstrap ]] && bootstrap=1
[[ $mode == rehearse || $mode == apply ]] && [[ -d $target ]] || { sed -n '2,29p' "$0" >&2; exit 2; }
dir=$(cd "$target" && pwd) || exit 2
cd "$dir" || exit 2

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "not a git checkout: $dir" >&2; exit 2; }
main_dir=$(dirname "$common")
branch=$(git branch --show-current)
[[ $dir == "$main_dir" ]] && is_dev=1 || is_dev=0
logs=$(mktemp -d); trap 'rm -rf "$logs"' EXIT

# ---- helpers ------------------------------------------------------------------------------
fail() { echo "RESULT: fail step=$1"; [[ -n ${2:-} ]] && echo "reason: $2"; exit 1; }

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

compose_name() { sed -n 's/^[[:space:]]*COMPOSE_PROJECT_NAME=//p' "$1/.env" 2>/dev/null | tail -1 | tr -d '"'"'"; }

# Commands from the "## Komutlar" section of CLAUDE.md, as KEY=value lines.
declare -A C=()
while IFS= read -r -d '' key && IFS= read -r -d '' val; do C[$key]=$val; done < <(python3 - "$dir/CLAUDE.md" <<'EOF'
import re, sys
inside = False
try:
    lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
except OSError:
    lines = []
for line in lines:
    if re.match(r"^##\s+Komutlar\s*$", line):
        inside = True; sys.stdout.write("section\0yes\0"); continue
    if inside and re.match(r"^#{1,2}\s", line):
        break
    m = re.match(r"^\s*[-*]\s*(service|migrate|test|seed|migrations)\s*:\s*`(.+)`\s*$", line) if inside else None
    if m:
        sys.stdout.write(f"{m.group(1)}\0{m.group(2)}\0")
EOF
)

# One line per compose service: "name built|image published-ports" ("-" when none).
services() {
  docker compose config --format json 2>/dev/null | python3 -c '
import json, sys
for name, svc in json.load(sys.stdin).get("services", {}).items():
    ports = ",".join(str(p["published"]) for p in svc.get("ports", []) if p.get("published"))
    print(name, "built" if "build" in svc else "image", ports or "-")'
}

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

# ---- checks -------------------------------------------------------------------------------
[[ ${C[section]:-} == yes ]] || fail checks "no '## Komutlar' section in CLAUDE.md (run the initer skill)"
[[ -f .env ]] || fail checks "missing .env"
name=$(compose_name "$dir"); dev_name=$(compose_name "$main_dir")
[[ -n $name ]] || fail checks "no COMPOSE_PROJECT_NAME in .env"
dirty=$(git status --porcelain --untracked-files=normal | grep -vE '^.. (docs/reports/|\.env$)' || true)
[[ -z $dirty ]] || fail checks "uncommitted changes; the deployed state must be committed"
git fetch -q origin || fail checks "git fetch failed"
docker compose config -q >/dev/null 2>&1 || fail checks "docker compose config failed"
svc_list=$(services)
if [[ -n $svc_list ]]; then
  app=${C[service]:-$(awk '$2 == "built" {print $1; exit}' <<<"$svc_list")}
  [[ -n $app ]] || fail checks "no service to run the commands in (set '- service:' in CLAUDE.md)"
fi

if [[ $mode == rehearse ]]; then
  [[ $is_dev == 0 && -n $branch && $branch != main && $branch != development ]] || fail checks "rehearse runs in a feature worktree"
  [[ $name != "$dev_name" ]] || fail checks "the worktree uses the development COMPOSE_PROJECT_NAME ($dev_name)"
  git merge-base --is-ancestor origin/development HEAD || fail checks "branch is behind origin/development; update it first (push skill)"
  if [[ -n ${C[migrations]:-} ]]; then
    changed=$(git diff --name-status origin/development...HEAD -- "${C[migrations]}" | awk '$1 !~ /^A/ {print $NF}')
    [[ -z $changed ]] || fail checks "migrations already in origin/development were changed (write a new migration instead): $changed"
  fi
  if [[ -n $dev_name ]]; then  # skipped before the development environment exists (initer)
    dev_missing=$(env_keys check "$main_dir/.env")
    [[ -z $dev_missing ]] || fail checks "development .env needs values before merge for: $dev_missing"
  fi
else
  [[ $is_dev == 1 && $branch == development ]] || fail checks "apply runs in the development checkout on 'development'"
  [[ $(git rev-parse HEAD) == $(git rev-parse origin/development) ]] || fail checks "local development is not equal to origin/development"
fi
echo "STEP checks   ok"

# ---- env ----------------------------------------------------------------------------------
empty=$(env_keys sync "$dir/.env")
[[ -z $empty ]] || fail env "new variables without a default in .env.example need values: $empty"
echo "STEP env      ok"

# Record what was rehearsed so the merge can check that nothing moved since.
record_rehearsal() {
  git -C "$main_dir" config "branch.$branch.rehearsedHead" "$(git rev-parse HEAD)"
  git -C "$main_dir" config "branch.$branch.rehearsedBase" "$(git rev-parse origin/development)"
  echo "rehearsed: head=$(git rev-parse --short HEAD) base=$(git rev-parse --short origin/development)"
}

# A skeleton project (initer) has no compose services yet: nothing to build or start.
if [[ -z $svc_list ]]; then
  echo "STEP build    skipped (no services in the compose file)"
  [[ $mode == rehearse ]] && record_rehearsal
  echo "RESULT: ok"
  exit 0
fi

# ---- reset (rehearse only): fresh containers and volumes for this worktree only -------------
[[ $mode == rehearse ]] && step reset docker compose down -v --remove-orphans

# ---- build, migrate, seed, up -------------------------------------------------------------
step build docker compose build
start_images() {  # databases and other image-only services, before the commands run
  local list; list=$(services | awk '$2 == "image" {print $1}')
  [[ -z $list ]] || docker compose up -d --wait $list
}
run_cmd() { docker compose run --rm "$app" sh -c "$1"; }
migrate() { start_images && run_cmd "${C[migrate]}"; }
if [[ -n ${C[migrate]:-} ]]; then
  step migrate migrate
else
  echo "STEP migrate  skipped (no migrate command)"
fi
if [[ -n ${C[seed]:-} ]] && [[ $mode == rehearse || $bootstrap == 1 ]]; then
  step seed run_cmd "${C[seed]}"
fi
step up docker compose up -d --remove-orphans --wait --wait-timeout 120

# ---- health -------------------------------------------------------------------------------
# "up --wait" waited for the compose healthchecks; here every published port must accept
# connections from outside the containers, on localhost and on the Tailscale IP.
health() {
  local hosts=(127.0.0.1) host svc kind ports port
  command -v tailscale >/dev/null && host=$(tailscale ip -4 2>/dev/null | head -1) && [[ -n $host ]] && hosts+=("$host")
  while read -r svc kind ports; do
    [[ $ports == - ]] && continue
    for port in ${ports//,/ }; do
      for host in "${hosts[@]}"; do
        python3 -c 'import socket, sys, time
deadline = time.time() + 60
while True:
    try:
        socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=3).close(); break
    except OSError:
        if time.time() > deadline: sys.exit(1)
        time.sleep(2)' "$host" "$port" || { echo "$svc: $host:$port does not accept connections"; return 1; }
        echo "$svc: $host:$port ok"
      done
    done
  done < <(services)
}
step health health

# ---- test (rehearse only) -----------------------------------------------------------------
if [[ $mode == rehearse ]]; then
  if [[ -n ${C[test]:-} ]]; then step test run_cmd "${C[test]}"; else echo "STEP test     skipped (no test command)"; fi
  record_rehearsal
fi

echo "RESULT: ok"

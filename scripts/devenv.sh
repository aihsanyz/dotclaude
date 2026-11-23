#!/usr/bin/env bash
# Development environments for projects that follow this setup (AGENTS.md with "## Komutlar",
# compose.dev.yaml selected by COMPOSE_FILE in .env).
#
#   devenv.sh up    [dir]               worktree: .env, free ports, data services, migrate, seed, app
#   devenv.sh reset [dir]               worktree: down + up (fresh database)
#   devenv.sh down  [dir]               worktree: remove its containers, volumes and local images
#   devenv.sh stop  [dir]               any checkout: stop containers, keep data
#   devenv.sh apply [dir] [--bootstrap] main checkout on main: env sync, build, migrate, postdeploy,
#                                       up, health (seed only on first setup or with --bootstrap)
#   devenv.sh ports [dir]               print the environment's addresses
#   devenv.sh run <key> [dir]           run a ## Komutlar command (lint, test, seed, migrate) in the app container
#
# dir defaults to the current directory. Worktrees get ports from 4100-4999; the main checkout
# keeps the defaults from .env.example. Exit: 0 ok, 1 failed, 2 usage.
set -uo pipefail

PORT_MIN=4100 PORT_MAX=4999 MEM_WARN_MB=700
mode=${1:-}; shift || true
key=
if [[ $mode == run ]]; then key=${1:-}; shift || true; fi
dir=. bootstrap=0
for a in "$@"; do [[ $a == --bootstrap ]] && bootstrap=1 || dir=$a; done
case $mode in up|reset|down|stop|apply|ports|run) ;; *) sed -n '2,15p' "$0" >&2; exit 2;; esac

top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || { echo "not a git checkout: $dir" >&2; exit 2; }
cd "$top" || exit 2
common=$(git rev-parse --path-format=absolute --git-common-dir)
main_dir=$(dirname "$common")
project=$(basename "$main_dir" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-')
branch=$(git branch --show-current)
[[ $top == "$main_dir" ]] && is_main=1 || is_main=0
logs=$(mktemp -d); trap 'rm -rf "$logs"' EXIT

fail() { echo "RESULT: fail step=$1"; [[ -n ${2:-} ]] && echo "reason: $2"; exit 1; }
redact() {
  python3 -c '
import re, sys
secrets = []
try:
    for line in open(".env"):
        m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)", line)
        if m and re.search(r"PASS|SECRET|TOKEN|KEY|URL", m.group(1)) and len(m.group(2).strip()) >= 6:
            secrets.append(m.group(2).strip().strip("\"\x27"))
except OSError:
    pass
for line in sys.stdin:
    for s in secrets:
        line = line.replace(s, "****")
    sys.stdout.write(line)'
}
step() {  # step <name> <command...>
  local name=$1; shift
  printf 'STEP %-9s ' "$name"
  if "$@" >"$logs/$name.log" 2>&1; then echo ok; else
    echo FAIL; echo "--- last output of '$name':"; tail -n 40 "$logs/$name.log" | redact; fail "$name"
  fi
}

eval "$(python3 "$HOME/.claude/scripts/komutlar.py" AGENTS.md)"
[[ $HAS_KOMUTLAR == 1 ]] || fail checks "AGENTS.md has no '## Komutlar' section (run /new-project)"

# ---- .env ---------------------------------------------------------------------------------
env_get() { sed -n "s/^[[:space:]]*$1=//p" .env 2>/dev/null | tail -1 | tr -d '"'"'"; }
env_set() {  # env_set KEY VALUE: replace or append
  python3 - "$1" "$2" <<'EOF'
import re, sys
key, val = sys.argv[1:3]
try:
    lines = open(".env").read().splitlines()
except OSError:
    lines = []
for i, l in enumerate(lines):
    if re.match(rf"\s*{re.escape(key)}=", l):
        lines[i] = f"{key}={val}"
        break
else:
    lines.append(f"{key}={val}")
open(".env", "w").write("\n".join(lines) + "\n")
EOF
}
env_sync() {  # append keys from .env.example missing in .env; print the ones without a default
  python3 - <<'EOF'
import re
def parse(p):
    out = {}
    try:
        for l in open(p):
            m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)", l)
            if m: out[m.group(1)] = m.group(2).strip()
    except OSError:
        pass
    return out
ex, cur = parse(".env.example"), parse(".env")
missing = [(k, v) for k, v in ex.items() if k not in cur]
empty = [k for k, v in missing if v in ("", '""', "''")]
with open(".env", "a") as f:
    for k, v in missing:
        if k not in empty: f.write(f"{k}={v}\n")
print(" ".join(empty))
EOF
}
prepare_env() {
  [[ -f .env.example ]] || fail env "no .env.example"
  if [[ ! -f .env ]]; then cp .env.example .env; fi
  git check-ignore -q .env || fail env ".env is not ignored by git; add it to .gitignore"
  local empty; empty=$(env_sync)
  [[ -z $empty ]] || fail env "variables without a default in .env.example need values in $top/.env: $empty"
  if [[ $is_main == 1 ]]; then
    env_set COMPOSE_PROJECT_NAME "$project-dev"
  else
    local slug; slug=$(tr '[:upper:]' '[:lower:]' <<<"$branch" | tr -c 'a-z0-9\n' '-' | cut -c1-40)
    env_set COMPOSE_PROJECT_NAME "$project-${slug:-wt}"
  fi
  name=$(env_get COMPOSE_PROJECT_NAME)
}

# ---- ports (worktrees only) ---------------------------------------------------------------
used_ports() {
  ss -tlnH 2>/dev/null | awk '{print $4}' | grep -oE '[0-9]+$'
  docker ps --format '{{.Ports}}' | grep -oE ':[0-9]+->' | grep -oE '[0-9]+'
  local wt
  for wt in $(git worktree list --porcelain | sed -n 's/^worktree //p'); do
    [[ $wt == "$top" ]] && continue
    grep -hoE '^[A-Z0-9_]*_PORT=[0-9]+' "$wt/.env" 2>/dev/null | cut -d= -f2
  done
}
own_ports() { docker compose ps --format '{{.Ports}}' 2>/dev/null | grep -oE ':[0-9]+->' | grep -oE '[0-9]+'; }
assign_ports() {
  [[ $is_main == 1 ]] && return 0
  local used own key def cur p
  used=$(used_ports | sort -un); own=$(own_ports | sort -un)
  for key in $(grep -oE '^[A-Z0-9_]*_PORT=' .env.example | tr -d '='); do
    def=$(sed -n "s/^$key=//p" .env.example | tail -1); cur=$(env_get "$key")
    if [[ -n $cur && $cur != "$def" && $cur -ge $PORT_MIN && $cur -le $PORT_MAX ]] \
       && { grep -qx "$cur" <<<"$own" || ! grep -qx "$cur" <<<"$used"; }; then
      continue
    fi
    for ((p = PORT_MIN; p <= PORT_MAX; p++)); do
      grep -qx "$p" <<<"$used" || break
    done
    (( p <= PORT_MAX )) || fail ports "no free port in $PORT_MIN-$PORT_MAX"
    env_set "$key" "$p"; used=$(printf '%s\n%s\n' "$used" "$p")
  done
}

# ---- compose ------------------------------------------------------------------------------
services() {  # "name built|image published-ports"
  docker compose config --format json 2>/dev/null | python3 -c '
import json, sys
for n, s in json.load(sys.stdin).get("services", {}).items():
    ports = ",".join(str(p["published"]) for p in s.get("ports", []) if p.get("published"))
    print(n, "built" if "build" in s else "image", ports or "-")'
}
start_data() { local l; l=$(services | awk '$2 == "image" {print $1}'); [[ -z $l ]] || docker compose up -d --wait $l; }
run_cmd() { docker compose run --rm "$app" sh -c "$1"; }
addresses() {
  local lan ts port svc kind ports
  lan=$(ip -4 -br addr show scope global 2>/dev/null | awk '$2 == "UP" {split($3, a, "/"); print a[1]; exit}')
  ts=$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null)
  while read -r svc kind ports; do
    [[ $ports == - ]] && continue
    for port in ${ports//,/ }; do
      echo "URL $svc: http://${lan:-localhost}:$port${ts:+  http://$ts:$port}"
    done
  done < <(services)
}
health() {
  local hosts=(127.0.0.1) h svc kind ports port
  h=$(tailscale ip -4 2>/dev/null | head -1) && [[ -n $h ]] && hosts+=("$h")
  while read -r svc kind ports; do
    [[ $ports == - ]] && continue
    for port in ${ports//,/ }; do
      for h in "${hosts[@]}"; do
        python3 -c 'import socket, sys, time
deadline = time.time() + 60
while True:
    try:
        socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=3).close(); break
    except OSError:
        if time.time() > deadline: sys.exit(1)
        time.sleep(2)' "$h" "$port" || { echo "$svc: $h:$port does not accept connections"; return 1; }
        echo "$svc: $h:$port ok"
      done
    done
  done < <(services)
}
memory_check() {
  local avail; avail=$(free -m | awk 'NR == 2 {print $7}')
  [[ -n $avail && $avail -lt $MEM_WARN_MB ]] && echo "WARNING: only ${avail} MB memory available; stop idle worktree environments (devenv.sh stop)."
  return 0
}
require_services() {
  svc_list=$(services)
  if [[ -z $svc_list ]]; then echo "STEP compose   no services yet (skeleton project)"; echo "RESULT: ok"; exit 0; fi
  app=${K_SERVICE:-$(awk '$2 == "built" {print $1; exit}' <<<"$svc_list")}
  [[ -n $app ]] || fail compose "no service to run commands in (set '- service:' in AGENTS.md)"
}
check_name() {
  [[ -n $name ]] || fail checks "no COMPOSE_PROJECT_NAME"
  [[ $is_main == 1 || $name != "$project-dev" ]] || fail checks "worktree uses the development project name"
}

# ---- modes --------------------------------------------------------------------------------
do_up() {
  [[ $is_main == 0 ]] || fail checks "up runs in a worktree; use apply in the main checkout"
  prepare_env; check_name; assign_ports; memory_check
  step compose docker compose config -q
  require_services
  step data start_data
  [[ -n $K_MIGRATE ]] && step migrate run_cmd "$K_MIGRATE"
  [[ -n $K_SEED ]] && step seed run_cmd "$K_SEED"
  step up docker compose up -d --build --remove-orphans --wait --wait-timeout 180
  step health health
  addresses
  echo "RESULT: ok"
}
do_down() {
  [[ $is_main == 0 ]] || fail checks "down deletes data; it only runs in a worktree"
  [[ -f .env ]] || { echo "RESULT: ok (no .env, nothing to remove)"; return; }
  name=$(env_get COMPOSE_PROJECT_NAME); check_name
  step down docker compose down -v --rmi local --remove-orphans
  echo "RESULT: ok"
}
do_apply() {
  [[ $is_main == 1 && ( $branch == main || $branch == master ) ]] || fail checks "apply runs in the main checkout on main"
  git fetch -q origin || fail checks "git fetch failed"
  [[ $(git rev-parse HEAD) == $(git rev-parse "origin/$branch") ]] || fail checks "local $branch is not equal to origin/$branch"
  [[ -z $(git status --porcelain | grep -vE '^.. \.env$' || true) ]] || fail checks "uncommitted changes in the main checkout"
  prepare_env; check_name
  step compose docker compose config -q
  require_services
  [[ -z $(docker compose ps -a -q 2>/dev/null) ]] && bootstrap=1
  step build docker compose build
  step data start_data
  [[ -n $K_MIGRATE ]] && step migrate run_cmd "$K_MIGRATE"
  [[ -n $K_POSTDEPLOY ]] && step postdeploy run_cmd "$K_POSTDEPLOY"
  [[ $bootstrap == 1 && -n $K_SEED ]] && step seed run_cmd "$K_SEED"
  step up docker compose up -d --remove-orphans --wait --wait-timeout 180
  step health health
  addresses
  echo "RESULT: ok"
}

case $mode in
  up) do_up ;;
  reset) do_down >/dev/null; do_up ;;
  down) do_down ;;
  stop) [[ -f .env ]] && step stop docker compose stop; echo "RESULT: ok" ;;
  apply) do_apply ;;
  ports) [[ -f .env ]] || fail checks "no .env"; addresses ;;
  run)
    [[ $key =~ ^(lint|test|seed|migrate|postdeploy)$ ]] || { echo "usage: devenv.sh run lint|test|seed|migrate|postdeploy [dir]" >&2; exit 2; }
    [[ -f .env ]] || fail checks "no .env (run devenv.sh up first)"
    var=K_${key^^}; [[ -n ${!var} ]] || fail checks "no '$key' command in AGENTS.md"
    require_services; start_data >/dev/null
    run_cmd "${!var}"
    ;;
esac

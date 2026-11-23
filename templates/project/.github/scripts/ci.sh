#!/usr/bin/env bash
# CI checks, driven by the "## Komutlar" section of AGENTS.md. Runs on the GitHub runner with
# Docker; every project command runs inside a container.
#
#   ci.sh lint       lint command in the dev image
#   ci.sh test       test command in the dev image (data services and migrations first)
#   ci.sh rehearse   production compose: fresh database (migrate service + seed + app healthy),
#                    then the upgrade rehearsal: last v* tag's schema and seed, then HEAD's migrations
#   ci.sh scan       gitleaks over the PR range (or the full history on main) and trivy fs
#
# A skeleton project without compose services skips lint/test/rehearse.
set -euo pipefail

GITLEAKS_IMAGE="zricethezav/gitleaks:v8.30.1"
TRIVY_IMAGE="aquasec/trivy:0.76.2"
cd "$(git rev-parse --show-toplevel)"

load_komutlar() {  # reads AGENTS.md in the current directory into K_* variables
  eval "$(python3 - <<'EOF'
import re, shlex
keys = ("service", "migrate", "postdeploy", "lint", "test", "seed", "migrations")
out, inside = {}, False
for line in open("AGENTS.md", encoding="utf-8").read().splitlines():
    if re.match(r"^##\s+Komutlar\s*$", line):
        inside = True; continue
    if inside and re.match(r"^#{1,2}\s", line):
        break
    m = re.match(r"^\s*[-*]\s*(%s)\s*:\s*`(.+)`\s*$" % "|".join(keys), line) if inside else None
    if m: out[m.group(1)] = m.group(2)
for k in keys:
    print(f"K_{k.upper()}={shlex.quote(out.get(k, ''))}")
EOF
)"
}
load_komutlar

# Build a CI .env from an example file: empty values get throwaway CI values that contain
# URL-hostile characters, so credentials pasted into URLs without encoding fail in CI.
make_env() {  # make_env <example> <project name>
  python3 - "$1" "$2" <<'EOF'
import re, secrets, sys
example, name = sys.argv[1:3]
lines = []
for line in open(example):
    m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)", line)
    if m:
        k, v = m.group(1), m.group(2).strip()
        if k == "COMPOSE_PROJECT_NAME":
            v = name
        elif v in ("", '""', "''"):
            v = "ci" + secrets.token_hex(8) + "@:/%+"  # URL-hostile characters catch unencoded credentials
        lines.append(f"{k}={v}")
open(".env", "w").write("\n".join(lines) + "\n")
EOF
}
services() { docker compose config --services 2>/dev/null; }
image_services() {
  docker compose config --format json | python3 -c '
import json, sys
print(" ".join(n for n, s in json.load(sys.stdin).get("services", {}).items() if "build" not in s))'
}
app_service() {
  [[ -n $K_SERVICE ]] && { echo "$K_SERVICE"; return; }
  docker compose config --format json | python3 -c '
import json, sys
print(next((n for n, s in json.load(sys.stdin).get("services", {}).items() if "build" in s), ""))'
}
skip_if_skeleton() { [[ -n $(services) ]] || { echo "no compose services yet: $1 skipped"; exit 0; }; }
run_cmd() { docker compose run --rm "$(app_service)" sh -c "$1"; }
start_data() { local l; l=$(image_services); [[ -z $l ]] || docker compose up -d --wait $l; }

dev_env() { make_env .env.example ci-dev; skip_if_skeleton "$1"; }
prod_env() { make_env .env.production.example ci-prod; skip_if_skeleton "$1"; }

# Bring the production stack up: the app's dependencies (backup, migrate) run first.
prod_up() {
  local app; app=$(app_service)
  docker compose build
  docker compose up -d --wait --wait-timeout 180 "$app"
  if docker compose config --services | grep -qx migrate; then
    local code; code=$(docker compose ps -a migrate --format '{{.ExitCode}}' | tail -1)
    [[ $code == 0 ]] || { echo "migrate service exited with $code"; docker compose logs migrate; exit 1; }
  elif [[ -n $K_MIGRATE ]]; then
    echo "::warning::compose.prod.yaml has no migrate service; running the migrate command directly"
    run_cmd "$K_MIGRATE"
  fi
}

case ${1:-} in
  lint)
    dev_env lint
    [[ -n $K_LINT ]] || { echo "::warning::no lint command in AGENTS.md"; exit 0; }
    docker compose build
    run_cmd "$K_LINT"
    ;;
  test)
    dev_env test
    [[ -n $K_TEST ]] || { echo "::warning::no test command in AGENTS.md"; exit 0; }
    docker compose build
    start_data
    [[ -z $K_MIGRATE ]] || run_cmd "$K_MIGRATE"
    run_cmd "$K_TEST"
    ;;
  rehearse)
    prod_env rehearse
    echo "== fresh database"
    prod_up
    [[ -z $K_SEED ]] || run_cmd "$K_SEED"
    docker compose down -v --remove-orphans
    last=$(git describe --tags --abbrev=0 --match 'v[0-9]*' HEAD 2>/dev/null || true)
    if [[ -z $last ]]; then
      echo "== upgrade rehearsal skipped: no previous v* tag"
      exit 0
    fi
    echo "== upgrade rehearsal: $last -> HEAD"
    prev=$(mktemp -d)
    git worktree add -q --detach "$prev" "$last"
    cp .env "$prev/.env"
    (cd "$prev" && load_komutlar && prod_up && { [[ -z $K_SEED ]] || run_cmd "$K_SEED"; })
    prod_up
    docker compose down -v --remove-orphans
    git worktree remove --force "$prev"
    ;;
  scan)
    if [[ -n ${BASE_SHA:-} ]]; then range="$BASE_SHA..HEAD"; else range="HEAD"; fi
    echo "== gitleaks ($range)"
    docker run --rm -v "$PWD:/repo:ro" -w /repo \
      -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
      "$GITLEAKS_IMAGE" git --log-opts="$range" --redact --no-banner --exit-code 1 /repo
    echo "== trivy fs"
    docker run --rm -v "$PWD:/repo:ro" "$TRIVY_IMAGE" fs --quiet --scanners vuln,secret,misconfig \
      --severity MEDIUM,HIGH,CRITICAL --ignore-unfixed --exit-code 1 /repo
    ;;
  *) sed -n '2,11p' "$0" >&2; exit 2 ;;
esac

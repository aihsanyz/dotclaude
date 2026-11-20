#!/usr/bin/env bash
# Shared helpers for deploy.sh (sourced, not executed).
#
# devenv_load <checkout> sets: dir, main_dir, project, branch, is_dev, claude_md and the C map,
# read from the "## Komutlar" section of the project's CLAUDE.md (written by initer):
#   - service: `app`                       APP_SERVICE    compose service that runs the commands
#   - migrate: `php artisan migrate`       MIGRATE_CMD
#   - test: `php artisan test`             TEST_CMD
#   - seed: `php artisan db:seed`          SEED_CMD       first setup only
#   - migrations: `database/migrations`    MIGRATIONS_DIR
#   - engines: `db=postgres`               ENGINES        only for images whose name hides the engine
# Everything else comes from compose.yaml: data services and engines from image names, health
# from the compose healthchecks and the published ports.

devenv_load() {
  dir=$(cd "$1" && pwd) || return 1
  local common
  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "not a git checkout: $dir" >&2; return 1; }
  main_dir=$(dirname "$common")
  project=$(basename "$main_dir")
  branch=$(git -C "$dir" branch --show-current)
  [[ $dir == "$main_dir" ]] && is_dev=1 || is_dev=0
  claude_md="$dir/CLAUDE.md"

  declare -gA C=([HEALTH_TIMEOUT]=90)
  has_commands=0
  [[ -f $claude_md ]] || return 0
  local key val
  while IFS= read -r -d '' key && IFS= read -r -d '' val; do
    C[$key]=$val; has_commands=1
  done < <(python3 - "$claude_md" <<'EOF'
import re, sys
names = {"service": "APP_SERVICE", "migrate": "MIGRATE_CMD", "test": "TEST_CMD", "seed": "SEED_CMD",
         "migrations": "MIGRATIONS_DIR", "engines": "ENGINES"}
inside, found = False, False
for line in open(sys.argv[1], encoding="utf-8"):
    if re.match(r"^##\s+Komutlar\s*$", line):
        inside = found = True
        continue
    if inside and re.match(r"^#{1,2}\s", line):
        break
    m = re.match(r"^\s*[-*]\s*([a-z]+)\s*:\s*`(.+)`\s*$", line) if inside else None
    if m and m.group(1) in names:
        sys.stdout.write(f"{names[m.group(1)]}\0{m.group(2)}\0")
if found:
    sys.stdout.write("COMMANDS_SECTION\0yes\0")
EOF
  )
}

# COMPOSE_PROJECT_NAME of a checkout, from its .env (empty if missing).
compose_name() { sed -n 's/^[[:space:]]*COMPOSE_PROJECT_NAME=//p' "$1/.env" 2>/dev/null | tail -1 | tr -d '"'"'"; }

# docker compose for a checkout; loads that checkout's compose file and .env. Refuses to run
# without an explicit COMPOSE_PROJECT_NAME, so compose never falls back to the directory name
# and starts stray containers with empty volumes.
dc_in() {
  local d=$1; shift
  [[ -n $(compose_name "$d") ]] || { echo "error: $d/.env has no COMPOSE_PROJECT_NAME; the environment is not set up" >&2; return 2; }
  docker compose --project-directory "$d" "$@"
}

# compose_services <checkout>: one line per service: "name engine published-ports"
# engine is postgres|mysql|mariadb|mongodb|redis|- (derived from the image, or ENGINES override);
# published ports are comma-separated host ports ("-" if none).
compose_services() {
  dc_in "$1" config --format json 2>/dev/null | python3 -c '
import json, re, sys
cfg = json.load(sys.stdin)
override = dict(p.split("=", 1) for p in sys.argv[1].split() if "=" in p)
rules = [(r"(^|/)(postgres|postgis)", "postgres"), (r"(^|/)mysql", "mysql"), (r"(^|/)mariadb", "mariadb"),
         (r"(^|/)mongo", "mongodb"), (r"(^|/)(redis|valkey|keydb)", "redis")]
for name, svc in cfg.get("services", {}).items():
    engine = override.get(name)
    if not engine and "build" not in svc:
        image = (svc.get("image") or "").split("@")[0].split(":")[0]
        engine = next((e for pat, e in rules if re.search(pat, image)), None)
    ports = ",".join(str(p["published"]) for p in svc.get("ports", []) if p.get("published"))
    print(name, engine or "-", ports or "-")
' "${C[ENGINES]:-}"
}

# "service engine" pairs for the data services of a checkout.
data_services() { compose_services "$1" | awk '$2 != "-" {print $1, $2}'; }

copyable() { [[ $1 =~ ^(postgres|mysql|mariadb|mongodb)$ ]]; }

#!/usr/bin/env bash
# Shared helpers for deploy.sh and db.sh (sourced, not executed).
# devenv_load <checkout> sets: dir, main_dir, project, branch, is_dev, stack_file and the C
# settings map derived from <checkout>/.claude/stack.toml (written by the project-init skill):
#   DATA_SERVICES  "svc:engine ..."    services with role = "data"
#   HEALTH_CHECKS  "PORT_VAR:path ..." services with a health table
#   APP_SERVICE, MIGRATE_CMD, TEST_CMD, SEED_CMD  from [commands]
#   MIGRATIONS_DIR from [migrations].dir, HEALTH_TIMEOUT from [project].health_timeout

devenv_load() {
  dir=$(cd "$1" && pwd) || return 1
  local common
  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "not a git checkout: $dir" >&2; return 1; }
  main_dir=$(dirname "$common")
  project=$(basename "$main_dir")
  branch=$(git -C "$dir" branch --show-current)
  [[ $dir == "$main_dir" ]] && is_dev=1 || is_dev=0

  declare -gA C=([APP_SERVICE]=app [HEALTH_TIMEOUT]=90)
  stack_file="$dir/.claude/stack.toml"
  [[ -f $stack_file ]] || return 0
  local key val
  # tomllib is in the Python standard library (3.11+); values come back NUL-separated.
  while IFS= read -r -d '' key && IFS= read -r -d '' val; do
    C[$key]=$val
  done < <(python3 - "$stack_file" <<'EOF'
import sys, tomllib
try:
    s = tomllib.load(open(sys.argv[1], "rb"))
except tomllib.TOMLDecodeError as e:
    sys.exit(f"invalid {sys.argv[1]}: {e}")
out = {}
services = s.get("services", {})
out["DATA_SERVICES"] = " ".join(f"{n}:{v['engine']}" for n, v in services.items()
                                if v.get("role") == "data" and v.get("engine"))
out["HEALTH_CHECKS"] = " ".join(f"{v['health']['port_var']}:{v['health'].get('path', '/')}"
                                for v in services.values() if isinstance(v.get("health"), dict))
cmd = s.get("commands", {})
for key, name in (("APP_SERVICE", "service"), ("MIGRATE_CMD", "migrate"), ("TEST_CMD", "test"), ("SEED_CMD", "seed")):
    if cmd.get(name): out[key] = cmd[name]
if s.get("migrations", {}).get("dir"): out["MIGRATIONS_DIR"] = s["migrations"]["dir"]
if s.get("project", {}).get("health_timeout"): out["HEALTH_TIMEOUT"] = str(s["project"]["health_timeout"])
for k, v in out.items():
    sys.stdout.write(f"{k}\0{v}\0")
EOF
  )
}

# docker compose for a checkout; loads that checkout's compose file and .env.
dc_in() { local d=$1; shift; docker compose --project-directory "$d" "$@"; }

# "service engine" pairs from DATA_SERVICES="db:postgres cache:redis".
data_services() {
  local spec
  for spec in ${C[DATA_SERVICES]:-}; do echo "${spec%%:*} ${spec#*:}"; done
}

copyable() { [[ $1 =~ ^(postgres|mysql|mariadb|mongodb)$ ]]; }

slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'; }

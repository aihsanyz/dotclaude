#!/usr/bin/env bash
# Shared helpers for deploy.sh and db.sh (sourced, not executed).
# devenv_load <checkout> sets: dir, main_dir, project, branch, is_dev and the C settings map
# read from <checkout>/.claude/devenv.conf.

devenv_load() {
  dir=$(cd "$1" && pwd) || return 1
  local common
  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "not a git checkout: $dir" >&2; return 1; }
  main_dir=$(dirname "$common")
  project=$(basename "$main_dir")
  branch=$(git -C "$dir" branch --show-current)
  [[ $dir == "$main_dir" ]] && is_dev=1 || is_dev=0

  declare -gA C=([APP_SERVICE]=app [HEALTH_TIMEOUT]=90)
  local conf="$dir/.claude/devenv.conf" line key val
  [[ -f $conf ]] || return 0
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
  done < "$conf"
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

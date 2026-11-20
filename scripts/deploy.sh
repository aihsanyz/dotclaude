#!/usr/bin/env bash
# The one standard procedure that updates the development environment after a merge.
# The pre-merge rehearsal runs the same steps in the worktree, with the same compose file,
# commands and a fresh copy of the development data, so the post-merge run only repeats
# what has already passed.
#
#   deploy.sh rehearse  <worktree>      [--bootstrap]  pre-merge rehearsal in a feature worktree
#   deploy.sh apply     <dev checkout>  [--bootstrap]  post-merge update of the development environment
#   deploy.sh copy-data <worktree>                     replace worktree data with a copy of development
#
# --bootstrap is for the first merge of a project (initer), before a development environment
# exists: data services start empty and the seed command runs after the migrations.
#
# Steps (rehearse and apply, same order):
#   checks   rehearse: branch contains origin/development, clean tree, migrations already in
#            origin/development unchanged, development .env can take the new variables
#            apply: on development and equal to origin/development, clean tree
#   env      add variables from .env.example missing in .env (fails if a new one has no default)
#   data     start the data services; rehearse also copies the development data in
#   build    docker compose build
#   migrate  migrate command in the command service
#   up       docker compose up -d --wait (waits for the compose healthchecks)
#   health   published ports answer on localhost and on the Tailscale IP
#   test     rehearse only: test command in the command service
#
# Commands come from the "## Komutlar" section of the project's CLAUDE.md; services, engines and
# ports come from compose.yaml. Exit: 0 ok, 1 failed.
set -uo pipefail
source "$HOME/.claude/scripts/devenv-lib.sh"

mode=${1:-}; target=${2:-}; bootstrap=0
[[ ${3:-} == --bootstrap ]] && bootstrap=1
[[ $mode =~ ^(rehearse|apply|copy-data)$ ]] && [[ -d $target ]] || { sed -n '2,27p' "$0" >&2; exit 2; }
devenv_load "$target" || exit 2
cd "$dir" || exit 2

die() { echo "error: $*" >&2; exit 2; }

# ---- data copy ----------------------------------------------------------------------------
# Shell run inside the data container; variables expand there (official image variables).
dump_script() {
  case $1 in
    postgres) echo 'pg_dump -U "$POSTGRES_USER" -Fc "${POSTGRES_DB:-$POSTGRES_USER}"' ;;
    mysql)    echo 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump -uroot --single-transaction --routines --triggers --events "$MYSQL_DATABASE"' ;;
    mariadb)  echo 'MYSQL_PWD="${MARIADB_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD}" mariadb-dump -uroot --single-transaction --routines --triggers --events "${MARIADB_DATABASE:-$MYSQL_DATABASE}"' ;;
    mongodb)  echo 'mongodump --quiet --archive -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin' ;;
  esac
}
restore_script() {
  case $1 in
    postgres) echo 'd="${POSTGRES_DB:-$POSTGRES_USER}"; psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d template1 -c "DROP DATABASE IF EXISTS \"$d\" WITH (FORCE)" -c "CREATE DATABASE \"$d\"" && pg_restore -U "$POSTGRES_USER" -d "$d" --no-owner --exit-on-error' ;;
    mysql)    echo 'export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; mysql -uroot -e "DROP DATABASE IF EXISTS \`$MYSQL_DATABASE\`; CREATE DATABASE \`$MYSQL_DATABASE\`" && mysql -uroot "$MYSQL_DATABASE"' ;;
    mariadb)  echo 'export MYSQL_PWD="${MARIADB_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD}"; d="${MARIADB_DATABASE:-$MYSQL_DATABASE}"; mariadb -uroot -e "DROP DATABASE IF EXISTS \`$d\`; CREATE DATABASE \`$d\`" && mariadb -uroot "$d"' ;;
    mongodb)  echo 'mongorestore --quiet --archive --drop -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin' ;;
  esac
}

copy_data() {
  [[ $is_dev == 0 ]] || die "copy-data runs in a worktree, not in the development checkout"
  local dev_name wt_name svc engine
  dev_name=$(compose_name "$main_dir"); wt_name=$(compose_name "$dir")
  [[ -n $dev_name ]] || die "the development environment is not set up (no COMPOSE_PROJECT_NAME in $main_dir/.env)"
  [[ -n $wt_name && $wt_name != "$dev_name" ]] || die "the worktree needs its own COMPOSE_PROJECT_NAME in .env, different from development ($dev_name)"
  while read -r svc engine; do
    if ! copyable "$engine"; then echo "copy: $svc ($engine) starts empty"; continue; fi
    dc_in "$main_dir" up -d --wait "$svc" >/dev/null 2>&1 || die "$svc did not start in development"
    dc_in "$dir" up -d --wait "$svc" >/dev/null 2>&1 || die "$svc did not start in the worktree"
    dc_in "$main_dir" exec -T "$svc" sh -c "$(dump_script "$engine")" \
      | dc_in "$dir" exec -T "$svc" sh -c "$(restore_script "$engine")" >/dev/null \
      || die "copy of $svc from development failed"
    echo "copy: $svc ($engine) copied from development"
  done < <(data_services "$dir")
}

if [[ $mode == copy-data ]]; then copy_data; exit 0; fi

# ---- reporting ----------------------------------------------------------------------------
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
[[ ${C[COMMANDS_SECTION]:-} == yes ]] || fail checks "no '## Komutlar' section in CLAUDE.md (run the initer skill)"
[[ -f $dir/compose.yaml || -f $dir/compose.yml || -f $dir/docker-compose.yml || -f $dir/docker-compose.yaml ]] || fail checks "no compose file"
[[ -f $dir/.env ]] || fail checks "missing .env"
dirty=$(git status --porcelain --untracked-files=normal | grep -vE '^.. (docs/reports/|\.env$)' || true)
[[ -z $dirty ]] || fail checks "uncommitted changes; the deployed state must be committed"
git fetch -q origin || fail checks "git fetch failed"
app_service=${C[APP_SERVICE]:-$(compose_services "$dir" | awk '$2 == "-" {print $1; exit}')}
[[ -n $app_service ]] || fail checks "no service to run the commands in (set '- service:' in CLAUDE.md)"

if [[ $mode == rehearse ]]; then
  [[ $is_dev == 0 && -n $branch && $branch != main && $branch != development ]] || fail checks "rehearse runs in a feature worktree"
  git merge-base --is-ancestor origin/development HEAD || fail checks "branch is behind origin/development; update it first (push skill)"
  if [[ -n ${C[MIGRATIONS_DIR]:-} ]]; then
    changed=$(git diff --name-status origin/development...HEAD -- "${C[MIGRATIONS_DIR]}" | awk '$1 !~ /^A/ {print $NF}')
    [[ -z $changed ]] || fail checks "migrations already in origin/development were changed (write a new migration instead): $changed"
  fi
  if [[ $bootstrap == 0 ]]; then
    [[ -n $(compose_name "$main_dir") ]] || fail checks "the development environment is not set up yet; the first merge of a project (initer) uses --bootstrap"
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

# ---- data ---------------------------------------------------------------------------------
data() {
  local svc engine
  while read -r svc engine; do
    dc_in "$dir" up -d --wait "$svc" || return 1
  done < <(data_services "$dir")
  if [[ $mode == rehearse && $bootstrap == 0 ]]; then copy_data; fi
}
if [[ -n $(data_services "$dir") ]]; then step data data; else echo "STEP data     skipped (no data services)"; fi

# ---- build, migrate, up -------------------------------------------------------------------
step build docker compose build
if [[ -n ${C[MIGRATE_CMD]:-} ]]; then
  step migrate docker compose run --rm "$app_service" sh -c "${C[MIGRATE_CMD]}"
else
  echo "STEP migrate  skipped (no migrate command)"
fi
if [[ $bootstrap == 1 && -n ${C[SEED_CMD]:-} ]]; then
  step seed docker compose run --rm "$app_service" sh -c "${C[SEED_CMD]}"
fi
step up docker compose up -d --remove-orphans --wait --wait-timeout "${C[HEALTH_TIMEOUT]}"

# ---- health -------------------------------------------------------------------------------
# The compose healthchecks were awaited by "up --wait"; here every published port must accept
# connections from outside the container, on localhost and on the Tailscale IP.
health() {
  local hosts=(127.0.0.1) host svc engine ports port
  command -v tailscale >/dev/null && host=$(tailscale ip -4 2>/dev/null | head -1) && [[ -n $host ]] && hosts+=("$host")
  while read -r svc engine ports; do
    [[ $ports == - ]] && continue
    for port in ${ports//,/ }; do
      for host in "${hosts[@]}"; do
        python3 -c 'import socket, sys, time
deadline = time.time() + int(sys.argv[3])
while True:
    try:
        socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=3).close(); break
    except OSError:
        if time.time() > deadline: sys.exit(1)
        time.sleep(2)' "$host" "$port" "${C[HEALTH_TIMEOUT]}" || { echo "$svc: $host:$port does not accept connections"; return 1; }
        echo "$svc: $host:$port ok"
      done
    done
  done < <(compose_services "$dir")
}
step health health

# ---- test (rehearse only) -----------------------------------------------------------------
if [[ $mode == rehearse ]]; then
  if [[ -n ${C[TEST_CMD]:-} ]]; then
    step test docker compose run --rm "$app_service" sh -c "${C[TEST_CMD]}"
  else
    echo "STEP test     skipped (no test command)"
  fi
  # Record what was rehearsed so the merge can check that nothing moved since.
  git -C "$main_dir" config "branch.$branch.rehearsedHead" "$(git rev-parse HEAD)"
  git -C "$main_dir" config "branch.$branch.rehearsedBase" "$(git rev-parse origin/development)"
  echo "rehearsed: head=$(git rev-parse --short HEAD) base=$(git rev-parse --short origin/development)"
fi

echo "RESULT: ok"

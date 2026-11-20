#!/usr/bin/env bash
# Shared development databases (postgres, mysql, redis) for projects and worktrees.
#
#   db.sh init    <engine> <project> --env-file <path>          project user + <project>_dev
#   db.sh clone   <engine> <project> <branch> --env-file <path> worktree copy of <project>_dev
#   db.sh drop    <engine> <project> <branch>                   drop a worktree database
#   db.sh backup  <engine> <project>                            dump <project>_dev (keeps last 5)
#   db.sh restore <engine> <project> <dump-file> --yes          restore <project>_dev from a dump
#   db.sh list    [engine]                                      list databases / redis users
#
# engine: postgres | mysql | redis. Redis has no databases: init creates an ACL user limited to
# `<project>:*` keys, clone hands out the prefix `<project>:<branch>:`, drop deletes those keys.
# Credentials are written straight into the given .env file and never printed.
set -euo pipefail

COMPOSE_FILE="$HOME/.claude/infra/compose.yaml"
STATE_DIR="$HOME/infra/shared"
SECRETS="$STATE_DIR/.env"
CREDS_DIR="$STATE_DIR/credentials"
BACKUP_DIR="$STATE_DIR/backups"
KEEP_BACKUPS=5

die() { echo "error: $*" >&2; exit 2; }
dc() { docker compose -f "$COMPOSE_FILE" --env-file "$SECRETS" "$@"; }
rand() { head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

# Identifiers: lowercase, [a-z0-9_] only, so they are safe to embed in SQL.
slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+|_+$//g'; }

ensure_secrets() {
  mkdir -p "$STATE_DIR" "$CREDS_DIR" "$BACKUP_DIR"
  chmod 700 "$STATE_DIR" "$CREDS_DIR" "$BACKUP_DIR"
  if [[ ! -f "$SECRETS" ]]; then
    umask 077
    printf 'POSTGRES_ADMIN_PASSWORD=%s\nMYSQL_ROOT_PASSWORD=%s\nREDIS_ADMIN_PASSWORD=%s\n' "$(rand)" "$(rand)" "$(rand)" > "$SECRETS"
  fi
  # shellcheck disable=SC1090
  source "$SECRETS"
}

ensure_up() {
  local svc=$1
  dc up -d --wait "$svc" >/dev/null 2>&1 || { dc up -d --wait "$svc"; die "$svc did not become healthy"; }
}

# Per-project password, created once and reused for every worktree of the project.
project_password() {
  local file="$CREDS_DIR/$1-$2.env"
  if [[ ! -f "$file" ]]; then (umask 077; echo "PASSWORD=$(rand)" > "$file"); fi
  sed -n 's/^PASSWORD=//p' "$file"
}

set_env() {  # set_env <file> <key> <value>: replace or append, value never echoed
  python3 - "$1" "$2" "$3" <<'EOF'
import sys, re, os
path, key, value = sys.argv[1:4]
lines = open(path).read().splitlines() if os.path.exists(path) else []
pat = re.compile(rf"^\s*{re.escape(key)}=")
out, done = [], False
for line in lines:
    if pat.match(line):
        if not done:
            out.append(f"{key}={value}")
            done = True
    else:
        out.append(line)
if not done:
    out.append(f"{key}={value}")
open(path, "w").write("\n".join(out) + "\n")
EOF
}

write_sql_env() {  # write_sql_env <env-file> <engine> <db> <user> <password>
  local f=$1 engine=$2 db=$3 user=$4 pass=$5 port scheme
  [[ $engine == postgres ]] && { port=5432; scheme=postgresql; } || { port=3306; scheme=mysql; }
  set_env "$f" DB_HOST "$engine"
  set_env "$f" DB_PORT "$port"
  set_env "$f" DB_NAME "$db"
  set_env "$f" DB_USER "$user"
  set_env "$f" DB_PASSWORD "$pass"
  set_env "$f" DATABASE_URL "$scheme://$user:$pass@$engine:$port/$db"
}

psql_admin() { dc exec -T postgres psql -v ON_ERROR_STOP=1 -q -U admin -d postgres "$@"; }
mysql_root() { dc exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql "$@"; }
redis_admin() { dc exec -T -e REDISCLI_AUTH="$REDIS_ADMIN_PASSWORD" redis redis-cli --no-auth-warning "$@"; }

pg_db_exists() { [[ $(psql_admin -tAc "SELECT 1 FROM pg_database WHERE datname='$1'") == 1 ]]; }
my_db_exists() { [[ -n $(mysql_root mysql -uroot -N -e "SHOW DATABASES LIKE '$1'") ]]; }

cmd_init() {
  local engine=$1 proj; proj=$(slug "$2"); local envf=$3
  local pass; pass=$(project_password "$engine" "$proj")
  ensure_up "$engine"
  case $engine in
    postgres)
      psql_admin -c "DO \$\$BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='$proj') THEN CREATE ROLE $proj LOGIN; END IF; END\$\$;"
      psql_admin -c "ALTER ROLE $proj WITH LOGIN PASSWORD '$pass';"
      pg_db_exists "${proj}_dev" || psql_admin -c "CREATE DATABASE ${proj}_dev OWNER $proj;"
      psql_admin -c "REVOKE CONNECT ON DATABASE ${proj}_dev FROM PUBLIC;"
      write_sql_env "$envf" postgres "${proj}_dev" "$proj" "$pass" ;;
    mysql)
      mysql_root mysql -uroot -e "CREATE USER IF NOT EXISTS '$proj'@'%' IDENTIFIED BY '$pass';
        ALTER USER '$proj'@'%' IDENTIFIED BY '$pass';
        GRANT ALL PRIVILEGES ON \`${proj}\\_%\`.* TO '$proj'@'%';
        CREATE DATABASE IF NOT EXISTS \`${proj}_dev\`;"
      write_sql_env "$envf" mysql "${proj}_dev" "$proj" "$pass" ;;
    redis)
      redis_admin ACL SETUSER "$proj" on ">$pass" resetkeys "~$proj:*" resetchannels "&$proj:*" +@all -@admin -@dangerous >/dev/null
      redis_admin ACL SAVE >/dev/null
      set_env "$envf" REDIS_URL "redis://$proj:$pass@redis:6379/0"
      set_env "$envf" REDIS_PREFIX "$proj:dev:" ;;
  esac
  echo "init: $engine project '$proj' ready (dev: ${proj}_dev); credentials written to $envf"
}

cmd_clone() {
  local engine=$1 proj br; proj=$(slug "$2"); br=$(slug "$3"); local envf=$4
  local db="${proj}_${br}"; db=${db:0:63}
  [[ $br != dev ]] || die "branch slug 'dev' is reserved for the development database"
  local pass; pass=$(project_password "$engine" "$proj")
  ensure_up "$engine"
  case $engine in
    postgres)
      pg_db_exists "${proj}_dev" || die "${proj}_dev does not exist; run: db.sh init postgres $proj --env-file <dev .env>"
      pg_db_exists "$db" && die "$db already exists"
      psql_admin -c "CREATE DATABASE $db OWNER $proj;"
      psql_admin -c "REVOKE CONNECT ON DATABASE $db FROM PUBLIC;"
      dc exec -T postgres sh -c "pg_dump -U admin -Fc ${proj}_dev | pg_restore -U admin -d $db --no-owner --role=$proj --exit-on-error"
      write_sql_env "$envf" postgres "$db" "$proj" "$pass" ;;
    mysql)
      my_db_exists "${proj}_dev" || die "${proj}_dev does not exist; run: db.sh init mysql $proj --env-file <dev .env>"
      my_db_exists "$db" && die "$db already exists"
      mysql_root mysql -uroot -e "CREATE DATABASE \`$db\`;"
      dc exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql sh -c \
        "mysqldump -uroot --single-transaction --routines --triggers --events ${proj}_dev | mysql -uroot $db"
      write_sql_env "$envf" mysql "$db" "$proj" "$pass" ;;
    redis)
      set_env "$envf" REDIS_URL "redis://$proj:$pass@redis:6379/0"
      set_env "$envf" REDIS_PREFIX "$proj:$br:" ;;
  esac
  echo "clone: $engine '$db' ready from ${proj}_dev; credentials written to $envf"
}

cmd_drop() {
  local engine=$1 proj br; proj=$(slug "$2"); br=$(slug "$3")
  [[ $br != dev ]] || die "refusing to drop the development database"
  local db="${proj}_${br}"; db=${db:0:63}
  ensure_up "$engine"
  case $engine in
    postgres) psql_admin -c "DROP DATABASE IF EXISTS $db WITH (FORCE);" ;;
    mysql)    mysql_root mysql -uroot -e "DROP DATABASE IF EXISTS \`$db\`;" ;;
    redis)
      dc exec -T -e REDISCLI_AUTH="$REDIS_ADMIN_PASSWORD" redis sh -c \
        "redis-cli --no-auth-warning --scan --pattern '$proj:$br:*' | xargs -r -n 500 redis-cli --no-auth-warning unlink >/dev/null" ;;
  esac
  echo "drop: $engine '$db' removed"
}

cmd_backup() {
  local engine=$1 proj; proj=$(slug "$2")
  local dir="$BACKUP_DIR/$engine" ts; ts=$(date +%Y%m%d-%H%M%S)
  mkdir -p "$dir"; chmod 700 "$dir"
  local out="$dir/${proj}_dev-$ts.sql.gz"
  ensure_up "$engine"
  case $engine in
    postgres) dc exec -T postgres pg_dump -U admin --clean --if-exists --no-owner "${proj}_dev" | gzip > "$out" ;;
    mysql)    dc exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysqldump -uroot --single-transaction --routines --triggers --events "${proj}_dev" | gzip > "$out" ;;
    redis)    die "redis has no per-project backup; data is persisted with appendonly" ;;
  esac
  chmod 600 "$out"
  ls -1t "$dir"/"${proj}"_dev-*.sql.gz | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -f
  echo "backup: $out"
}

cmd_restore() {
  local engine=$1 proj; proj=$(slug "$2"); local file=$3 confirm=${4:-}
  [[ $confirm == --yes ]] || die "restore overwrites ${proj}_dev; ask the user, then pass --yes"
  [[ -f $file ]] || die "dump not found: $file"
  ensure_up "$engine"
  case $engine in
    # Restore as the project role so restored objects belong to the project, not to admin.
    postgres) { echo "SET ROLE $proj;"; gunzip -c "$file"; } \
                | dc exec -T postgres psql -v ON_ERROR_STOP=1 -q -U admin -d "${proj}_dev" >/dev/null ;;
    mysql)    gunzip -c "$file" | dc exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot "${proj}_dev" ;;
    *)        die "restore is not supported for $engine" ;;
  esac
  echo "restore: ${proj}_dev restored from $file"
}

cmd_list() {
  local engines=${1:-"postgres mysql redis"}
  for e in $engines; do
    dc ps --status running --services 2>/dev/null | grep -qx "$e" || { echo "$e: not running"; continue; }
    case $e in
      postgres) echo "postgres:"; psql_admin -tAc "SELECT '  '||datname FROM pg_database WHERE datname NOT IN ('postgres','template0','template1','admin') ORDER BY 1" ;;
      mysql)    echo "mysql:"; mysql_root mysql -uroot -N -e "SHOW DATABASES" | grep -vE '^(information_schema|mysql|performance_schema|sys)$' | sed 's/^/  /' ;;
      redis)    echo "redis users:"; redis_admin ACL USERS | grep -v '^default$' | sed 's/^/  /' ;;
    esac
  done
}

main() {
  local cmd=${1:-} envf=""
  [[ -n $cmd ]] || { sed -n '2,14p' "$0"; exit 2; }
  shift
  local args=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env-file) envf=${2:?--env-file needs a path}; shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  ensure_secrets
  local engine=${args[0]:-}
  if [[ $cmd != list ]]; then
    [[ $engine =~ ^(postgres|mysql|redis)$ ]] || die "engine must be postgres, mysql or redis"
  fi
  case $cmd in
    init)    [[ -n $envf && -n ${args[1]:-} ]] || die "usage: db.sh init <engine> <project> --env-file <path>"
             cmd_init "$engine" "${args[1]}" "$envf" ;;
    clone)   [[ -n $envf && -n ${args[2]:-} ]] || die "usage: db.sh clone <engine> <project> <branch> --env-file <path>"
             cmd_clone "$engine" "${args[1]}" "${args[2]}" "$envf" ;;
    drop)    [[ -n ${args[2]:-} ]] || die "usage: db.sh drop <engine> <project> <branch>"
             cmd_drop "$engine" "${args[1]}" "${args[2]}" ;;
    backup)  [[ -n ${args[1]:-} ]] || die "usage: db.sh backup <engine> <project>"
             cmd_backup "$engine" "${args[1]}" ;;
    restore) [[ -n ${args[2]:-} ]] || die "usage: db.sh restore <engine> <project> <dump-file> --yes"
             cmd_restore "$engine" "${args[1]}" "${args[2]}" "${args[3]:-}" ;;
    list)    cmd_list "${engine:-}" ;;
    *)       die "unknown command: $cmd" ;;
  esac
}

main "$@"

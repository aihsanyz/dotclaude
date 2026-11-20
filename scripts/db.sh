#!/usr/bin/env bash
# Data services of a project's environments. Every environment (the development checkout and
# each worktree) runs its own data containers from the project's compose file; this script
# copies and backs up their data.
#
#   db.sh copy-from-dev <worktree> [service...]       replace worktree data with a copy of development
#   db.sh backup        <checkout> [service...]       dump data (development keeps 5, worktree keeps 1)
#   db.sh restore       <checkout> <service> <file> --yes
#   db.sh backups       <checkout>                    list backups of the checkout
#   db.sh forget        <worktree>                    delete the worktree's backups
#
# Services and engines come from the data services in .claude/stack.toml (role = "data", engine = ...).
# Copyable engines: postgres, mysql, mariadb, mongodb. Others (redis, ...) start empty.
# Credentials are read inside the container from the official image variables
# (POSTGRES_*, MYSQL_*, MARIADB_*, MONGO_INITDB_*); they are never printed.
set -euo pipefail
source "$HOME/.claude/scripts/devenv-lib.sh"

BACKUP_ROOT="$HOME/infra/backups"
KEEP_DEV_BACKUPS=5

die() { echo "error: $*" >&2; exit 2; }

# Shell scripts run inside the data container; variables expand there, not on the host.
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

engine_of() {  # engine_of <service>
  local s e
  while read -r s e; do [[ $s == "$1" ]] && { echo "$e"; return; }; done < <(data_services)
  die "service '$1' is not listed in DATA_SERVICES"
}

selected() {  # services from args, or all from DATA_SERVICES
  if [[ $# -gt 0 ]]; then printf '%s\n' "$@"; else data_services | awk '{print $1}'; fi
}

ensure_up() { dc_in "$1" up -d --wait "$2" >/dev/null 2>&1 || { dc_in "$1" up -d --wait "$2"; die "$2 did not start in $1"; }; }

label() { [[ $is_dev == 1 ]] && echo "dev-$(date +%Y%m%d-%H%M%S)" || echo "wt-$(slug "$branch")"; }

cmd_copy_from_dev() {
  [[ $is_dev == 0 ]] || die "copy-from-dev runs in a worktree, not in the development checkout"
  local dev_name wt_name; dev_name=$(compose_name "$main_dir"); wt_name=$(compose_name "$dir")
  [[ -n $dev_name ]] || die "the development environment is not set up (no COMPOSE_PROJECT_NAME in $main_dir/.env)"
  [[ -n $wt_name && $wt_name != "$dev_name" ]] || die "the worktree needs its own COMPOSE_PROJECT_NAME in .env, different from development ($dev_name)"
  local wt=$dir svc engine
  for svc in $(selected "$@"); do
    engine=$(engine_of "$svc")
    if ! copyable "$engine"; then echo "copy: $svc ($engine) is not copyable, starts empty"; continue; fi
    ensure_up "$main_dir" "$svc"
    ensure_up "$wt" "$svc"
    dc_in "$main_dir" exec -T "$svc" sh -c "$(dump_script "$engine")" \
      | dc_in "$wt" exec -T "$svc" sh -c "$(restore_script "$engine")" \
      || die "copy of $svc from development failed"
    echo "copy: $svc ($engine) copied from development"
  done
}

cmd_backup() {
  local svc engine out lbl; lbl=$(label)
  for svc in $(selected "$@"); do
    engine=$(engine_of "$svc")
    copyable "$engine" || { echo "backup: $svc ($engine) skipped, not a database"; continue; }
    ensure_up "$dir" "$svc"
    mkdir -p "$BACKUP_ROOT/$project/$svc"; chmod 700 "$BACKUP_ROOT" "$BACKUP_ROOT/$project" "$BACKUP_ROOT/$project/$svc"
    out="$BACKUP_ROOT/$project/$svc/$lbl.gz"
    (umask 077; dc_in "$dir" exec -T "$svc" sh -c "$(dump_script "$engine")" | gzip > "$out") || die "backup of $svc failed"
    if [[ $is_dev == 1 ]]; then
      ls -1t "$BACKUP_ROOT/$project/$svc"/dev-*.gz | tail -n +$((KEEP_DEV_BACKUPS + 1)) | xargs -r rm -f
    fi
    echo "backup: $out"
  done
}

cmd_restore() {
  local svc=$1 file=$2 confirm=${3:-} engine
  [[ $confirm == --yes ]] || die "restore overwrites $svc data in $dir; ask the user, then pass --yes"
  [[ -f $file ]] || die "backup not found: $file"
  engine=$(engine_of "$svc")
  copyable "$engine" || die "$svc ($engine) cannot be restored"
  ensure_up "$dir" "$svc"
  gunzip -c "$file" | dc_in "$dir" exec -T "$svc" sh -c "$(restore_script "$engine")" >/dev/null || die "restore failed"
  echo "restore: $svc restored from $file"
}

cmd_backups() {
  local pat; [[ $is_dev == 1 ]] && pat='dev-*.gz' || pat="wt-$(slug "$branch").gz"
  find "$BACKUP_ROOT/$project" -name "$pat" -printf '%TY-%Tm-%Td %TH:%TM  %p\n' 2>/dev/null | sort -r || true
}

cmd_forget() {
  [[ $is_dev == 0 ]] || die "forget only removes worktree backups"
  find "$BACKUP_ROOT/$project" -name "wt-$(slug "$branch").gz" -delete 2>/dev/null || true
  echo "forget: worktree backups of '$branch' removed"
}

main() {
  local cmd=${1:-} target=${2:-}
  [[ -n $cmd && -n $target ]] || { sed -n '2,16p' "$0"; exit 2; }
  shift 2
  devenv_load "$target" || die "cannot load $target"
  [[ -n ${C[DATA_SERVICES]:-} ]] || die "no data services in $dir/.claude/stack.toml"
  case $cmd in
    copy-from-dev) cmd_copy_from_dev "$@" ;;
    backup)        cmd_backup "$@" ;;
    restore)       [[ $# -ge 2 ]] || die "usage: db.sh restore <checkout> <service> <file> --yes"; cmd_restore "$@" ;;
    backups)       cmd_backups ;;
    forget)        cmd_forget ;;
    *)             die "unknown command: $cmd" ;;
  esac
}

main "$@"

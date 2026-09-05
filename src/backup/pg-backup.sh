#!/usr/bin/env bash
# Nightly dump of every pg1c database into $PG_BACKUP_DIR (mounted as
# /backups in the container). Runs from launchd (local.pg1c.backup, 5:37)
# or by hand from the repo.
#
# Change detection: an activity fingerprint per database from
# pg_stat_database (transaction/row counters + size). Unchanged since the
# last dump -> no dump. Fingerprints are re-read AFTER dumping: pg_dump
# itself creates transactions, without this every db would look "changed"
# forever.
set -uo pipefail

# launchd starts jobs with a bare PATH lacking /usr/local/bin where docker
# lives; without this the script would decide "docker is down" and silently
# skip the backup
PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Backup root: PG_BACKUP_DIR from the repo .env (the same variable
# docker-compose mounts as /backups), fallback $HOME/pg1c-backups.
# Relative values are resolved against the repo root (compose treats them
# the same way).
BACKUP_ROOT="$(grep -E '^PG_BACKUP_DIR=' "$REPO_ROOT/.env" 2>/dev/null | tail -1 | cut -d= -f2-)"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/pg1c-backups}"
case "$BACKUP_ROOT" in
    /*) ;;
    *)  BACKUP_ROOT="$REPO_ROOT/${BACKUP_ROOT#./}" ;;
esac
PG_SUBDIR="pg1c"
OUT_DIR="$BACKUP_ROOT/$PG_SUBDIR/$(date +%F)"
STATE_DIR="$BACKUP_ROOT/$PG_SUBDIR/.state"
LOG="$BACKUP_ROOT/$PG_SUBDIR/backup.log"
CTR="pg1c"

log() { printf '%s [%s] %s\n' "$(date '+%F %T')" "$1" "$2" >> "$LOG"; }

mkdir -p "$OUT_DIR" "$STATE_DIR" 2>/dev/null || { echo "нет прав на $BACKUP_ROOT" >&2; exit 1; }

# Docker down -> exit 0: launchd will retry next night anyway
if ! docker info >/dev/null 2>&1; then
  log WARN "docker не запущен — пропуск запуска"
  exit 0
fi

# SQL runs inside the container; creds come from its own env and never
# leave the container
run_pg() {
  docker exec "$CTR" sh -c 'PGPASSWORD="${POSTGRES_PASSWORD:-$PGPASSWORD}" psql -U "${POSTGRES_USER:-postgres}" -Atq -d postgres -c "'"$1"'"'
}

# Fingerprint: datname|commits.rollbacks.ins.upd.del.size
# "postgres" is excluded: this script itself queries it — the counters move
# because of us, the db would count as "changed" forever (roles go into
# globals.sql anyway)
FP_SQL="SELECT s.datname || '|' || s.xact_commit || '.' || s.xact_rollback || '.' || \
s.tup_inserted || '.' || s.tup_updated || '.' || s.tup_deleted || '.' || pg_database_size(s.datname) \
FROM pg_stat_database s JOIN pg_database d ON d.datname = s.datname \
WHERE d.datistemplate = false AND s.datname <> current_database() ORDER BY s.datname"

dumped=0; skipped=0; errors=0; failed=""

# not mapfile: the system /bin/bash is 3.2, mapfile only arrived in 4
rows=()
while IFS= read -r line; do rows+=("$line"); done < <(run_pg "$FP_SQL")

for row in ${rows[@]+"${rows[@]}"}; do
  db="${row%%|*}"; fp="${row#*|}"
  state_file="$STATE_DIR/$db.fp"
  stored=""
  [[ -f "$state_file" ]] && stored=$(<"$state_file")

  if [[ "$fp" == "$stored" ]]; then
    skipped=$((skipped+1))
    log INFO "$db: без изменений — пропуск"
    continue
  fi

  log INFO "$db: изменения есть — дамп"
  out_rel="$PG_SUBDIR/$(date +%F)/$db.dump"
  if docker exec -e DB="$db" -e OUT="/backups/$out_rel" "$CTR" \
      sh -c 'PGPASSWORD="${POSTGRES_PASSWORD:-$PGPASSWORD}" pg_dump -U "${POSTGRES_USER:-postgres}" -Fc -d "$DB" -f "$OUT"'
  then
    size=$(du -h "$BACKUP_ROOT/$out_rel" 2>/dev/null | cut -f1)
    log INFO "$db: готово ($size)"
    dumped=$((dumped+1))
  else
    log ERROR "$db: pg_dump упал"
    errors=$((errors+1)); failed="$failed $db"
  fi
done

# Roles/globals — every run (tiny file, always fresh).
# The path is built on the host: the container clock is UTC, not local
globals_rel="$PG_SUBDIR/$(date +%F)/globals.sql"
if docker exec -e OUT="/backups/$globals_rel" "$CTR" \
    sh -c 'PGPASSWORD="${POSTGRES_PASSWORD:-$PGPASSWORD}" pg_dumpall -U "${POSTGRES_USER:-postgres}" --globals-only -f "$OUT"'
then log INFO "globals.sql: готово"; else log ERROR "pg_dumpall упал"; errors=$((errors+1)); fi

# Re-read the fingerprints AFTER the dumps and store them as the new baseline
rows_post=()
while IFS= read -r line; do rows_post+=("$line"); done < <(run_pg "$FP_SQL")
for row in ${rows_post[@]+"${rows_post[@]}"}; do
  db="${row%%|*}"; fp="${row#*|}"
  # failed databases are not pinned — tomorrow they get dumped again
  [[ " $failed " == *" $db "* ]] && continue
  printf '%s' "$fp" > "$STATE_DIR/$db.fp"
done

log INFO "итог: дампов $dumped, без изменений $skipped, ошибок $errors"
exit "$errors"

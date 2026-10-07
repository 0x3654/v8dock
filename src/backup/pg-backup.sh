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
# Retention (GFS): days to keep daily, plus the last weekly/monthly
# snapshots. All from the repo .env, overridable per deployment; 0 disables
# the tier (0/0/0 = keep everything, manual cleanup).
# Per-contour: PG_PROFILE selects which databases to dump (TEST_DATABASES /
# DEV_DATABASES in .env) and which retention tier applies (BACKUP_KEEP_* for
# test, DEV_BACKUP_KEEP_* for dev). Same script, two realities.
env_int() { v="$(grep -E "^$1=" "$REPO_ROOT/.env" 2>/dev/null | tail -1 | cut -d= -f2-)"; echo "${v:-$2}"; }
env_str() { v="$(grep -E "^$1=" "$REPO_ROOT/.env" 2>/dev/null | tail -1 | cut -d= -f2-)"; echo "$v"; }
PG_PROFILE=$(env_str PG_PROFILE test)
case "$PG_PROFILE" in
  dev)
    PREFIX="DEV"; DBS_ALLOW="$(env_str DEV_DATABASES "")" ;;
  *)
    PREFIX="";    DBS_ALLOW="$(env_str TEST_DATABASES "")" ;;
esac
KEEP_DAILY=$(env_int ${PREFIX}BACKUP_KEEP_DAILY 3)
KEEP_WEEKLY=$(env_int ${PREFIX}BACKUP_KEEP_WEEKLY 2)
KEEP_MONTHLY=$(env_int ${PREFIX}BACKUP_KEEP_MONTHLY 1)

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

# Same, but inside a specific database (per-db fingerprint query)
run_pg_db() {
  docker exec -e DB="$1" "$CTR" sh -c 'PGPASSWORD="${POSTGRES_PASSWORD:-$PGPASSWORD}" psql -U "${POSTGRES_USER:-postgres}" -Atq -d "$DB" -c "'"$2"'"'
}

# Fingerprint: per-db sum of written rows (n_tup_ins+n_tup_upd+n_tup_del
# over pg_stat_user_tables), queried in EACH database — pg_stat_user_tables
# is only visible from inside its own database.
# Semantics: a boolean "rows were written / were not", no volume threshold.
# - reads don't move it (unlike xact_commit: opening a db in 1C = skip)
# - 1C background jobs (регламентные задания) do write rows -> honest dump
# - size bloating from autovacuum/vacuum doesn't move it
# - container restart resets counters to 0 < stored -> one extra dump per
#   restart (safe direction: false "changed", never false "unchanged")
# "postgres" is excluded: this script itself queries it (roles go into
# globals.sql anyway)
DBS_SQL="SELECT s.datname FROM pg_stat_database s JOIN pg_database d ON d.datname = s.datname \
WHERE d.datistemplate = false AND s.datname <> current_database() ORDER BY s.datname"
FP_SQL_DB="SELECT coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) FROM pg_stat_user_tables"

dumped=0; skipped=0; errors=0; failed=""

# not mapfile: the system /bin/bash is 3.2, mapfile only arrived in 4
dbs=()
while IFS= read -r line; do dbs+=("$line"); done < <(run_pg "$DBS_SQL")

for db in ${dbs[@]+"${dbs[@]}"}; do
  # contour filter: only databases declared for this profile
  if [[ -n "$DBS_ALLOW" && " $DBS_ALLOW " != *" $db "* ]]; then
    continue
  fi
  fp=$(run_pg_db "$db" "$FP_SQL_DB")
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
    # verify immediately: a corrupt archive must NEVER count as a good
    # backup, and (when retention is ever enabled) old days may only be
    # pruned after the current one verified — never delete-good-for-bad
    if docker exec -e OUT="/backups/$out_rel" "$CTR" \
        sh -c 'PGPASSWORD="${POSTGRES_PASSWORD:-$PGPASSWORD}" pg_restore -U "${POSTGRES_USER:-postgres}" --list "$OUT" >/dev/null 2>&1'
    then
      size=$(du -h "$BACKUP_ROOT/$out_rel" 2>/dev/null | cut -f1)
      log INFO "$db: готово + проверен ($size)"
      dumped=$((dumped+1))
    else
      log ERROR "$db: дамп создан, но pg_restore --list не прошёл — архив битый"
      errors=$((errors+1)); failed="$failed $db"
      rm -f "$BACKUP_ROOT/$out_rel"
    fi
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
# (pg_dump itself writes nothing to user tables, but keep the read-after
# convention in case this ever changes)
for db in ${dbs[@]+"${dbs[@]}"}; do
  # contour filter (same as the dump loop)
  if [[ -n "$DBS_ALLOW" && " $DBS_ALLOW " != *" $db "* ]]; then
    continue
  fi
  # failed databases are not pinned — tomorrow they get dumped again
  [[ " $failed " == *" $db "* ]] && continue
  printf '%s' "$(run_pg_db "$db" "$FP_SQL_DB")" > "$STATE_DIR/$db.fp"
done

log INFO "итог: дампов $dumped, без изменений $skipped, ошибок $errors"

# ── retention (GFS): prune old day-directories ──────────────────────────────
# Runs ONLY when the whole day verified (errors == 0): never delete good
# backups to make room for unverified ones.
# A day survives if it is one of:
#   - the newest KEEP_DAILY days
#   - the newest day of a ISO-week among the last KEEP_WEEKLY weeks
#   - the newest day of a month among the last KEEP_MONTHLY months
prune_days() {
  keep_daily=$1; keep_weekly=$2; keep_monthly=$3
  {
    # daily tier
    ls "$BACKUP_ROOT/$PG_SUBDIR" 2>/dev/null | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort -r | head -n "$keep_daily"
    # weekly tier: last day per ISO week for the newest keep_weekly weeks
    ls "$BACKUP_ROOT/$PG_SUBDIR" 2>/dev/null | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort -r       | awk -v k="$keep_weekly" '{ cmd="date -j -f %Y-%m-%d " $1 " +%G-%V"; cmd | getline iso; close(cmd);
          if (iso != last[k]) { for (i = k; i > 1; i--) last[i] = last[i-1]; last[1] = iso; print } }'       | head -n "$keep_weekly"
    # monthly tier
    ls "$BACKUP_ROOT/$PG_SUBDIR" 2>/dev/null | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort -r       | awk '{ m = substr($1, 1, 7); if (m != last) { last = m; print } }' | head -n "$keep_monthly"
  } | sort -u > /tmp/pg1c-keep.$$
  removed=0
  for d in $(ls "$BACKUP_ROOT/$PG_SUBDIR" 2>/dev/null | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort); do
    grep -qx "$d" /tmp/pg1c-keep.$$ || { rm -rf "$BACKUP_ROOT/$PG_SUBDIR/$d"; log INFO "retention: удалён $d"; removed=$((removed+1)); }
  done
  rm -f /tmp/pg1c-keep.$$
  [[ $removed -gt 0 ]] && log INFO "retention: удалено дней $removed (GFS $keep_daily/$keep_weekly/$keep_monthly)"
}

if [[ "$errors" -eq 0 ]]; then
  # guard: если все tier-ы отключены (0/0/0) — не чистим вообще
  if [[ $((KEEP_DAILY + KEEP_WEEKLY + KEEP_MONTHLY)) -gt 0 ]]; then
    prune_days "$KEEP_DAILY" "$KEEP_WEEKLY" "$KEEP_MONTHLY"
  fi
else
  log WARN "retention: пропуск — день с ошибками, старое не трогаем"
fi

exit "$errors"

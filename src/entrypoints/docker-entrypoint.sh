#!/bin/bash
# PostgreSQL 18.4-1.1C entrypoint for 1C:Enterprise.
# On first run (empty PGDATA) it creates the cluster with ru_RU.UTF-8 / UTF8,
# plugs in the 1C tuning (/conf/postgresql-1c.conf) and opens up network access.
set -euo pipefail

: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD должна быть задана (см. .env)}"
: "${PGDATA:=/var/lib/postgresql/18/main}"

if [ "$#" -eq 0 ]; then
    set -- postgres
fi

file_env() { # read POSTGRES_PASSWORD from a file if POSTGRES_PASSWORD_FILE is set
    local var="$1"; local fileVar="${var}_FILE"
    if [ -n "${!fileVar:-}" ]; then
        if [ -n "${!var:-}" ] && [ "${!var}" != "${!fileVar}" ]; then
            echo "Ошибка: заданы и $var, и $fileVar" >&2; exit 1
        fi
        export "$var=$(cat "${!fileVar}")"
    fi
}
file_env POSTGRES_PASSWORD

if [ "$1" = 'postgres' ] && [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo ">>> Инициализация нового кластера ($PGDATA), локаль ru_RU.UTF-8, кодировка UTF8"
    echo "$POSTGRES_PASSWORD" > /tmp/.pgpw
    initdb -D "$PGDATA" \
        --username=postgres --pwfile=/tmp/.pgpw \
        --encoding=UTF8 --locale=ru_RU.UTF-8 \
        --auth-local=scram-sha-256 --auth-host=scram-sha-256
    rm -f /tmp/.pgpw

    # 1C tuning (mounted read-only at /conf)
    echo "include_if_exists = '/conf/postgresql-1c.conf'" >> "$PGDATA/postgresql.conf"

    # network access: 1C server (Windows VM 10.211.55.x, containers, LAN)
    {
        echo
        echo "# сетевой доступ (доверенная локальная сеть)"
        echo "host all all 0.0.0.0/0 scram-sha-256"
        echo "host all all ::/0 scram-sha-256"
    } >> "$PGDATA/pg_hba.conf"
fi

exec "$@"

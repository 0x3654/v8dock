#!/bin/bash
# Entrypoint PostgreSQL 9.1.9-1.1C (the 8.2 era) for the 8.2 cluster (rev82).
# On first run (empty PGDATA) it creates the cluster with ru_RU.UTF-8 / UTF8,
# plugs in the era config (/conf/postgresql-9.1-1c.conf) and network access.
# 9.1 does not know scram — md5 authentication (that is how the 8.2 era worked).
set -euo pipefail

: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD должна быть задана (см. .env)}"
: "${PGDATA:=/var/lib/postgresql/9.1/main}"

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
    # 9.1 only knows the common --auth (no local/host split as in newer versions)
    initdb -D "$PGDATA" \
        --username=postgres --pwfile=/tmp/.pgpw \
        --encoding=UTF8 --locale=ru_RU.UTF-8 \
        --auth=md5
    rm -f /tmp/.pgpw

    # local socket -> trust (healthcheck/psql without a password from inside);
    # the network stays md5 (the 8.2 cluster connects with a password)
    sed -i -E 's/^(local[[:space:]]+all[[:space:]]+all[[:space:]]+)md5[[:space:]]*$/\1trust/' \
        "$PGDATA/pg_hba.conf"

    # 8.2-era tuning (baked into the image; 9.1 does not know include_if_exists)
    echo "include = '/conf/postgresql-9.1-1c.conf'" >> "$PGDATA/postgresql.conf"

    # network access: 8.2 cluster (Windows 10.211.55.2 -> host:5433, containers)
    {
        echo
        echo "# сетевой доступ (пароль md5)"
        echo "host all all 0.0.0.0/0 md5"
    } >> "$PGDATA/pg_hba.conf"
fi

exec "$@"

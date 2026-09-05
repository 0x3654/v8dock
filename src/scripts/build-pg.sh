#!/bin/sh
# Build a pg1c image of a SPECIFIC 1C build version (archive in dists/):
#   ./src/scripts/build-pg.sh 18.4-1.1C          # current
#   ./src/scripts/build-pg.sh 17.10-1.1C
# The archive name is derived from the version: 18.4-1.1C ->
#   postgresql_18.4_1_debian_*_aarch64_package.tar.bz2 (the debian minor in the
#   name drifts between releases — matched by mask). The major is derived automatically.
set -e
cd "$(dirname "$0")/../.."

VER="${1:?укажи версию, например: ./src/scripts/build-pg.sh 18.4-1.1C}"
MAJOR="${VER%%.*}"                                    # 18.4-1.1C -> 18
BASE="$(printf '%s' "${VER%.1C}" | tr -- '-' '_')"    # -> 18.4_1

set -- dists/postgresql_${BASE}_debian_*_aarch64_package.tar.bz2
if [ ! -f "$1" ]; then
    echo "НЕТ dists/postgresql_${BASE}_debian_*_aarch64_package.tar.bz2 — скачай с releases.1c.ru и положи в dists/ (README «Что скачать»)" >&2
    exit 1
fi
echo "архив: $1"

# the build-arg takes the bare file name: the Dockerfile looks it up in /dists (bind-mount)
docker build -f src/Dockerfile \
    --build-arg PG_PACKAGE="${1#dists/}" --build-arg PG_MAJOR="$MAJOR" \
    -t "pg1c:$VER" .

echo "OK: pg1c:$VER"
echo "Запуск:  PG_VERSION=$VER docker compose up -d pg1c"
if [ "$MAJOR" != 18 ]; then
    echo "ВНИМАНИЕ: мажор $MAJOR != 18 — том pg1c-data поднимет ПУСТОЙ кластер"
    echo "(PGDATA=/var/lib/postgresql/$MAJOR/main, старые данные в другом мажоре);"
    echo "для нового мажора объяви отдельный том в volumes compose."
fi

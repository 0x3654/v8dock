#!/bin/sh
# Build a 1C server image of a SPECIFIC version (deb packages must be in dists/):
#   ./src/scripts/build-server.sh 8.3.27.2340            # arm64 (primary)
#   ./src/scripts/build-server.sh 8.5.1.1343 arm64
# Package names are derived from the version: 8.3.27.2340 ->
#   1c-enterprise-8.3.27.2340-common_8.3.27-2340_arm64.deb (+ -server_...)
# Download the archives from releases.1c.ru and unpack them into dists/ (see README).
set -e
cd "$(dirname "$0")/../.."

VER="${1:?укажи версию, например: ./src/scripts/build-server.sh 8.3.27.2340}"
ARCH="${2:-arm64}"
REV="${VER%.*}-${VER##*.}"   # 8.3.27.2340 -> 8.3.27-2340

COMMON="1c-enterprise-${VER}-common_${REV}_${ARCH}.deb"
DEB="1c-enterprise-${VER}-server_${REV}_${ARCH}.deb"
for f in "$COMMON" "$DEB"; do
    if [ ! -f "dists/$f" ]; then
        echo "НЕТ dists/$f — скачай архив с releases.1c.ru и распакуй в dists/ (README «Что скачать»)" >&2
        exit 1
    fi
done

docker image inspect 1c-base:11 >/dev/null 2>&1 || ./src/scripts/build.sh

docker build -f src/Dockerfile.server \
    --build-arg SERVER_VERSION="$VER" --build-arg SERVER_ARCH="$ARCH" \
    --build-arg SERVER_COMMON="$COMMON" --build-arg SERVER_DEB="$DEB" \
    -t "server1c:$VER" .

echo "OK: server1c:$VER"
echo "Запуск:   SERVER_VERSION=$VER docker compose --profile with-server up -d"
echo "          (для новой версии добавь том srv1c-$VER-data: в volumes compose)"

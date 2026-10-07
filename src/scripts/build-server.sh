#!/bin/sh
# Build a 1C server image of a SPECIFIC version:
#   ./src/scripts/build-server.sh 8.3.27.2340            # arm64 (primary)
#   ./src/scripts/build-server.sh 8.5.1.1343 arm64
# Package names are derived from the version: 8.3.27.2340 ->
#   1c-enterprise-8.3.27.2340-common_8.3.27-2340_arm64.deb (+ -server_...)
# Missing debs are downloaded automatically from releases.1c.ru by
# src/scripts/fetch-release.py (RELEASES_LOGIN/PASSWORD in .env; the archive
# is unpacked into dists/ and SHA-512 verified — see its header for the
# releases.1c.ru URL scheme).
set -e
cd "$(dirname "$0")/../.."

VER="${1:?укажи версию, например: ./src/scripts/build-server.sh 8.3.27.2340}"
ARCH="${2:-arm64}"
REV="${VER%.*}-${VER##*.}"   # 8.3.27.2340 -> 8.3.27-2340

COMMON="1c-enterprise-${VER}-common_${REV}_${ARCH}.deb"
DEB="1c-enterprise-${VER}-server_${REV}_${ARCH}.deb"
if [ ! -f "dists/$COMMON" ] || [ ! -f "dists/$DEB" ]; then
    case "$VER" in
        8.3.*) NICK=Platform83 ;;
        8.5.*) NICK=Platform85 ;;
        *) echo "Не знаю releases-проект для $VER — скачай вручную (README «Что скачать»)" >&2; exit 1 ;;
    esac
    case "$ARCH" in
        arm64) PAT='server.arm.deb64_*' ;;
        amd64) PAT='server64_*' ;;
        *) echo "Не знаю архив для arch=$ARCH — скачай вручную" >&2; exit 1 ;;
    esac
    echo "dists/ не хватает $COMMON / $DEB — качаю ($NICK, $PAT)…" >&2
    python3 src/scripts/fetch-release.py "$VER" --nick "$NICK" --files "$PAT"
    for f in "$COMMON" "$DEB"; do
        [ -f "dists/$f" ] || { echo "после загрузки всё нет dists/$f — см. вывод fetch-release.py выше" >&2; exit 1; }
    done
fi

docker image inspect 1c-base:11 >/dev/null 2>&1 || ./src/scripts/build.sh

docker build -f src/Dockerfile.server \
    --build-arg SERVER_VERSION="$VER" --build-arg SERVER_ARCH="$ARCH" \
    --build-arg SERVER_COMMON="$COMMON" --build-arg SERVER_DEB="$DEB" \
    -t "server1c:$VER" .

echo "OK: server1c:$VER"
echo "Запуск:   SERVER_VERSION=$VER docker compose --profile with-server up -d"
echo "          (для новой версии добавь том srv1c-$VER-data: в volumes compose)"

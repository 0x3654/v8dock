#!/bin/sh
# bootstrap.sh — one-command bring-up from a fresh clone:
#   1. .env    — create from .env.example (generates a random POSTGRES_PASSWORD)
#   2. dists/  — verify the 1C distributions downloaded from releases.1c.ru
#   3. build   — version images via compose (the bases auto-pull from Docker Hub)
#   4. up      — pg1c first (wait for healthy), then the 1C server cluster
#   5. print the remaining manual steps (hosts entries, license activation)
#
# Usage:
#   ./bootstrap.sh               # pg1c + 8.3 server + license stand (the default set)
#   ./bootstrap.sh --no-server   # DB only (no 1C server, no license stand)
#   ./bootstrap.sh --with-85     # also the second cluster (platform 8.5)
#
# Versions follow the docker-compose defaults; override via env (see README):
#   PG_VERSION=18.4-1.1C SERVER_VERSION=8.3.27.2325 ./bootstrap.sh
set -e
cd "$(dirname "$0")"

PG_VERSION="${PG_VERSION:-18.4-1.1C}"
SERVER_VERSION="${SERVER_VERSION:-8.3.27.2325}"
SERVER85_VERSION="${SERVER85_VERSION:-8.5.1.1522}"

WITH_SERVER=1
WITH_85=0
for arg in "$@"; do
    case "$arg" in
        --no-server) WITH_SERVER=0 ;;
        --with-85)   WITH_85=1 ;;
        *) echo "unknown flag: $arg (supported: --no-server --with-85)" >&2; exit 2 ;;
    esac
done

# --- 0. prerequisites ---------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    echo "docker not found — install Docker Desktop (Rosetta enabled) first" >&2
    exit 1
fi
docker compose version >/dev/null 2>&1 || { echo "'docker compose' (v2 plugin) not available" >&2; exit 1; }

# --- 1. .env -----------------------------------------------------------------
if [ ! -f .env ]; then
    cp .env.example .env
    # replace the placeholder password with a random one, keep the file otherwise intact
    if command -v openssl >/dev/null 2>&1; then
        PWD_GEN="$(openssl rand -hex 16)"
        sed -i.bak "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${PWD_GEN}|" .env && rm -f .env.bak
        echo "== .env created; POSTGRES_PASSWORD generated: ${PWD_GEN}"
    else
        echo "== .env created from the example — EDIT POSTGRES_PASSWORD before continuing!" >&2
    fi
    echo "   (optional) DEV_LICENSE_LOGIN/PASSWORD — developer.1c.ru account, needed only"
    echo "   for the FIRST license activation: ./src/scripts/license-renew.sh first"
elif grep -q '^POSTGRES_PASSWORD=меняй' .env 2>/dev/null; then
    echo "== POSTGRES_PASSWORD in .env is still the example placeholder — edit it!" >&2
    exit 1
fi

# --- 2. dists/ preflight ------------------------------------------------------
# Each component names the exact files it needs; anything missing is reported
# together with the releases.1c.ru page to download it from. Unpack the
# archives so the .deb/.tar.bz2 files land directly in dists/.
MISSING=0
miss() {   # miss "<file or mask>" "<releases.1c.ru page>"
    echo "  MISSING: $1"
    echo "           download: $2"
    MISSING=$((MISSING + 1))
}
have() { [ -f "dists/$1" ]; }

# pg1c: the 1C-patched PostgreSQL build (vanilla PostgreSQL is NOT supported
# by the platform). The debian minor in the archive name drifts between
# releases — matched by mask.
PG_BASE="$(printf '%s' "${PG_VERSION%.1C}" | tr -- '-' '_')"   # 18.4-1.1C -> 18.4_1
set -- dists/postgresql_${PG_BASE}_debian_*_aarch64_package.tar.bz2
[ -f "$1" ] || miss "postgresql_${PG_BASE}_debian_<deb>._aarch64_package.tar.bz2" \
    "https://releases.1c.ru/project/AddCompPostgre  (version ${PG_VERSION}, Debian aarch64)"

if [ "$WITH_SERVER" = 1 ]; then
    # server1c (8.3): deb names use two version formats — 8.3.27.2325 -> 8.3.27-2325
    REV="${SERVER_VERSION%.*}-${SERVER_VERSION##*.}"
    have "1c-enterprise-${SERVER_VERSION}-common_${REV}_arm64.deb" ||
        miss "1c-enterprise-${SERVER_VERSION}-common_${REV}_arm64.deb" \
            "https://releases.1c.ru/project/Platform83  (server zip, release ${SERVER_VERSION}, section 'Linux arm64')"
    have "1c-enterprise-${SERVER_VERSION}-server_${REV}_arm64.deb" ||
        miss "1c-enterprise-${SERVER_VERSION}-server_${REV}_arm64.deb" \
            "https://releases.1c.ru/project/Platform83  (same zip)"

    # license stand (lic1c): the thick client of the same version, amd64 build —
    # the x86 fingerprint under Rosetta is consistent with the server license
    have "1c-enterprise-${SERVER_VERSION}-client_${REV}_amd64.deb" ||
        miss "1c-enterprise-${SERVER_VERSION}-client_${REV}_amd64.deb" \
            "https://releases.1c.ru/project/Platform83  (client zip, x64 deb)"
    have "1c-enterprise-${SERVER_VERSION}-common_${REV}_amd64.deb" ||
        miss "1c-enterprise-${SERVER_VERSION}-common_${REV}_amd64.deb" \
            "https://releases.1c.ru/project/Platform83  (server zip, x64 — common lives there)"
    have "1c-enterprise-${SERVER_VERSION}-server_${REV}_amd64.deb" ||
        miss "1c-enterprise-${SERVER_VERSION}-server_${REV}_amd64.deb" \
            "https://releases.1c.ru/project/Platform83  (server zip, x64 — the stand needs server libs, see README gotchas)"
fi

if [ "$WITH_85" = 1 ]; then
    REV85="${SERVER85_VERSION%.*}-${SERVER85_VERSION##*.}"
    have "1c-enterprise-${SERVER85_VERSION}-common_${REV85}_arm64.deb" ||
        miss "1c-enterprise-${SERVER85_VERSION}-common_${REV85}_arm64.deb" \
            "https://releases.1c.ru/project/Platform85  (server zip, release ${SERVER85_VERSION}, arm64)"
    have "1c-enterprise-${SERVER85_VERSION}-server_${REV85}_arm64.deb" ||
        miss "1c-enterprise-${SERVER85_VERSION}-server_${REV85}_arm64.deb" \
            "https://releases.1c.ru/project/Platform85  (same zip)"
fi

if [ "$MISSING" -gt 0 ]; then
    echo
    echo "== dists/ is incomplete: $MISSING file(s) missing."
    echo "   Download from releases.1c.ru (a developer.1c.ru account is required),"
    echo "   unpack the archives into dists/, then re-run ./bootstrap.sh"
    exit 1
fi
echo "== dists/ OK"

# --- 3. build -----------------------------------------------------------------
if [ "$WITH_SERVER" = 1 ]; then
    ./src/scripts/build.sh
else
    docker build -f src/Dockerfile \
        --build-arg PG_PACKAGE="$(cd dists && ls postgresql_${PG_BASE}_debian_*_aarch64_package.tar.bz2)" \
        --build-arg PG_MAJOR="${PG_VERSION%%.*}" -t "pg1c:${PG_VERSION}" .
fi

# --- 4. up --------------------------------------------------------------------
docker compose up -d pg1c
echo "== waiting for pg1c to become healthy..."
WAITED=0
until [ "$(docker inspect -f '{{.State.Health.Status}}' pg1c 2>/dev/null)" = "healthy" ]; do
    sleep 5
    WAITED=$((WAITED + 5))
    if [ "$WAITED" -ge 300 ]; then
        echo "pg1c did not become healthy in 5 min — check: docker logs pg1c" >&2
        exit 1
    fi
done
[ "$WITH_SERVER" = 1 ] && docker compose --profile with-server up -d

# --- 5. what's next -----------------------------------------------------------
cat <<'EOF'

== Stand is up. Remaining manual steps (details in README):
   1. hosts entries so clients resolve the cluster name:
        mac:     192.0.2.10 server1c   (then install the pf daemon, see README "Mac networking")
        Windows: 10.211.55.2 server1c
   2. First license activation (free community license, developer.1c.ru account):
        put DEV_LICENSE_LOGIN/PASSWORD into .env, then
        ./src/scripts/license-renew.sh first
   3. Install the 1C client on your working machine (links in README "Clients"),
      then create an infobase: Srvr="server1c", DB server pg1c.
EOF
docker compose ps

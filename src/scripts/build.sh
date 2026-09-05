#!/bin/sh
# Full stand build: the version images via compose build.
#   ./src/scripts/build.sh            # version images (bases auto-pull from Docker Hub)
#   ./src/scripts/build.sh --bases    # also build the bases locally — an OVERRIDE:
#                                     # the local build shadows the registry tag
#                                     # (docker prefers a local image in FROM)
# The bases live on docker.io/0x3654 (1c-base, lic1c-base — multi-arch),
# published by .github/workflows/publish-base-images.yml. Version images
# embed 1C distributions and are always built locally from dists/.
set -e
cd "$(dirname "$0")/../.."

if [ "$1" = "--bases" ]; then
    echo "=== локальные основы (оверрайд docker.io/0x3654, нативная arch)"
    docker build --target base     -t docker.io/0x3654/1c-base:latest    -f src/Dockerfile.base .
    docker build --target lic-base -t docker.io/0x3654/lic1c-base:latest -f src/Dockerfile.base .
    # the amd64 license stand needs the amd64 variant under the SAME tag
    # (lic1c-base is a multi-arch manifest in the registry; a local classic
    # build shadows it per platform — build the amd64 one when developing
    # the license stand):
    #   docker build --platform linux/amd64 --target lic-base \
    #     -t docker.io/0x3654/lic1c-base:latest -f src/Dockerfile.base .
fi

echo "=== версии платформы (pg1c, server1c, lic1c; основы подтянутся из реестра)"
docker compose --profile with-server --profile license build

docker image ls --format "{{.Repository}}:{{.Tag}}  {{.Size}}" \
    | grep -E "1c-base|lic1c|server1c|pg1c"

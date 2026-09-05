#!/bin/sh
# Entrypoint of the 1C:Enterprise server container.
# ragent (PID 1) brings up rmngr and rphost on its own; ras is needed for
# administration via rac — ragent does not start it, so we start it separately,
# pointing it at the cluster agent address. For the "second cluster" on its own
# port range (8.5: ragent 2540) the agent is set via the AGENT_PORT env; ras
# listens on RAS_PORT (1545).
#
# /cpuinfo (if mounted): overrides /proc/cpuinfo with the Rosetta fingerprint
# (VirtualApple x86) — the server license is bound to the x86 CPU; a native
# arm container sees empty x86 fields and rejects the license. Requires
# privileged (mount --bind over procfs).
set -e

AGENT_PORT="${AGENT_PORT:-1540}"
RAS_PORT="${RAS_PORT:-1545}"

mkdir -p /home/usr1cv8/.1cv8
chown -R 999:1000 /home/usr1cv8/.1cv8 2>/dev/null || true

if [ -f /cpuinfo ] && [ "$(id -u)" = "0" ]; then
    mount --bind /cpuinfo /proc/cpuinfo || echo "WARN: не вышло подменить /proc/cpuinfo"
fi

if ! rac "localhost:${RAS_PORT}" cluster list >/dev/null 2>&1; then
    ras cluster --daemon "localhost:${AGENT_PORT}" || echo "WARN: ras не запустился"
fi

# the server runs as usr1cv8 (the volume owner): if the container was started
# as root (needed for mount --bind) — drop privileges before ragent
if [ "$(id -u)" = "0" ]; then
    exec setpriv --reuid=999 --regid=1000 --clear-groups env HOME=/home/usr1cv8 ragent "$@"
fi
exec ragent "$@"

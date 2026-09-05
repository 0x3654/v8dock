#!/bin/sh
# 1C cluster administration from the mac: rac inside the container (ras is
# already brought up by the entrypoint). rac commands pass straight through;
# the cluster uuid (--cluster=) is injected automatically for the command
# groups that need it — no need to copy it from `cluster list` by hand. A
# replacement for the Windows MMC console for routine operations.
#   ./src/scripts/rac.sh cluster list
#   ./src/scripts/rac.sh session list                # sessions (uuid injected)
#   ./src/scripts/rac.sh session terminate --session=<uuid>
#   ./src/scripts/rac.sh infobase summary list       # cluster infobases
#   ./src/scripts/rac.sh lock infobase set --infobase=<uuid> ... # locks
# Cluster 8.5 (its ras is on 1545 internally, same as in 8.3):
#   RAC_CONTAINER=server1c-8.5.1.1522 ./src/scripts/rac.sh session list
set -e

CT="${RAC_CONTAINER:-server1c-8.3.27.2325}"
RAS="${RAS_ADDR:-localhost:1545}"

# rac groups that need the cluster uuid (verified via «Ошибка разбора
# параметра: cluster»); agent/cluster/help — without it
CLUSTER_SCOPED="manager server process service infobase connection session
lock rule profile counter limit service-setting binary-data-storage"

cmd="${1:-cluster}"
[ $# -gt 0 ] && shift

needs_cluster=0
for g in $CLUSTER_SCOPED; do [ "$g" = "$cmd" ] && needs_cluster=1; done

if [ "$needs_cluster" = 1 ]; then
    case " $* " in
        *"--cluster="*) ;;   # already passed manually
        *) set -- "$@" "--cluster=$(docker exec "$CT" rac "$RAS" cluster list \
               | awk '/^cluster/{print $3}')" ;;
    esac
fi

exec docker exec "$CT" rac "$RAS" "$cmd" "$@"

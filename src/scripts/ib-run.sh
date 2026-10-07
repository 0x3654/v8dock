#!/bin/sh
# Open a server infobase in the LOCAL mac 1C client, right base and
# credentials in the connection string — no base-list clicking. The client
# window appears on the desktop (that's the point); startup errors show as
# dialogs the user sees live.
#
#   ./src/scripts/ib-run.sh <base> [options]
#     -m thin|thick|designer   client flavor (default: THICK — most bases on
#                              this stand are 8.2-origin configs with ordinary
#                              forms; the thin client cannot run those)
#     -c <cluster-container>   default: auto — the cluster actually hosting
#                              the base (asked via rac); the client version is
#                              taken from its name (server1c-8.3.27.2325
#                              -> /opt/1cv8/8.3.27.2325)
#     -n <user> -p <pwd>       infobase credentials (/N /P); without them a
#                              base with users shows its auth dialog
#     -s <seconds>             after the launch sleep N and take a screenshot
#                              of the screen (error dialogs land frontmost)
#                              -> data/runs/<base>_<HHMMSS>.png
#
#   ./src/scripts/ib-run.sh ut_dev_copy
#   ./src/scripts/ib-run.sh erp_demo -m thin
#   ./src/scripts/ib-run.sh ut_dev_copy -m designer
#   ./src/scripts/ib-run.sh acct_dev -n Администратор -p secret
#
# Gotcha: released mac clients reject the 8.5 cluster (see README); 8.5-cluster
# bases cannot be opened this way yet. The mac thick/thin client is x86_64
# (Rosetta) — works on this machine, segfaults on A18 Pro macs.
set -e

BASE=""; CT=""; FLAVOR=thick; IBUSER=""; IBPWD=""; SHOT=0
while getopts m:c:n:p:s: opt; do
    case $opt in
        m) FLAVOR="$OPTARG" ;;
        c) CT="$OPTARG" ;;
        n) IBUSER="$OPTARG" ;;
        p) IBPWD="$OPTARG" ;;
        s) SHOT="$OPTARG" ;;
        *) echo "usage: $0 <base> [-m thin|thick|designer] [-c ct] [-n user] [-p pwd] [-s sec]" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
BASE="$1"
[ -n "$BASE" ] || { echo "base name required" >&2; exit 1; }

# cluster auto-pick: the one actually hosting the base (each container is
# asked via rac; a plain "first container" pick opens 8.3 bases with the 8.5
# client and vice versa — a guaranteed connection error)
if [ -z "$CT" ]; then
    for c in $(docker ps --format '{{.Names}}' | grep '^server1c-'); do
        if RAC_CONTAINER="$c" ./src/scripts/rac.sh infobase summary list 2>/dev/null \
            | grep -q "^name     : $BASE\$"; then
            CT="$c"; break
        fi
    done
fi
[ -n "$CT" ] || { echo "base not found in any running cluster (or no server1c-* container)" >&2; exit 1; }

VER=${CT#server1c-}
APPDIR="/opt/1cv8/$VER"
[ -d "$APPDIR" ] || { echo "client $APPDIR not installed on this mac" >&2; exit 1; }

case "$FLAVOR" in
    thin)     APP="$APPDIR/1cv8c.app"; MODE=ENTERPRISE ;;
    thick)    APP="$APPDIR/1cv8.app";  MODE=ENTERPRISE ;;
    designer) APP="$APPDIR/1cv8.app";  MODE=DESIGNER ;;
    *) echo "flavor must be thin|thick|designer" >&2; exit 1 ;;
esac

case "$VER" in
    8.5*) SRVR="server1c:2540"
          echo "NOTE: released mac clients reject the 8.5 cluster — expect a connection error" >&2 ;;
    *)    SRVR="server1c" ;;
esac

ARGS="$MODE /S $SRVR/$BASE"
[ -n "$IBUSER" ] && ARGS="$ARGS /N$IBUSER"
[ -n "$IBPWD" ] && ARGS="$ARGS /P$IBPWD"

open -n "$APP" --args $ARGS
echo "launched: $BASE on $CT ($VER, $FLAVOR)"

# optional screenshot: error dialogs appear frontmost; the shot lets the
# assistant read the error text from the picture. NB: screencapture needs the
# Screen Recording permission granted to the terminal app (System Settings ->
# Privacy & Security); without it the file comes out empty
if [ "$SHOT" -gt 0 ]; then
    sleep "$SHOT"
    mkdir -p data/runs
    OUT="data/runs/${BASE}_$(date +%H%M%S).png"
    screencapture -x "$OUT"
    echo "shot: $OUT"
fi

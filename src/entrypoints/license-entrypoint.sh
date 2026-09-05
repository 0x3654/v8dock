#!/bin/sh
# License stand: brings up only the screen (Xvfb + x11vnc, vnc://localhost:5900,
# password 1clicens) and lives on its own. 1C processes are started from outside
# on command:
#
#   renewal/activation:   ./license-renew.sh [first]   (ibsrv + client /Execute)
#   manual wizard (VNC):  docker exec -d lic1c setpriv --reuid=999 --regid=1000 \
#     --clear-groups env HOME=/home/usr1cv8 DISPLAY=:0 LANG=ru_RU.UTF-8 \
#     /opt/1cv8/arm64/8.3.27.2325/1cv8 DESIGNER /F /home/usr1cv8/license-ib
#
# The container runs while server1c83 is up (separate lic-net network).
set -e

Xvfb :0 -screen 0 1400x900x24 -nolisten tcp &
sleep 2
x11vnc -display :0 -forever -shared -passwd 1clicens -quiet -bg

exec sleep infinity

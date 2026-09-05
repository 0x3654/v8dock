#!/bin/sh
# Fully automatic renewal (and initial activation) of the 1C server community
# license — no GUI involvement and no cluster downtime.
#
#   ./license-renew.sh           — renewal (license already exists, no credentials needed)
#   ./license-renew.sh first     — initial activation with developer.1c.ru credentials
#                                  from .env (DEV_LICENSE_LOGIN/PASSWORD)
#
# Scheme: the thick client in the lic1c container (client-only image, no server
# part) opens the file infobase license-ib DIRECTLY (/F, without ibsrv — the
# thin client cannot do this, the thick one can) and runs an epf automaton that
# calls the standard ПолучениеЛицензий API. The hardware fingerprint = the
# container (MAC/volume shared with server1c) → the license is valid for the
# cluster. The result lands in license-result.txt.
set -e
cd "$(dirname "$0")/../.."

RUN="setpriv --reuid=999 --regid=1000 --clear-groups env HOME=/home/usr1cv8 DISPLAY=:0 LANG=ru_RU.UTF-8"

# 1. a fresh stand container and a copy of the data processor
docker compose --profile license rm -sf lic1c >/dev/null 2>&1 || true
docker compose --profile license up -d lic1c >/dev/null

# platform directory inside the stand: amd64 stand (Rosetta) — x86_64; if we
# switch back to an arm stand — arm64. Detected at runtime so the script does
# not depend on the variant.
V8DIR=/opt/1cv8/$(docker exec lic1c ls /opt/1cv8 | tail -1)/8.3.27.2325
V8=$V8DIR/1cv8
docker cp src/license-epf/license.epf lic1c:/home/usr1cv8/license.epf
docker exec -u root lic1c chown 999:1000 /home/usr1cv8/license.epf

# 2. the parameter file for the epf
if [ "$1" = "first" ]; then
    PARAMS="$(grep '^DEV_LICENSE_LOGIN=' .env | cut -d= -f2-)===$(grep '^DEV_LICENSE_PASSWORD=' .env | cut -d= -f2-)"
else
    # renewal: login/password are NOT passed (the center recognizes the license
    # by fingerprint/file on its own); empty credentials yield «Пинкод не входит
    # в комплект» — expected OUTSIDE the expiry window; renewal confirmed Sep 11-12
    PARAMS=""
fi
docker exec lic1c sh -c "printf '%s' '$PARAMS' > /home/usr1cv8/license-params.txt"
docker exec -u root lic1c chown 999:1000 /home/usr1cv8/license-params.txt

# 3. protection against dangerous actions (the value is a REGEX on the path,
#    recipe: habr 928572), nethasp.ini (without it fingerprint collection times
#    out searching for network HASPs — «Сбор информации о компьютере выполняется
#    длительное время») and cleanup of stale file-infobase locks from previous runs
docker exec lic1c sh -c 'mkdir -p /home/usr1cv8/.1cv8/1C/1cv8/conf && \
    printf "DisableUnsafeActionProtection=.*license.*\n" > /home/usr1cv8/.1cv8/1C/1cv8/conf/conf.cfg && \
    printf "[NH_COMMON]\nNH_TCPIP = Disabled\n" > /home/usr1cv8/.1cv8/1C/1cv8/conf/nethasp.ini && \
    chown -R 999:1000 /home/usr1cv8/.1cv8; \
    chmod 777 /var/1C/licenses; \
    rm -f /home/usr1cv8/license-ib/1Cv8.1CL'

# 4. session with the data processor: thick client directly on the file infobase
echo "--- запускаю обработку..."
docker exec lic1c sh -c "timeout 120 $RUN $V8 ENTERPRISE /F /home/usr1cv8/license-ib \
    /Execute /home/usr1cv8/license.epf /UseHwLicenses-" \
    || echo "(клиент завершился с кодом $?)"
docker exec lic1c sh -c 'for d in /proc/[0-9]*; do grep -q "^1cv8" "$d/comm" 2>/dev/null && kill "${d#/proc/}" 2>/dev/null; done' || true

echo "--- лицензии в volume:"
docker exec lic1c ls -la /var/1C/licenses/
echo "--- результат обработки:"
docker exec lic1c cat /home/usr1cv8/license-result.txt 2>/dev/null || echo "(лог не создан)"
docker compose --profile license rm -sf lic1c >/dev/null

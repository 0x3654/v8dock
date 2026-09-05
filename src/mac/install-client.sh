#!/bin/sh
# Install the 1C client infrastructure on the mac (idempotent, safe to re-run
# after macOS/platform updates):
#   1. /var/1C/licenses — the system license directory (linux layout of the
#      client; without it a "successfully obtained" license is silently not
#      saved — README, the "/var/1C" gotcha). Requires sudo.
#   2. launchd timer for client license auto-renewal (Mon/Thu 03:37, the
#      client runs hidden for 90 seconds — renewal is machine-based, done
#      at startup). The plist carries a __REPO_ROOT__ placeholder; it is
#      substituted with the actual repo path at install time.
# Run: sh src/mac/install-client.sh
set -e
cd "$(dirname "$0")/../../"   # repo root

echo "=== 1/2: /var/1C/licenses (системный каталог лицензий)"
if [ -d /var/1C/licenses ]; then
    echo "ок: существует ($(ls /var/1C/licenses 2>/dev/null | wc -l | tr -d ' ') лицензий)"
else
    echo "нет — создаю (sudo):"
    sudo mkdir -p /var/1C/licenses
    sudo chown -R "$(id -un):staff" /var/1C
    echo "создан"
fi

echo "=== 2/2: launchd-таймер автопродления (пн/чт 03:37)"
PLIST_SRC=src/mac/com.user.1c-license-renew.plist
PLIST_DST="$HOME/Library/LaunchAgents/com.user.1c-license-renew.plist"
chmod +x src/mac/1c-license-autorenew.sh
mkdir -p "$HOME/Library/LaunchAgents"
# unload the old one if it existed
launchctl bootout "gui/$(id -u)/com.user.1c-license-renew" 2>/dev/null || true
# substitute __REPO_ROOT__ with the actual checkout path (the repo plist
# is path-agnostic; the installed copy must point at this checkout)
sed "s|__REPO_ROOT__|$(pwd)|g" "$PLIST_SRC" > "$PLIST_DST"
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
echo "установлен и загружен"

echo ""
echo "Проверка (одноразовый прогон таймера, ~95 сек):"
echo "  launchctl kickstart gui/$(id -u)/com.user.1c-license-renew && tail -3 /tmp/1c-license-renew.log"

#!/bin/sh
# Automatic renewal of the 1C client license on the mac (launchd
# com.user.1c-license-renew, Mon/Thu 03:37). Stealthy: the client is started
# HIDDEN (open -g -j — the window does not appear even on an unlocked screen),
# renewal is performed by the licensing subsystem at startup (machine-based, no
# login), killed after 90 seconds.
# The license lives in /var/1C/licenses (the system one, linux layout of the client).
PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/bin:$PATH"
APP=/opt/1cv8/8.3.27.2325/1cv8.app
LOG=/tmp/1c-license-renew.log
IB="$HOME/Documents/InfoBase"

# the system license directory may not have survived a macOS reinstall — log it
[ -d /var/1C/licenses ] || { echo "$(date '+%F %T') НЕТ /var/1C/licenses — см. README (петля /var/1C)" >> "$LOG"; exit 1; }

before=$(ls /var/1C/licenses | sort | tail -1)
echo "$(date '+%F %T') старт скрытый (было: $before)" >> "$LOG"
# -g: do not bring the app to front; -j: launch hidden (no visible windows are created)
open -g -j -a "$APP" --args ENTERPRISE /F "$IB"
sleep 90
pkill -f "8.3.27.2325/1cv8.app" 2>/dev/null
sleep 3
after=$(ls /var/1C/licenses | sort | tail -1)
echo "$(date '+%F %T') финиш (стало: $after)" >> "$LOG"
[ "$before" != "$after" ] && echo "$(date '+%F %T') ОБНОВЛЕНИЕ: $before -> $after" >> "$LOG"
exit 0

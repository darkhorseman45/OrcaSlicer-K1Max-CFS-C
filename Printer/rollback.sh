#!/bin/sh
# Restore only files changed by the user-space installer.
set -eu
BASE=/usr/data/fluidd
BACKUP=${1:-}
[ -n "$BACKUP" ] || { echo 'Usage: sh rollback.sh /usr/data/k1max-cfs-c-backups/TIMESTAMP'; exit 2; }
case "$BACKUP" in /usr/data/k1max-cfs-c-backups/*) ;; *) echo 'ERROR: invalid backup location'; exit 1 ;; esac
[ -d "$BACKUP" ] || { echo 'ERROR: backup not found'; exit 1; }
# Stop only the processes our installer actually started, using recorded PIDs.
for name in webcam-bridge camera-server; do
    if [ -f "$BASE/$name.pid" ]; then
        pid=$(cat "$BASE/$name.pid")
        case "$pid" in *[!0-9]*|'') ;; *) kill "$pid" 2>/dev/null || true ;; esac
        rm -f "$BASE/$name.pid"
    fi
done
for item in nginx/nginx.conf start-fluidd.sh webcam_bridge.py camera-server-v2.py webcams.json; do
    if [ -f "$BACKUP/$item" ]; then
        cp -p "$BACKUP/$item" "$BASE/$item"
    elif [ -f "$BACKUP/was-absent.txt" ] && grep -Fxq "$item" "$BACKUP/was-absent.txt"; then
        rm -f "$BASE/$item"
    fi
done
if [ -f "$BASE/nginx/nginx.conf" ]; then
    /usr/sbin/nginx -t -c "$BASE/nginx/nginx.conf" &&
    /usr/sbin/nginx -s reload -c "$BASE/nginx/nginx.conf" || true
else
    [ ! -f "$BASE/nginx/nginx.pid" ] || kill "$(cat "$BASE/nginx/nginx.pid")" 2>/dev/null || true
fi
echo 'Rollback complete. Original settings restored where available.'
echo 'UI payload remains on disk and can be removed manually if desired.'
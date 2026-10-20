#!/bin/sh
# K1 Max CFS-C user-space installation. No firmware, CFS, box.cfg or printer.cfg edits.
set -eu
SRC=/usr/data/k1max-cfs-c
BASE=/usr/data/fluidd
BACKUPS=/usr/data/k1max-cfs-c-backups
MODE=${1:---check}
if [ "$MODE" != --check ] && [ "$MODE" != --install ]; then
    echo 'Usage: sh install.sh --check | --install'; exit 2
fi
[ "$(id -u)" = 0 ] || { echo 'ERROR: must run as root.'; exit 1; }
for binary in /usr/bin/python3 /usr/sbin/nginx; do
    [ -x "$binary" ] || { echo "ERROR: missing $binary"; exit 1; }
done
[ -d /usr/data ] || { echo 'ERROR: /usr/data unavailable'; exit 1; }
[ -f "$SRC/ui/index.html" ] || { echo 'ERROR: bundled Fluidd UI not yet uploaded'; exit 1; }
[ -f "$SRC/webcam_bridge.py" ] || { echo 'ERROR: missing webcam_bridge.py'; exit 1; }
[ -f "$SRC/camera-server-v2.py" ] || { echo 'ERROR: missing camera script'; exit 1; }
[ -f "$SRC/nginx-k1max.conf" ] || { echo 'ERROR: missing nginx config'; exit 1; }
[ -f "$SRC/start-fluidd.sh" ] || { echo 'ERROR: missing startup script'; exit 1; }
/usr/bin/python3 -m py_compile "$SRC/webcam_bridge.py" "$SRC/camera-server-v2.py"
sh -n "$SRC/start-fluidd.sh"
mkdir -p "$BASE/nginx"
# Do not replace pre-existing unrelated Fluidd or nginx installation.
if [ -f "$BASE/nginx/nginx.conf" ] && ! grep -q 'K1MAX-CFS-C-INSTALLER' "$BASE/nginx/nginx.conf"; then
    echo 'ERROR: another Fluidd nginx configuration exists.'
    echo 'Refusing to overwrite it. Use the individual patch scripts or manual migration.'
    exit 1
fi
if [ -f "$BASE/start-fluidd.sh" ] && ! grep -q 'K1MAX-CFS-C-INSTALLER' "$BASE/start-fluidd.sh"; then
    echo 'ERROR: another Fluidd startup configuration exists. No changes made.'
    exit 1
fi
# Prove NEXUSP socket exists; no firmware or CFS state is touched.
/usr/bin/python3 - <<'PY'
import socket
with socket.create_connection(('127.0.0.1', 7125), 3):
    print('Creality NEXUSP (7125): reachable')
PY
# If foreign process owns 4408 and we have no previously installed config, abort.
if [ ! -f "$BASE/nginx/nginx.conf" ]; then
    if /usr/bin/python3 - <<'PY'
import socket
try:
    with socket.create_connection(('127.0.0.1', 4408), 1):
        pass
except OSError:
    raise SystemExit(1)
PY
    then
        echo 'ERROR: port 4408 already in use by another service. No changes made.'
        exit 1
    fi
fi
# Validate config using a staged file; user-space only.
mkdir -p "$BASE/nginx"
cp "$SRC/nginx-k1max.conf" "$BASE/nginx/nginx-k1max-check.conf"
if ! /usr/sbin/nginx -t -c "$BASE/nginx/nginx-k1max-check.conf"; then
    rm -f "$BASE/nginx/nginx-k1max-check.conf"
    echo 'ERROR: nginx configuration check failed.'; exit 1
fi
rm -f "$BASE/nginx/nginx-k1max-check.conf"
echo 'PRECHECK PASS: nginx, python3, NEXUSP, UI, and bridge source.'
if command -v ffmpeg >/dev/null 2>&1 && [ -e /dev/video0 ]; then
    echo 'Camera hardware and ffmpeg: detected'
else
    echo 'WARNING: camera dependencies absent; Fluidd and printer controls can still run.'
fi
if [ "$MODE" = --check ]; then exit 0; fi
if [ "${K1MAX_INSTALL_CONFIRM:-}" != IDLE ]; then
    echo 'ERROR: install requires K1MAX_INSTALL_CONFIRM=IDLE after checking printer is idle.'
    exit 1
fi
[ -n "${K1MAX_PRINTER_IP:-}" ] || { echo "ERROR: installer needs K1MAX_PRINTER_IP"; exit 1; }
/usr/bin/python3 - "$K1MAX_PRINTER_IP" <<'PY'
import ipaddress,sys
try: ipaddress.IPv4Address(sys.argv[1])
except ValueError: raise SystemExit("ERROR: invalid IPv4 printer IP")
PY
stamp=$(date +%Y%m%d-%H%M%S)-$$
BACKUP="$BACKUPS/$stamp"
mkdir -p "$BACKUP" "$BASE/nginx"
for item in nginx/nginx.conf start-fluidd.sh webcam_bridge.py camera-server-v2.py webcams.json; do
    if [ -e "$BASE/$item" ]; then
        [ ! -L "$BASE/$item" ] || { echo "ERROR: symlink target $item"; exit 1; }
        mkdir -p "$BACKUP/$(dirname "$item")"
        cp -p "$BASE/$item" "$BACKUP/$item"
    else
        echo "$item" >> "$BACKUP/was-absent.txt"
    fi
done
# Webcam JSON points to each recipient's own printer, not the developer's LAN IP.
if [ ! -e "$BASE/webcams.json" ]; then
    /usr/bin/python3 - "$K1MAX_PRINTER_IP" "$BASE/webcams.json" <<'PY'
import json,sys
ip,path=sys.argv[1:]
cam={'uid':'e31c7b26-2d3e-4d0b-9cd2-6b70d8770e04',
'name':'K1 Max Camera','location':'printer','service':'mjpegstreamer',
'enabled':True,'icon':'mdiWebcam','target_fps':10,'target_fps_idle':5,
'stream_url':'http://%s:8080/stream'%ip,
'snapshot_url':'http://%s:8080/snapshot'%ip,
'flip_horizontal':False,'flip_vertical':False,'rotation':0,
'aspect_ratio':'4:3','extra_data':{},'source':'database'}
with open(path,'w') as f: json.dump([cam],f,indent=2)
PY
fi
cp "$SRC/webcam_bridge.py" "$BASE/webcam_bridge.py"
cp "$SRC/camera-server-v2.py" "$BASE/camera-server-v2.py"
cp "$SRC/nginx-k1max.conf" "$BASE/nginx/nginx.conf"
cp "$SRC/start-fluidd.sh" "$BASE/start-fluidd.sh"
chmod 755 "$BASE/start-fluidd.sh"
echo "$BACKUP" > "$BACKUPS/latest"
if ! sh "$BASE/start-fluidd.sh"; then
    echo 'ERROR: service start failed; restoring backed-up files.'
    sh "$SRC/rollback.sh" "$BACKUP" || true
    exit 1
fi
if ! /usr/bin/python3 "$BASE/webcam_bridge.py" --check; then
    echo 'ERROR: bridge healthcheck failed; restoring backup.'
    sh "$SRC/rollback.sh" "$BACKUP" || true
    exit 1
fi
echo "SUCCESS: printer services installed; rollback: sh $SRC/rollback.sh '$BACKUP'"
#!/bin/sh
# K1MAX-CFS-C-INSTALLER: start only user-space services, no firmware changes.
set -u
BASE=/usr/data/fluidd
PY=/usr/bin/python3
BRIDGE="$BASE/webcam_bridge.py"
CAMERA="$BASE/camera-server-v2.py"
CONF="$BASE/nginx/nginx.conf"
PORT_PID="$BASE/nginx/nginx.pid"

# Start websocket compatibility relay if it is not already listening.
if "$PY" - "$BRIDGE" <<'PY' >/dev/null 2>&1
import socket,sys
s=socket.create_connection(('127.0.0.1',7126),1)
s.close()
PY
then
    echo 'WebSocket bridge already running.'
else
    nohup "$PY" -u "$BRIDGE" </dev/null >>"$BASE/webcam-bridge.log" 2>&1 &
    echo "$!" > "$BASE/webcam-bridge.pid"
    sleep 2
    if ! "$PY" - "$BRIDGE" <<'PY' >/dev/null 2>&1
import socket,sys
s=socket.create_connection(('127.0.0.1',7126),2)
s.close()
PY
    then echo 'ERROR: WebSocket bridge could not start.' >&2; exit 1; fi
fi

if [ -e /dev/video0 ] && command -v ffmpeg >/dev/null 2>&1; then
    if "$PY" - <<'PY' >/dev/null 2>&1
import socket
s=socket.create_connection(('127.0.0.1',8080),1)
s.close()
PY
    then echo 'Camera port 8080 already active.'
    else
        nohup "$PY" -u "$CAMERA" </dev/null >>"$BASE/camera-server.log" 2>&1 &
        echo "$!" > "$BASE/camera-server.pid"
        sleep 2
    fi
else
    echo 'WARNING: Camera disabled: /dev/video0 or ffmpeg unavailable.'
fi

if [ -f "$PORT_PID" ] && kill -0 "$(cat "$PORT_PID")" 2>/dev/null; then
    /usr/sbin/nginx -s reload -c "$CONF" || exit 1
    echo 'Fluidd nginx reloaded.'
else
    /usr/sbin/nginx -c "$CONF" || exit 1
    echo 'Fluidd nginx started at port 4408.'
fi
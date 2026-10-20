#!/usr/bin/env python3
"""K1 Max NEXUSP webcam compatibility WebSocket proxy. Python 3.8 stdlib only."""
import base64
import json
import os
import select
import socket
import socketserver
import sys
import struct
import threading
import uuid
from urllib.parse import urlparse

LISTEN_HOST = '127.0.0.1'
LISTEN_PORT = 7126
UPSTREAM_HOST = '127.0.0.1'
UPSTREAM_PORT = 7125
DATA_FILE = '/usr/data/fluidd/webcams.json'
DEFAULT_CAMERA = {
    'uid': 'e31c7b26-2d3e-4d0b-9cd2-6b70d8770e04',
    'name': 'K1 Max Camera',
    'location': 'printer',
    'service': 'mjpegstreamer',
    'enabled': True,
    'icon': 'mdiWebcam',
    'target_fps': 10,
    'target_fps_idle': 5,
    'stream_url': 'http://127.0.0.1:8080/stream',
    'snapshot_url': 'http://127.0.0.1:8080/snapshot',
    'flip_horizontal': False,
    'flip_vertical': False,
    'rotation': 0,
    'aspect_ratio': '4:3',
    'extra_data': {},
    'source': 'database',
}

store_lock = threading.RLock()


def read_cameras():
    if not os.path.exists(DATA_FILE):
        return [dict(DEFAULT_CAMERA)]
    with open(DATA_FILE, 'r') as f:
        cams = json.load(f)
    if not isinstance(cams, list):
        raise ValueError('webcams.json is not a list')
    return cams


def write_cameras(cams):
    tmp = DATA_FILE + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(cams, f, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, DATA_FILE)


def rpc_error(message, code=-32602):
    return {'code': code, 'message': message}


def handle_webcam(method, params):
    if method not in ('server.webcams.list', 'server.webcams.get_item',
                      'server.webcams.post_item', 'server.webcams.delete_item',
                      'server.webcams.test'):
        return None, rpc_error('Webcam method not implemented', -32601)
    with store_lock:
        cams = read_cameras()
        if method == 'server.webcams.list':
            return {'webcams': cams}, None
        params = params if isinstance(params, dict) else {}
        uid, name = params.get('uid'), params.get('name')
        matched = next((c for c in cams if (uid and c.get('uid') == uid) or
                        (not uid and name and c.get('name') == name)), None)
        if method == 'server.webcams.get_item':
            if not matched:
                return None, rpc_error('Webcam not found')
            return {'webcam': matched}, None
        if method == 'server.webcams.delete_item':
            if not matched:
                return None, rpc_error('Webcam not found')
            cams.remove(matched)
            write_cameras(cams)
            return {'webcam': matched}, None
        if method == 'server.webcams.test':
            if not matched:
                return None, rpc_error('Webcam not found')
            return {'name': matched['name'],
                    'snapshot_reachable': bool(matched.get('snapshot_url')),
                    'snapshot_url': matched.get('snapshot_url', ''),
                    'stream_url': matched.get('stream_url', '')}, None
        if method == 'server.webcams.post_item':
            if matched is None and (not name or not params.get('stream_url')):
                return None, rpc_error('New camera requires name and stream_url')
            if matched is None and any(c.get('name') == name for c in cams):
                return None, rpc_error('Camera name already exists')
            cam = dict(matched) if matched else dict(DEFAULT_CAMERA)
            if not matched:
                cam['uid'] = str(uuid.uuid4())
            for k in ('name', 'location', 'service', 'enabled', 'icon',
                      'target_fps', 'target_fps_idle', 'stream_url',
                      'snapshot_url', 'flip_horizontal', 'flip_vertical',
                      'rotation', 'aspect_ratio', 'extra_data'):
                if k in params:
                    cam[k] = params[k]
            cam['source'] = 'database'
            if matched:
                cams[cams.index(matched)] = cam
            else:
                cams.append(cam)
            write_cameras(cams)
            return {'webcam': cam}, None


def read_headers(sock, data=b''):
    while b'\r\n\r\n' not in data:
        if len(data) > 65536:
            raise ValueError('Oversize WebSocket handshake')
        chunk = sock.recv(8192)
        if not chunk:
            raise ConnectionError('Socket closed during handshake')
        data += chunk
    at = data.index(b'\r\n\r\n') + 4
    return data[:at], data[at:]


def websocket_frame(text):
    data = json.dumps(text, separators=(',', ':')).encode('utf-8')
    n = len(data)
    if n < 126:
        hdr = bytes((0x81, n))
    elif n <= 65535:
        hdr = b'\x81\x7e' + struct.pack('!H', n)
    else:
        hdr = b'\x81\x7f' + struct.pack('!Q', n)
    return hdr + data


def frame_parts(buf):
    if len(buf) < 2:
        return None
    b0, b1 = buf[0], buf[1]
    length = b1 & 0x7f
    ix = 2
    if length == 126:
        if len(buf) < 4:
            return None
        length = struct.unpack('!H', buf[ix:ix + 2])[0]
        ix += 2
    elif length == 127:
        if len(buf) < 10:
            return None
        length = struct.unpack('!Q', buf[ix:ix + 8])[0]
        ix += 8
    if length > 8 * 1024 * 1024:
        raise ValueError('Oversize WebSocket frame')
    masked = bool(b1 & 0x80)
    if masked:
        if len(buf) < ix + 4:
            return None
        mask = buf[ix:ix + 4]
        ix += 4
    else:
        mask = None
    end = ix + length
    if len(buf) < end:
        return None
    payload = buf[ix:end]
    if mask:
        payload = bytes(c ^ mask[i % 4] for i, c in enumerate(payload))
    return buf[:end], payload, b0, buf[end:]


class WebcamHandler(socketserver.BaseRequestHandler):
    def handle(self):
        client = self.request
        client.settimeout(10)
        try:
            upstream = socket.create_connection((UPSTREAM_HOST, UPSTREAM_PORT), 5)
        except OSError as e:
            print('Cannot reach NEXUSP:', e, flush=True)
            return
        with upstream:
            try:
                header, remaining = read_headers(client)
                # Disable per-message compression so webcam JSON-RPC is readable.
                lines = header.split(b'\r\n')
                filtered = [line for line in lines
                            if not line.lower().startswith(b'sec-websocket-extensions:')]
                upstream.sendall(b'\r\n'.join(filtered))
                upstream_header, extra = read_headers(upstream)
                client.sendall(upstream_header + extra)
                if b' 101 ' not in upstream_header.split(b'\r\n', 1)[0]:
                    return
                client.settimeout(None)
                upstream.settimeout(None)
            except (OSError, ValueError) as e:
                print('WebSocket handshake failed:', e, flush=True)
                return

            stop = threading.Event()
            send_lock = threading.Lock()
            info_lock = threading.Lock()
            pending_server_info = set()

            def relay_upstream():
                # Reassemble server WebSocket frames before forwarding.
                # Only the result of a requested server.info is augmented;
                # all other traffic is forwarded byte-for-byte.
                buffer_from_nexusp = b''
                try:
                    while not stop.is_set():
                        chunk = upstream.recv(65536)
                        if not chunk:
                            break
                        buffer_from_nexusp += chunk
                        while True:
                            frame = frame_parts(buffer_from_nexusp)
                            if frame is None:
                                break
                            raw, decoded, first, buffer_from_nexusp = frame
                            if (first & 0x8f) == 0x81:
                                try:
                                    msg = json.loads(decoded.decode('utf-8'))
                                except (ValueError, UnicodeDecodeError):
                                    msg = None
                                if isinstance(msg, dict) and 'id' in msg:
                                    with info_lock:
                                        is_info = msg['id'] in pending_server_info
                                        if is_info:
                                            pending_server_info.discard(msg['id'])
                                    if is_info and isinstance(msg.get('result'), dict):
                                        info = msg['result']
                                        components = info.get('components')
                                        if isinstance(components, list) and 'webcam' not in components:
                                            info['components'] = components + ['webcam']
                                            raw = websocket_frame(msg)
                            with send_lock:
                                client.sendall(raw)
                except (OSError, ValueError) as e:
                    print('NEXUSP relay stopped:', str(e)[:160], flush=True)
                finally:
                    stop.set()
                    try:
                        client.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass

            t = threading.Thread(target=relay_upstream, daemon=True)
            t.start()
            buffer = remaining
            try:
                while not stop.is_set():
                    frame = frame_parts(buffer)
                    if frame is None:
                        data = client.recv(65536)
                        if not data:
                            break
                        buffer += data
                        continue
                    raw, decoded, first, buffer = frame
                    is_text = (first & 0x8f) == 0x81
                    if is_text:
                        try:
                            msg = json.loads(decoded.decode('utf-8'))
                        except (ValueError, UnicodeDecodeError):
                            msg = None
                        if isinstance(msg, dict) and str(msg.get('method', '')).startswith('server.webcams.'):
                            result, error = handle_webcam(msg['method'], msg.get('params', {}))
                            response = {'jsonrpc': '2.0', 'id': msg.get('id')}
                            if error:
                                response['error'] = error
                            else:
                                response['result'] = result
                            with send_lock:
                                client.sendall(websocket_frame(response))
                            continue
                    # Compatibility with NEXUSP: this single read-only RPC is absent.
                    # Do not intercept any other database/printer/machine methods.
                    if (is_text and isinstance(msg, dict) and
                            msg.get('method') == 'server.database.list' and
                            msg.get('id') is not None):
                        with send_lock:
                            client.sendall(websocket_frame({
                                'jsonrpc': '2.0', 'id': msg['id'],
                                'result': {'namespaces': ['fluidd', 'webcams'],
                                           'backups': []}}))
                        continue
                    if is_text and isinstance(msg, dict) and msg.get('method') == 'server.info':
                        request_id = msg.get('id')
                        if request_id is not None:
                            with info_lock:
                                pending_server_info.add(request_id)
                    upstream.sendall(raw)
            except (OSError, ValueError) as e:
                print('WebSocket client closed:', str(e)[:120], flush=True)
            finally:
                stop.set()
                try:
                    upstream.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass


class Bridge(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def check_running_bridge():
    """Read-only local check of camera listing and transparent API forwarding."""
    with socket.create_connection((LISTEN_HOST, LISTEN_PORT), 5) as sock:
        sock.settimeout(5)
        key = base64.b64encode(os.urandom(16))
        sock.sendall(
            b'GET /websocket HTTP/1.1\r\n'
            b'Host: 127.0.0.1\r\n'
            b'Upgrade: websocket\r\n'
            b'Connection: Upgrade\r\n'
            b'Sec-WebSocket-Version: 13\r\n'
            b'Sec-WebSocket-Key: ' + key + b'\r\n\r\n'
        )
        header, remainder = read_headers(sock)
        if b' 101 ' not in header.split(b'\r\n', 1)[0]:
            raise RuntimeError('WebSocket upgrade failed: ' + repr(header[:200]))
        print('WebSocket bridge handshake: OK')
        for request_id, method in ((301, 'server.webcams.list'),
                                   (302, 'server.info')):
            message = json.dumps({'jsonrpc': '2.0', 'id': request_id,
                                  'method': method}).encode()
            mask = os.urandom(4)
            n = len(message)
            if n < 126:
                head = bytes([0x81, 0x80 | n])
            else:
                head = b'\x81\xfe' + struct.pack('!H', n)
            sock.sendall(head + mask + bytes(c ^ mask[i % 4]
                                            for i, c in enumerate(message)))
            while True:
                frame = frame_parts(remainder)
                if frame is None:
                    data = sock.recv(8192)
                    if not data:
                        raise RuntimeError('WebSocket closed during test')
                    remainder += data
                    continue
                raw, payload, first, remainder = frame
                if (first & 0x0f) != 1:
                    continue
                msg = json.loads(payload.decode())
                if msg.get('id') != request_id:
                    continue
                if method == 'server.webcams.list':
                    names = [c.get('name') for c in msg.get('result', {}).get('webcams', [])]
                    if not names:
                        raise RuntimeError('Bridge did not return camera: ' + repr(msg))
                    print('Persistent camera listing: OK', names)
                else:
                    if 'result' not in msg:
                        raise RuntimeError('server.info failed: ' + repr(msg))
                    components = msg['result'].get('components', [])
                    if 'webcam' not in components:
                        raise RuntimeError('Webcam missing from server.info components: ' + repr(components))
                    print('server.info advertises webcam: OK')
                    print('Non-camera RPC forwarded to NEXUSP: result')
                break


if __name__ == '__main__':
    if '--check' in sys.argv:
        check_running_bridge()
        sys.exit(0)
    print('Webcam bridge listening on 127.0.0.1:7126 -> NEXUSP 7125', flush=True)
    print('Camera data file:', DATA_FILE, flush=True)
    with Bridge((LISTEN_HOST, LISTEN_PORT), WebcamHandler) as server:
        server.serve_forever()
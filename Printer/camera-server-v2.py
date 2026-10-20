#!/usr/bin/env python3
"""Optional LAN MJPEG bridge for Creality camera. Runs in userspace, port 8080.
Uses a single ffmpeg /dev/video0 capture process shared by all viewers.
Python 3.8 standard library. Avoid exposing port 8080 to the internet.
"""
import http.server
import os
import subprocess
import threading
import time

HOST = '0.0.0.0'
PORT = 8080
DEVICE = os.environ.get('K1MAX_CAMERA_DEVICE', '/dev/video0')
JPEG_MAX = 2 * 1024 * 1024
lock = threading.Condition()
latest_frame = None


def frame_worker():
    global latest_frame
    while True:
        if not os.path.exists(DEVICE):
            print('Camera missing: '+DEVICE, flush=True)
            time.sleep(5)
            continue
        commands = [
            ['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error',
             '-f', 'video4linux2', '-input_format', 'mjpeg', '-framerate', '10',
             '-i', DEVICE, '-f', 'mjpeg', '-q:v', '5', 'pipe:1'],
            ['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error',
             '-f', 'video4linux2', '-i', DEVICE, '-f', 'mjpeg', '-q:v', '5', 'pipe:1']]
        for cmd in commands:
            try:
                proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL, bufsize=0)
            except OSError as e:
                print('Camera ffmpeg start failed:', e, flush=True)
                time.sleep(5)
                break
            buf = bytearray()
            frames = 0
            try:
                while True:
                    chunk = proc.stdout.read(4096)
                    if not chunk:
                        break
                    buf.extend(chunk)
                    while True:
                        soi = buf.find(b'\xff\xd8')
                        if soi < 0:
                            buf.clear()
                            break
                        if soi > 0:
                            del buf[:soi]
                        eoi = buf.find(b'\xff\xd9', 2)
                        if eoi < 0:
                            if len(buf) > JPEG_MAX:
                                buf.clear()
                            break
                        frame = bytes(buf[:eoi+2])
                        del buf[:eoi+2]
                        with lock:
                            latest_frame = frame
                            lock.notify_all()
                        frames += 1
            finally:
                if proc.poll() is None:
                    proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
            if frames:
                break
        time.sleep(2)


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        if self.path.split('?')[0] not in ('/snapshot', '/stream'):
            self.send_error(404)
            return
        with lock:
            if latest_frame is None:
                lock.wait(timeout=5)
            frame = latest_frame
        if frame is None:
            self.send_error(503, 'Camera warming up or unavailable')
            return
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        if self.path.startswith('/snapshot'):
            self.send_header('Content-Type', 'image/jpeg')
            self.send_header('Content-Length', str(len(frame)))
            self.end_headers()
            self.wfile.write(frame)
            return
        self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=frame')
        self.end_headers()
        try:
            while True:
                with lock:
                    lock.wait(timeout=1.5)
                    frame = latest_frame
                if frame:
                    self.wfile.write(b'--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ' +
                                     str(len(frame)).encode() + b'\r\n\r\n' + frame + b'\r\n')
                    self.wfile.flush()
        except (OSError, BrokenPipeError, ConnectionResetError):
            pass


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == '__main__':
    threading.Thread(target=frame_worker, daemon=True).start()
    print('Camera bridge listening on 0.0.0.0:8080', flush=True)
    Server((HOST, PORT), Handler).serve_forever()
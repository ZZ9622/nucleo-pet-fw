#!/usr/bin/env python3
"""Read-only USB state bridge. Python standard library, macOS, 9600 8N1."""
import argparse
import hmac
import json
import os
import select
import termios
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def validate(line):
    value = json.loads(line)
    if (value.get('v') != 1 or type(value.get('seq')) is not int
            or not 0 < value['seq'] <= 0xffffffff
            or any(type(value.get(k)) is not int or not 0 <= value[k] <= 100
                   for k in ('energy', 'happiness'))
            or type(value.get('sleeping')) is not bool):
        raise ValueError('Invalid device state')
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', required=True, help='/dev/cu.usbmodem…')
    parser.add_argument('--bind', default='127.0.0.1')
    parser.add_argument('--http-port', type=int, default=8765)
    args = parser.parse_args()
    token = os.environ.get('PET_BRIDGE_TOKEN')
    if not token:
        parser.error('Set PET_BRIDGE_TOKEN to a private token first')
    lock = threading.Lock()
    latest = None
    received = 0.0

    def reader():
        nonlocal latest, received
        while True:
            fd = None
            try:
                fd = os.open(args.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
                attr = termios.tcgetattr(fd)
                attr[0] = attr[1] = attr[3] = 0
                attr[2] = termios.CLOCAL | termios.CREAD | termios.CS8
                attr[4] = attr[5] = termios.B9600
                attr[6][termios.VMIN] = attr[6][termios.VTIME] = 0
                termios.tcsetattr(fd, termios.TCSANOW, attr)
                termios.tcflush(fd, termios.TCIOFLUSH)
                buffer = b''
                while True:
                    os.write(fd, b'?')
                    deadline = time.monotonic() + 1
                    while time.monotonic() < deadline:
                        if not select.select([fd], [], [], max(0, deadline-time.monotonic()))[0]:
                            break
                        chunk = os.read(fd, 512)
                        if not chunk:
                            raise OSError('Serial disconnected')
                        buffer += chunk
                        if len(buffer) > 1024:
                            raise ValueError('Oversize serial response')
                        while b'\n' in buffer:
                            line, buffer = buffer.split(b'\n', 1)
                            try:
                                value = validate(line)
                            except (ValueError, TypeError, AttributeError):
                                continue
                            with lock:
                                latest, received = value, time.monotonic()
            except (OSError, ValueError, termios.error):
                with lock:
                    latest, received = None, 0
                time.sleep(1)
            finally:
                if fd is not None:
                    os.close(fd)

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if not hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + token):
                self.send_error(401)
                return
            if self.path != '/state':
                self.send_error(404)
                return
            with lock:
                fresh = latest is not None and time.monotonic() - received < 3
                payload = json.dumps({'connected': fresh, 'state': latest if fresh else None}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer((args.bind, args.http_port), Handler)
    threading.Thread(target=reader, daemon=True).start()
    print(f'Read-only bridge listening on {args.bind}:{args.http_port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()

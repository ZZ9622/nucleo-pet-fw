#!/usr/bin/env python3
"""Authenticated USB handoff bridge, macOS stdlib, protocol v2 / 115200 8N1."""
import argparse
import hmac
import json
import os
import select
import termios
import threading
import time
import uuid
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KEYS = ('energy', 'happiness', 'experience', 'coins', 'level', 'stage', 'isSleeping',
        'lowEnergyAwakeSeconds', 'secondsSinceFeed', 'awakeDecayElapsedSeconds',
        'sleepRecoveryElapsedSeconds', 'gameTimeSeconds', 'rngState', 'feedback')
LIMITS = (100, 100, 65535, 65535, 99, 2, 1, 3, 86400, 3599, 59, 0xffffffff, 0xffffffff, 10)


def words_valid(words):
    return (isinstance(words, list) and len(words) == 14
            and all(type(v) is int and 0 <= v <= maximum for v, maximum in zip(words, LIMITS))
            and words[4] >= 1 and (words[8] < 86400 or words[0] == 0))


def identifier(value):
    if not isinstance(value, str):
        raise ValueError('Missing identity')
    return uuid.UUID(value).hex


def decode_frame(line, request_id):
    data, crc = line.rsplit(b'|', 1)
    if len(crc) != 8 or zlib.crc32(data) != int(crc, 16):
        raise ValueError('Serial checksum mismatch')
    value = json.loads(data)
    if (value.get('v') != 2 or value.get('requestID') != request_id
            or type(value.get('ok')) is not bool or type(value.get('error')) is not str
            or type(value.get('phase')) is not int or value['phase'] not in range(5)
            or type(value.get('revision')) is not int or not 0 <= value['revision'] < 0xffffffff
            or type(value.get('payloadHash')) is not int or not 0 <= value['payloadHash'] <= 0xffffffff
            or not words_valid(value.get('state'))):
        raise ValueError('Invalid board response')
    value['petID'] = str(uuid.UUID(value['petID']))
    value['transferID'] = str(uuid.UUID(value['transferID']))
    value['state'] = dict(zip(KEYS, value['state']))
    value['state']['isSleeping'] = bool(value['state']['isSleeping'])
    return value


class SerialTransport:
    def __init__(self, port):
        self.port = port
        self.lock = threading.Lock()
        self.fd = None

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def request(self, command='STATUS', payload=None):
        payload = payload or {}
        request_id = uuid.uuid4().hex
        pet_id = identifier(payload.get('petID', '0' * 32))
        transfer_id = identifier(payload.get('transferID', '0' * 32))
        revision = payload.get('revision', 0)
        if type(revision) is not int or not 0 <= revision < 0xffffffff:
            raise ValueError('Invalid revision')
        state = ''
        if command == 'RETURN_STAGE':
            source = payload['state']
            words = [source[k] for k in KEYS]
            if type(words[6]) is not bool:
                raise ValueError('Invalid sleep state')
            words[6] = int(words[6])
            if not words_valid(words):
                raise ValueError('Invalid pet state')
            state = ','.join(map(str, words))
        data = f'!{request_id}|{command}|{pet_id}|{transfer_id}|{revision}|{state}'.encode()
        frame = data + f'|{zlib.crc32(data):08x}\n'.encode()
        with self.lock:
            for attempt in range(3):
                try:
                    if self.fd is None:
                        self.fd = os.open(self.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
                        attr = termios.tcgetattr(self.fd)
                        attr[0] = attr[1] = attr[3] = 0
                        attr[2] = termios.CLOCAL | termios.CREAD | termios.CS8
                        attr[4] = attr[5] = termios.B115200
                        attr[6][termios.VMIN] = attr[6][termios.VTIME] = 0
                        termios.tcsetattr(self.fd, termios.TCSANOW, attr)
                    termios.tcflush(self.fd, termios.TCIFLUSH)
                    sent = 0
                    deadline = time.monotonic() + 4
                    while sent < len(frame):
                        if not select.select([], [self.fd], [], max(0, deadline-time.monotonic()))[1]:
                            raise TimeoutError('USB write timed out')
                        sent += os.write(self.fd, frame[sent:])
                    buffer = b''
                    while time.monotonic() < deadline:
                        if not select.select([self.fd], [], [], max(0, deadline-time.monotonic()))[0]:
                            break
                        chunk = os.read(self.fd, 2048)
                        if not chunk:
                            raise OSError('USB disconnected')
                        buffer += chunk
                        if len(buffer) > 4096:
                            raise ValueError('Oversize serial response')
                        while b'\n' in buffer:
                            line, buffer = buffer.split(b'\n', 1)
                            try:
                                return decode_frame(line, request_id)
                            except (ValueError, KeyError, TypeError):
                                continue
                    raise TimeoutError('Board did not acknowledge; retry the same journey')
                except (OSError, ValueError, termios.error):
                    self.close()
                    if attempt == 2:
                        raise
            raise OSError('USB unavailable')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', required=True)
    parser.add_argument('--bind', default='127.0.0.1')
    parser.add_argument('--http-port', type=int, default=8765)
    args = parser.parse_args()
    token = os.environ.get('PET_BRIDGE_TOKEN')
    if not token:
        parser.error('Set PET_BRIDGE_TOKEN first')
    transport = SerialTransport(args.port)

    class Handler(BaseHTTPRequestHandler):
        def reply(self, code, value):
            data = json.dumps(value).encode()
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def authorized(self):
            if hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + token):
                return True
            self.reply(401, {'error': 'Unauthorized'})
            return False

        def do_GET(self):
            if not self.authorized():
                return
            if self.path not in ('/state', '/device'):
                self.reply(404, {'error': 'Not found'})
                return
            try:
                value = transport.request()
                if self.path == '/state':
                    s = value['state']
                    value = {'connected': True, 'state': {'v': 1, 'seq': 1,
                        'energy': s['energy'], 'happiness': s['happiness'], 'sleeping': s['isSleeping']}}
                self.reply(200, value)
            except (OSError, ValueError, termios.error):
                self.reply(503, {'error': 'USB disconnected or no valid response'})

        def do_POST(self):
            if not self.authorized():
                return
            routes = {'/handoff/take/prepare': 'TAKE_PREPARE', '/handoff/take/commit': 'TAKE_COMMIT',
                      '/handoff/return/stage': 'RETURN_STAGE', '/handoff/return/commit': 'RETURN_COMMIT'}
            if self.path not in routes:
                self.reply(404, {'error': 'Not found'})
                return
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 4096:
                    raise ValueError('Invalid request size')
                self.connection.settimeout(5)
                payload = json.loads(self.rfile.read(size))
                if not isinstance(payload, dict) or any(k not in payload for k in ('petID', 'transferID', 'revision')):
                    raise ValueError('Missing handoff identity')
                value = transport.request(routes[self.path], payload)
                self.reply(200 if value['ok'] else 409, value)
            except (ValueError, KeyError, TypeError):
                self.reply(400, {'error': 'Invalid request'})
            except (OSError, termios.error):
                self.reply(503, {'error': 'No receipt; keep this journey pending and retry'})

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer((args.bind, args.http_port), Handler)
    server.daemon_threads = True
    print(f'USB handoff v2 bridge listening on {args.bind}:{args.http_port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        with transport.lock:
            transport.close()


if __name__ == '__main__':
    main()

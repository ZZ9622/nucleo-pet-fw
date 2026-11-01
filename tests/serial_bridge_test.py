"""Exercise the real bridge against a pseudo terminal; no board required."""
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import socket
import subprocess
import sys
import time
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bridge', ROOT / 'tools/serial_bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class BridgeTests(unittest.TestCase):
    def test_validation(self):
        valid = dict(v=1, seq=1, energy=80, happiness=75, sleeping=False)
        self.assertEqual(bridge.validate(json.dumps(valid)), valid)
        for key, value in [('energy', 101), ('happiness', True), ('sleeping', 0), ('v', 2)]:
            with self.assertRaises(ValueError):
                bridge.validate(json.dumps(dict(valid, **{key: value})))

    def test_serial_http_auth_and_stale(self):
        master, slave = pty.openpty()
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        process = subprocess.Popen([sys.executable, str(ROOT / 'tools/serial_bridge.py'),
            '--port', os.ttyname(slave), '--http-port', str(port)],
            env=dict(os.environ, PET_BRIDGE_TOKEN='test-only'), stdout=subprocess.PIPE)
        url = f'http://127.0.0.1:{port}/state'
        def get(authorized=True):
            headers = {'Authorization': 'Bearer test-only'} if authorized else {}
            with urlopen(Request(url, headers=headers), timeout=2) as response:
                return json.load(response)
        try:
            self.assertTrue(process.stdout.readline())
            with self.assertRaises(HTTPError) as caught:
                get(False)
            self.assertEqual(caught.exception.code, 401)
            self.assertTrue(select.select([master], [], [], 3)[0])
            self.assertIn(b'?', os.read(master, 64))
            os.write(master, b'{"v":1,"seq":1,"energy":80,')
            os.write(master, b'"happiness":75,"sleeping":false}\n')
            deadline = time.monotonic() + 2
            while True:
                result = get()
                if result['connected'] or time.monotonic() >= deadline:
                    break
                time.sleep(.05)
            self.assertTrue(result['connected'])
            self.assertEqual(result['state']['happiness'], 75)
            time.sleep(3.1)
            self.assertEqual(get(), {'connected': False, 'state': None})
            os.close(master)
            master = None
            time.sleep(.2)
            self.assertFalse(get()['connected'])
        finally:
            process.terminate()
            process.wait(timeout=3)
            process.stdout.close()
            if master is not None:
                os.close(master)
            os.close(slave)


if __name__ == '__main__':
    unittest.main()

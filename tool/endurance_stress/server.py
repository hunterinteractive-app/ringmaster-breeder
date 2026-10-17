#!/usr/bin/env python3
"""Loopback-only static host, fault proxy, and evidence collector. Synthetic data only."""
import http.server
import json
from pathlib import Path
import threading
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / 'build/web'
OUT = ROOT / 'deliverables/scaling-fixes/endurance-browser-samples.jsonl'
STATUS = json.loads(Path('/private/tmp/rmb-next-stress/local-status.json').read_text())
assert STATUS['API_URL'] == 'http://127.0.0.1:56431'
LOCK = threading.Lock()
MODE = 'normal'
COUNTS = {'requests': 0, 'injected_offline': 0, 'lost_acknowledgements': 0, 'slow_requests': 0}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(BUILD), **kwargs)

    def log_message(self, *args):
        pass  # Do not log subscription URLs or bearer tokens.

    def reply(self, status, body, content_type='application/json'):
        data = body.encode() if isinstance(body, str) else json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def body(self):
        return self.rfile.read(int(self.headers.get('Content-Length', 0)))

    def do_GET(self):
        if self.path == '/fixture.json':
            return self.reply(200, {'key': STATUS['ANON_KEY'], 'email': 'scale-owner@example.invalid',
                                    'password': 'Synthetic-stress-only-2026!'})
        if self.path == '/metrics':
            return self.reply(200, {**COUNTS, 'mode': MODE})
        if self.path.startswith('/backend/'):
            return self.proxy()
        return super().do_GET()

    def do_POST(self):
        global MODE
        if self.path == '/control':
            mode = json.loads(self.body())['mode']
            assert mode in ['normal', 'offline', 'slow', 'lose-next-write-ack']
            with LOCK:
                MODE = mode
            return self.reply(200, {'mode': MODE})
        if self.path == '/evidence':
            data = json.loads(self.body())
            data['proxy'] = dict(COUNTS)
            data['server_timestamp'] = time.time()
            OUT.parent.mkdir(exist_ok=True)
            with LOCK, OUT.open('a') as output:
                output.write(json.dumps(data) + '\n')
            return self.reply(200, {'saved': True})
        if self.path.startswith('/backend/'):
            return self.proxy()
        self.reply(404, {})

    def do_PATCH(self):
        return self.proxy()

    def do_DELETE(self):
        return self.proxy()

    def do_OPTIONS(self):
        self.reply(200, {})

    def proxy(self):
        global MODE
        assert self.path.startswith('/backend/')
        path = self.path[len('/backend'):]
        raw = self.body() if self.command in ['POST', 'PATCH', 'DELETE'] else None
        with LOCK:
            COUNTS['requests'] += 1
            mode = MODE
            lose_ack = mode == 'lose-next-write-ack' and self.command == 'POST' and path.startswith('/rest/v1/animal_weights')
            if lose_ack:
                MODE = 'normal'
        if mode == 'offline':
            COUNTS['injected_offline'] += 1
            return self.reply(503, {'message': 'Synthetic connection interruption', 'code': 'LOCAL_TEST_OFFLINE'})
        if mode == 'slow':
            COUNTS['slow_requests'] += 1
            time.sleep(.35)
        headers = {k: v for k, v in self.headers.items()
                   if k.lower() not in ['host', 'content-length', 'connection', 'accept-encoding']}
        request = urllib.request.Request(STATUS['API_URL'] + path, data=raw, headers=headers, method=self.command)
        try:
            response = urllib.request.urlopen(request, timeout=75)
        except urllib.error.HTTPError as error:
            response = error
        except Exception as error:
            return self.reply(502, {'message': str(type(error).__name__)})
        with response:
            data = response.read()
            if lose_ack and 200 <= response.status < 300:
                COUNTS['lost_acknowledgements'] += 1
                return self.reply(503, {'message': 'Synthetic lost success acknowledgement', 'code': 'LOCAL_TEST_LOST_ACK'})
            self.send_response(response.status)
            for name, value in response.headers.items():
                if name.lower() not in ['transfer-encoding', 'connection', 'content-length', 'content-encoding']:
                    self.send_header(name, value)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass


if __name__ == '__main__':
    print('Synthetic stress host listening on http://127.0.0.1:56440', flush=True)
    http.server.ThreadingHTTPServer(('127.0.0.1', 56440), Handler).serve_forever()

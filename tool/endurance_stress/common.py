"""Only the explicitly named local Supabase stack is accepted."""
import hashlib
import json
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
STATUS = json.loads(Path('/private/tmp/rmb-next-stress/local-status.json').read_text())
API = STATUS['API_URL']
assert API == 'http://127.0.0.1:56431', 'Refusing a non-local API'
DB = 'supabase_db_rmb-next-stress'
RING = 'e1000000-0000-4000-8000-000000000010'
OWNER = 'e1000000-0000-4000-8000-000000000001'


def uid(value):
    return str(uuid.UUID(hashlib.md5(value.encode()).hexdigest()))


def sql(query, check=True):
    result = subprocess.run(['docker', 'exec', '-i', DB, 'psql', '-U', 'postgres', '-d', 'postgres',
                             '-v', 'ON_ERROR_STOP=1', '-Atq'], input=query, text=True, capture_output=True, timeout=180)
    if check and result.returncode:
        raise AssertionError(result.stderr[-2200:])
    return result


def request(path, token=None, method='GET', body=None, timeout=90, headers=None):
    h = {'apikey': STATUS['ANON_KEY'], 'Content-Type': 'application/json'}
    if token:
        h['Authorization'] = 'Bearer ' + token
    h.update(headers or {})
    req = urllib.request.Request(API + path, method=method, headers=h,
                                 data=json.dumps(body).encode() if body is not None else None)
    start = time.monotonic()
    try:
        response = urllib.request.urlopen(req, timeout=timeout)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        raw = response.read()
        result = json.loads(raw) if raw and 'json' in response.headers.get('Content-Type', '') else raw.decode()
        return response.status, result, dict(response.headers), round((time.monotonic() - start) * 1000, 2)


def login(email):
    status, data, _, _ = request('/auth/v1/token?grant_type=password', method='POST',
                                body={'email': email, 'password': 'Synthetic-stress-only-2026!'})
    assert status == 200, (status, data)
    return data['access_token']


def evidence(filename, data):
    output = ROOT / 'deliverables/scaling-fixes'
    output.mkdir(exist_ok=True)
    (output / filename).write_text(json.dumps(data, indent=2) + '\n')

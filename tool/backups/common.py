"""Private admin utilities. No credentials are put in subprocess arguments/logs."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import uuid
from urllib.parse import parse_qsl, unquote, urlparse


def literal(value):
    if '\x00' in str(value):
        raise ValueError('NUL is not valid SQL text')
    return "E'" + str(value).replace('\\', '\\\\').replace("'", "''") + "'"


def ident(value):
    return '"' + value.replace('"', '""') + '"'


def sha256(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, data):
    Path(path).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


def run(command, **kwargs):
    # Database errors can contain row data. Keep diagnostics off CI logs.
    result = subprocess.run(command, stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        raise RuntimeError(f'{Path(command[0]).name} failed (exit {result.returncode}); '
                           'inspect privately, never publish database diagnostics')
    return result


class Database:
    """A persistent psql session permits pg_dump to share an exported snapshot."""
    def __init__(self, url):
        parsed = urlparse(url)
        if parsed.scheme not in ('postgres', 'postgresql') or not parsed.hostname or not parsed.username:
            raise ValueError('Expected a PostgreSQL connection URI')
        self.env = dict(os.environ, PGHOST=parsed.hostname, PGPORT=str(parsed.port or 5432),
                        PGUSER=unquote(parsed.username), PGPASSWORD=unquote(parsed.password or ''),
                        PGDATABASE=unquote(parsed.path.lstrip('/')), PGCONNECT_TIMEOUT='30')
        options = {'sslmode': 'PGSSLMODE', 'sslrootcert': 'PGSSLROOTCERT',
                   'application_name': 'PGAPPNAME', 'channel_binding': 'PGCHANNELBINDING'}
        for name, value in parse_qsl(parsed.query):
            if name not in options:
                raise ValueError('Unsupported database URI option: ' + name)
            self.env[options[name]] = value
        self.errors = tempfile.TemporaryFile()
        self.process = subprocess.Popen(
            ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'],
            env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=self.errors, text=True, bufsize=1)

    def execute(self, sql):
        marker = 'done_' + uuid.uuid4().hex
        self.process.stdin.write(sql + '\n\\echo ' + marker + '\n')
        self.process.stdin.flush()
        lines = []
        for line in self.process.stdout:
            if line.rstrip('\n') == marker:
                return '\n'.join(lines)
            lines.append(line.rstrip('\n'))
        raise RuntimeError('Database command failed; transaction rolled back. '
                           'Diagnostics withheld because they may contain private records.')

    def json(self, sql):
        return json.loads(self.execute(sql))

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            self.process.wait(timeout=30)
        if not self.process.stdin.closed:
            self.process.stdin.close()
        self.process.stdout.close()
        self.errors.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

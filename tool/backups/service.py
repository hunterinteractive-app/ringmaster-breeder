"""Encrypted whole-service snapshots and verified Backblaze B2 uploads.

Requires PostgreSQL 17+ clients, gpg, and (for upload) AWS CLI v2. Python stdlib only.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen
import uuid

from common import Database, literal, run, sha256, write_json
from owner import TABLES, PRESERVED, export_owner

PROJECT = 'aqfsrolvaewcpkdkttiz'
PREFIX = 'ringmaster-breeder/service'
OBJECTS_SQL = """SELECT coalesce(jsonb_agg(to_jsonb(t)-'last_accessed_at' ORDER BY bucket_id,name),'[]')
                 FROM storage.objects t"""


def object_key(bucket, name):
    return hashlib.sha256((bucket + '\0' + name).encode()).hexdigest()


def fetch_object(url, key, obj, path):
    request = Request(url.rstrip('/') + '/storage/v1/object/' +
                      quote(obj['bucket_id'], safe='') + '/' + quote(obj['name'], safe='/'),
                      headers={'apikey': key, 'Authorization': 'Bearer ' + key})
    # Never follow a redirect with a privileged Authorization header.
    import urllib.request
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *_):
            return None
    with urllib.request.build_opener(NoRedirect).open(request, timeout=120) as response:
        with path.open('wb') as target:
            shutil.copyfileobj(response, target)
    size = (obj.get('metadata') or {}).get('size')
    if size is not None and path.stat().st_size != int(size):
        raise ValueError('Storage object size mismatch; snapshot is incomplete')


def crypt(source, target, decrypt=False):
    # Separate descriptor avoids putting the passphrase on argv or in plaintext files.
    secret = os.environ['BACKUP_PASSPHRASE']
    if '\n' in secret or not 32 <= len(secret.encode()) <= 4096:
        raise ValueError('BACKUP_PASSPHRASE must be a single line of at least 32 characters')
    read_fd, write_fd = os.pipe()
    try:
        os.write(write_fd, (secret + '\n').encode())
        os.close(write_fd)
        write_fd = None
        with tempfile.TemporaryDirectory(prefix='breeder-gpg-') as home:
            command = ['gpg', '--homedir', home, '--batch', '--no-symkey-cache',
                       '--pinentry-mode', 'loopback', '--passphrase-fd', str(read_fd),
                       '--output', str(target)]
            command += ['--decrypt'] if decrypt else ['--symmetric', '--cipher-algo', 'AES256']
            run(command + [str(source)], pass_fds=(read_fd,), stdout=subprocess.DEVNULL)
    finally:
        os.close(read_fd)
        if write_fd is not None:
            os.close(write_fd)


def verify_directory(root):
    manifest = json.loads((root / 'manifest.json').read_text())
    if manifest.get('format') != 'ringmaster-breeder-service' or manifest.get('version') != 1:
        raise ValueError('Unsupported backup format')
    expected = set(manifest['checksums']) | {'manifest.json'}
    actual = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
    if actual != expected or not {'database.dump', 'roles.sql', 'source.tar', 'objects.json'} <= expected:
        raise ValueError('Archive contents do not match the manifest')
    for name, checksum in manifest['checksums'].items():
        if Path(name).is_absolute() or '..' in Path(name).parts:
            raise ValueError('Unsafe manifest path')
        path = root / name
        if path.is_symlink() or not path.is_relative_to(root) or sha256(path) != checksum:
            raise ValueError('Backup checksum mismatch')
    return manifest


def extract(archive, output):
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    try:
        with tempfile.TemporaryDirectory(prefix='breeder-decrypt-') as temp:
            tar = Path(temp) / 'archive.tar.gz'
            crypt(archive, tar, decrypt=True)
            with tarfile.open(tar, 'r:gz') as bundle:
                members = bundle.getmembers()
                names = set()
                for member in members:
                    name = Path(member.name)
                    if (not member.isfile() or name.is_absolute() or '..' in name.parts
                            or name.as_posix() in names):
                        raise ValueError('Unsafe or duplicate archive member')
                    names.add(name.as_posix())
                bundle.extractall(output, members=members, filter='data')
        return verify_directory(output)
    except Exception:
        shutil.rmtree(output)
        raise


def validate_source(db_url, api_url):
    if api_url != f'https://{PROJECT}.supabase.co':
        raise ValueError('This tool is restricted to the Breeder project')
    parsed = urlparse(db_url)
    direct = parsed.hostname == f'db.{PROJECT}.supabase.co'
    pooler = ((parsed.hostname or '').endswith('.pooler.supabase.com')
              and parsed.username == 'postgres.' + PROJECT and parsed.port == 5432)
    if not (direct or pooler):
        raise ValueError('Use the Breeder direct or session-pooler connection string')


def create(output):
    db_url = os.environ['SUPABASE_DB_URL']
    api_url = os.environ['SUPABASE_URL'].rstrip('/')
    validate_source(db_url, api_url)
    key = os.environ['SUPABASE_SERVICE_ROLE_KEY']
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    stamp = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H-%M-%SZ')
    name = f'breeder-{stamp}-{uuid.uuid4().hex[:12]}.tar.gz.gpg'
    encrypted = output / name
    try:
        with tempfile.TemporaryDirectory(prefix='breeder-backup-') as temp:
            root = Path(temp) / 'snapshot'
            root.mkdir(mode=0o700)
            (root / 'objects').mkdir()
            (root / 'owners').mkdir()
            with Database(db_url) as db:
                db.execute('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;')
                point = db.json("SELECT json_build_object('time',clock_timestamp(),"
                                "'snapshot',pg_export_snapshot(),'version',version());")
                inventory = db.json("""SELECT coalesce(jsonb_agg(n.nspname||'.'||c.relname),'[]')
                    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                    WHERE n.nspname IN ('public','breeder_private') AND c.relkind='r';""")
                known = {'public.' + t for t in TABLES} | set(PRESERVED)
                if set(inventory) != known:
                    raise ValueError('Schema inventory changed: classify new/missing tables in owner.py before backup')
                objects = db.json(OBJECTS_SQL + ';')
                write_json(root / 'buckets.json', db.json(
                    "SELECT coalesce(jsonb_agg(to_jsonb(b)),'[]') FROM storage.buckets b;"))
                command = ['pg_dump', '--format=custom', '--no-owner', '--snapshot=' + point['snapshot'],
                           '--schema=public', '--schema=breeder_private', '--schema=auth',
                           '--schema=storage', '--schema=supabase_migrations',
                           '--schema=extensions',
                           '--file=' + str(root / 'database.dump')]
                run(command, env=db.env)
                # Roles carry no passwords; database payload and Storage are encrypted below.
                with (root / 'roles.sql').open('wb') as stream:
                    run(['pg_dumpall', '--roles-only', '--no-role-passwords'], env=db.env, stdout=stream)
                owners = db.json("SELECT coalesce(jsonb_agg(id),'[]') FROM public.users;")
                for owner in owners:
                    token = hashlib.sha256(owner.encode()).hexdigest()
                    write_json(root / 'owners' / (token + '.json'), export_owner(db, owner, point['time']))
                # All database rows, owner packages and object metadata use this same snapshot.
                for obj in objects:
                    token = object_key(obj['bucket_id'], obj['name'])
                    fetch_object(api_url, key, obj, root / 'objects' / token)
                    obj['backup_file'] = 'objects/' + token
                    obj['sha256'] = sha256(root / obj['backup_file'])
                db.execute('ROLLBACK;')
                # A historical Storage version must not be replaced by a newer object
                # during download. Fail this run rather than label a partial backup complete.
                current = {(o['bucket_id'], o['name']): o for o in db.json(OBJECTS_SQL + ';')}
                for obj in objects:
                    saved = {k: v for k, v in obj.items() if k not in ('backup_file', 'sha256')}
                    if current.get((obj['bucket_id'], obj['name'])) != saved:
                        raise ValueError('Storage changed during backup; retry a new snapshot')
            write_json(root / 'objects.json', objects)
            run(['git', 'archive', '--format=tar', '--output=' + str(root / 'source.tar'), 'HEAD'])
            commit = run(['git', 'rev-parse', 'HEAD'], stdout=subprocess.PIPE, text=True).stdout.strip()
            checksums = {p.relative_to(root).as_posix(): sha256(p) for p in root.rglob('*') if p.is_file()}
            write_json(root / 'manifest.json', dict(
                format='ringmaster-breeder-service', version=1, project=PROJECT,
                snapshot_at=point['time'], postgres=point['version'], commit=commit,
                owner_count=len(owners), object_count=len(objects), checksums=checksums,
                scope=['public', 'breeder_private', 'auth', 'storage', 'supabase_migrations', 'extensions'],
                external_configuration='Recreate secrets, SMTP, DNS, deployment and provider settings using the runbook.'))
            tar = Path(temp) / 'snapshot.tar.gz'
            with tarfile.open(tar, 'w:gz') as bundle:
                for path in sorted(root.rglob('*')):
                    if path.is_file():
                        bundle.add(path, arcname=path.relative_to(root).as_posix(), recursive=False)
            crypt(tar, encrypted)
            # Verify decryption, archive structure and every plaintext hash before uploading.
            verified = extract(encrypted, Path(temp) / 'verified')
        write_json(output / (name + '.complete.json'), {
            'archive': name, 'sha256': sha256(encrypted), 'bytes': encrypted.stat().st_size,
            'snapshot_at': verified['snapshot_at'], 'project': PROJECT, 'format_version': 1,
            'owner_count': verified['owner_count'], 'object_count': verified['object_count']})
        return encrypted
    except Exception:
        shutil.rmtree(output)
        raise


def upload(archive):
    endpoint = os.environ['B2_ENDPOINT']
    parsed = urlparse(endpoint)
    if parsed.scheme != 'https' or not (parsed.hostname or '').endswith('.backblazeb2.com'):
        raise ValueError('Expected a Backblaze B2 HTTPS S3 endpoint')
    bucket = os.environ['B2_BUCKET']
    base = f's3://{bucket}/{PREFIX}/{archive.name}'
    options = ['--endpoint-url', endpoint, '--only-show-errors']
    run(['aws', 's3', 'cp', str(archive), base, *options], stdout=subprocess.DEVNULL)
    # Re-download encrypted bytes: multipart ETags are not reliable SHA-256 checksums.
    with tempfile.TemporaryDirectory(prefix='breeder-readback-') as temp:
        copy = Path(temp) / 'readback.gpg'
        run(['aws', 's3', 'cp', base, str(copy), *options], stdout=subprocess.DEVNULL)
        if sha256(copy) != sha256(archive):
            raise ValueError('B2 read-back mismatch; completion marker was not published')
    marker = archive.with_name(archive.name + '.complete.json')
    run(['aws', 's3', 'cp', str(marker), base + '.complete.json', *options], stdout=subprocess.DEVNULL)
    print('Verified encrypted snapshot uploaded under ' + PREFIX + '/')
    record = json.loads(marker.read_text())
    print(json.dumps(record, sort_keys=True))
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write('\nVerified Breeder backup\n\n')
            for label in ('archive', 'snapshot_at', 'bytes', 'owner_count', 'object_count', 'sha256'):
                if label in record:
                    summary.write(f'- {label}: `{record[label]}`\n')
            summary.write('- Verification: decrypted payload checksums and B2 encrypted read-back passed.\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    backup = commands.add_parser('create')
    backup.add_argument('--output', required=True, type=Path)
    backup.add_argument('--upload', action='store_true')
    unpack = commands.add_parser('extract')
    unpack.add_argument('archive', type=Path)
    unpack.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    if args.command == 'extract':
        extract(args.archive, args.output)
        print('Decrypted backup and all checksums verified.')
    else:
        archive = create(args.output)
        if args.upload:
            upload(archive)
        else:
            print('Local encrypted snapshot verified; not uploaded.')


if __name__ == '__main__':
    main()

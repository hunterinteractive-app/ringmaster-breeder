"""Restore verified Storage bytes through the Storage API, never metadata inserts.

Individual recovery writes new immutable paths and prepares a rewritten owner
snapshot. Whole-service recovery writes original paths into an empty replacement
project. This tool never overwrites or deletes existing Storage objects.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile
from urllib.parse import quote, unquote, urlparse
from urllib.request import Request
import urllib.request
import uuid

from common import Database, sha256, write_json
from owner import make_plan
from service import PROJECT, fetch_object, verify_directory


def media_references(data):
    for table, column, bucket in [('animals', 'photo_path', 'animal_photos'),
                                  ('animal_health_records', 'attachment_url', 'health_attachments')]:
        for row in data['tables'][table]:
            path = row.get(column)
            if not path:
                continue
            if '://' in path:
                marker = '/' + bucket + '/'
                url = urlparse(path)
                if url.hostname != PROJECT + '.supabase.co' or marker not in url.path:
                    raise ValueError('Unrecognized external attachment; review manually')
                path = unquote(url.path.split(marker, 1)[1])
            animal = row['id'] if table == 'animals' else row['animal_id']
            if path.split('/')[0] != animal or any(p in ('', '.', '..') for p in path.split('/')):
                raise ValueError('File path is outside the record animal scope')
            yield row, column, bucket, path, animal


def upload_file(api_url, key, obj, source, destination):
    content = source.read_bytes()
    if hashlib.sha256(content).hexdigest() != obj['sha256']:
        raise ValueError('File checksum mismatch before upload')
    request = Request(api_url + '/storage/v1/object/' + quote(obj['bucket_id'], safe='') +
                      '/' + quote(destination, safe='/'), data=content, method='POST', headers={
                          'Authorization': 'Bearer ' + key, 'apikey': key, 'x-upsert': 'false',
                          'Content-Type': (obj.get('metadata') or {}).get('mimetype', 'application/octet-stream')})
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *_):
            return None
    with urllib.request.build_opener(NoRedirect).open(request, timeout=120) as response:
        response.read()
    with tempfile.TemporaryDirectory(prefix='breeder-media-check-') as temp:
        target = Path(temp) / 'verified'
        check = dict(obj, name=destination)
        fetch_object(api_url, key, check, target)
        if sha256(target) != obj['sha256']:
            raise ValueError('Restored Storage bytes failed verification')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('backup', type=Path, help='Verified extracted service backup')
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--owner', type=Path, help='Owner package from that backup')
    modes.add_argument('--whole-service', action='store_true')
    parser.add_argument('--output', required=True, type=Path, help='New private recovery directory')
    parser.add_argument('--confirm-project', required=True, help='Target Supabase project reference')
    args = parser.parse_args()
    os.umask(0o077)
    verify_directory(args.backup)
    api_url = os.environ['RESTORE_SUPABASE_URL'].rstrip('/')
    if api_url != f'https://{args.confirm_project}.supabase.co':
        raise ValueError('Target project does not match confirmation')
    if args.whole_service and args.confirm_project == PROJECT:
        raise ValueError('Whole-service files must be restored to a replacement project')
    objects = json.loads((args.backup / 'objects.json').read_text())
    key = os.environ['RESTORE_SERVICE_ROLE_KEY']
    args.output.mkdir(mode=0o700, parents=True, exist_ok=False)
    uploads = []
    write_json(args.output / 'uploads.json', uploads)
    if args.owner:
        # Only owner packages whose checksum is in this service backup are accepted.
        package = args.owner.resolve()
        if package.parent != (args.backup / 'owners').resolve():
            raise ValueError('Choose an owner package inside this verified backup')
        data = copy.deepcopy(json.loads(package.read_text()))
        with Database(os.environ['RESTORE_DB_URL']) as db:
            db.execute(make_plan(db, data))
        lookup = {(o['bucket_id'], o['name']): o for o in objects}
        # Validate every reference before uploading any file.
        refs = list(media_references(data))
        for _, _, bucket, path, _ in refs:
            if (bucket, path) not in lookup:
                raise ValueError('A referenced file is absent from this snapshot; review manually')
        paths = {}
        for row, column, bucket, path, animal in refs:
            entry = lookup[bucket, path]
            if (bucket, path) not in paths:
                # Keep the animal prefix required by RLS, never reuse an old path.
                destination = animal + '/recovery_' + uuid.uuid4().hex + '_' + Path(path).name
                upload_file(api_url, key, entry, args.backup / entry['backup_file'], destination)
                paths[bucket, path] = destination
                uploads.append(dict(bucket=bucket, original=path, restored=destination,
                                    sha256=entry['sha256']))
                write_json(args.output / 'uploads.json', uploads)
            row[column] = paths[bucket, path]
        data['media_prepared'] = True
        write_json(args.output / 'owner.json', data)
    else:
        # Recreate buckets with the settings recorded in buckets.json first.
        for entry in objects:
            upload_file(api_url, key, entry, args.backup / entry['backup_file'], entry['name'])
            uploads.append(dict(bucket=entry['bucket_id'], restored=entry['name'], sha256=entry['sha256']))
            write_json(args.output / 'uploads.json', uploads)
    print('Storage bytes restored and verified. Database recovery is a separate step.')


if __name__ == '__main__':
    main()

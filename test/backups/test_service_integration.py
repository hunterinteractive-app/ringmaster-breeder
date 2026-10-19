"""End-to-end snapshot/restore drill on an explicitly disposable local database."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tool' / 'backups'))
from common import Database, run
import service


@unittest.skipUnless(os.environ.get('BACKUP_TEST_DB_URL'), 'Disposable database not configured')
class ServiceIntegrationTests(unittest.TestCase):
    def test_snapshot_restore_and_owner_packages_share_one_point(self):
        # Reuse the schema's real constraints and the two-household fixture.
        from test_owner_integration import OwnerIntegrationTests, OWNER, ANIMAL
        fixture = OwnerIntegrationTests()
        fixture.setUp()
        db = fixture.db
        url = os.environ['BACKUP_TEST_DB_URL']
        destination = url.replace('/breeder_backup_test', '/breeder_backup_restore_test')
        try:
            db.execute("INSERT INTO storage.objects(bucket_id,name,metadata) "
                       "VALUES('animal_photos','synthetic/object.jpg','{\"size\":11}');")
            db.execute('COMMIT;')
            with tempfile.TemporaryDirectory(prefix='breeder-full-drill-') as temp:
                root = Path(temp)
                actual_run = service.run
                def change_after_dump(command, **kwargs):
                    result = actual_run(command, **kwargs)
                    if command[0] == 'pg_dump':
                        # A write after the snapshot must not leak into the owner package.
                        db.execute(f"ALTER TABLE public.animals DISABLE TRIGGER USER; "
                                   f"UPDATE public.animals SET name='Later change' WHERE id='{ANIMAL}'; "
                                   'ALTER TABLE public.animals ENABLE TRIGGER USER;')
                    return result
                def download(url, key, obj, path):
                    path.write_bytes(b'photo-bytes')
                with patch.dict(os.environ, {
                    'SUPABASE_DB_URL': url, 'SUPABASE_URL': f'https://{service.PROJECT}.supabase.co',
                    'SUPABASE_SERVICE_ROLE_KEY': 'synthetic-key',
                    'BACKUP_PASSPHRASE': 'synthetic-passphrase-' + 'x' * 40,
                }), patch.object(service, 'validate_source'), patch.object(service, 'fetch_object', download), patch.object(service, 'run', change_after_dump):
                    archive = service.create(root / 'encrypted')
                    service.extract(archive, root / 'verified')
                marker = json.loads(archive.with_name(archive.name + '.complete.json').read_text())
                self.assertEqual(marker['sha256'], service.sha256(archive))
                manifest = service.verify_directory(root / 'verified')
                self.assertEqual(manifest['owner_count'], 2)
                self.assertEqual(manifest['object_count'], 1)
                package = root / 'verified' / 'owners' / (hashlib.sha256(OWNER.encode()).hexdigest() + '.json')
                owner = json.loads(package.read_text())
                animal = next(a for a in owner['tables']['animals'] if a['id'] == ANIMAL)
                self.assertEqual(animal['name'], 'Original')
                objects = json.loads((root / 'verified' / 'objects.json').read_text())
                self.assertEqual((root / 'verified' / objects[0]['backup_file']).read_bytes(), b'photo-bytes')
                db.execute('CREATE DATABASE breeder_backup_restore_test;')
                with Database(destination) as restored:
                    restored.execute('DROP SCHEMA public;')
                    result = subprocess.run(['pg_restore', '--no-owner', '--no-privileges', '--exit-on-error',
                         '--dbname=breeder_backup_restore_test', str(root / 'verified' / 'database.dump')],
                        env=restored.env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                    self.assertEqual(result.returncode, 0, result.stderr.decode())
                    self.assertEqual(restored.json(f"SELECT to_json(name) FROM public.animals WHERE id='{ANIMAL}';"), 'Original')
                    self.assertEqual(restored.json('SELECT to_json(count(*)) FROM public.users;'), 2)
        finally:
            db.execute('DROP DATABASE IF EXISTS breeder_backup_restore_test WITH (FORCE);')
            db.execute('TRUNCATE auth.users CASCADE; TRUNCATE storage.objects;')
            fixture.tearDown()


if __name__ == '__main__':
    unittest.main()

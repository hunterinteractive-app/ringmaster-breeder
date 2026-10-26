import copy
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tool' / 'backups'))
from common import literal, sha256, write_json
from files import media_references
from owner import TABLES, PRESERVED
from service import PROJECT, crypt, extract, object_key, preserve_first_of_month, report_completion, upload, validate_inventory, validate_source, verify_directory


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def fixture(self):
        root = self.root / 'payload'
        root.mkdir()
        for name in ['database.dump', 'roles.sql', 'source.tar', 'objects.json']:
            (root / name).write_bytes(b'synthetic-content')
        write_json(root / 'manifest.json', dict(format='ringmaster-breeder-service', version=1,
                   checksums={p.name: sha256(p) for p in root.iterdir()}))
        return root

    def test_new_migration_tables_have_a_recovery_classification(self):
        # Catch additions during ordinary CI, before the next nightly backup.
        migrations = Path(__file__).resolve().parents[2] / 'supabase' / 'migrations'
        created = set()
        for path in migrations.glob('*.sql'):
            created.update(re.findall(
                r'^\s*create\s+table\s+(?:if\s+not\s+exists\s+)?'
                r'((?:public|breeder_private)\.[a-z_][a-z_0-9]*)\s*\(',
                path.read_text().lower(), flags=re.MULTILINE))
        self.assertTrue(created, 'Migration inventory must not be empty')
        known = {'public.' + t for t in TABLES} | set(PRESERVED)
        self.assertEqual(created - known, set(), 'Classify new tables in tool/backups/owner.py')

    def test_inventory_error_identifies_new_and_missing_tables(self):
        inventory = {'public.' + t for t in TABLES} | set(PRESERVED)
        validate_inventory(inventory)
        inventory.add('public.future_records')
        inventory.remove('public.animals')
        with self.assertRaisesRegex(ValueError,
                r'unclassified: public.future_records; missing: public.animals'):
            validate_inventory(inventory)

    def test_checksum_detects_corruption_and_missing_files(self):
        root = self.fixture()
        verify_directory(root)
        (root / 'database.dump').write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            verify_directory(root)
        (root / 'roles.sql').unlink()
        with self.assertRaisesRegex(ValueError, 'contents'):
            verify_directory(root)

    @unittest.skipUnless(shutil.which('gpg'), 'GnuPG required')
    def test_real_encryption_decryption_and_wrong_key(self):
        root = self.fixture()
        tar = self.root / 'backup.tar.gz'
        with tarfile.open(tar, 'w:gz') as bundle:
            for path in root.iterdir():
                bundle.add(path, arcname=path.name)
        archive = self.root / 'encrypted.gpg'
        with patch.dict(os.environ, BACKUP_PASSPHRASE='synthetic-' + 'x' * 40):
            crypt(tar, archive)
            self.assertNotIn(b'synthetic-content', archive.read_bytes())
            extract(archive, self.root / 'restored')
        with patch.dict(os.environ, BACKUP_PASSPHRASE='wrong-' + 'y' * 40):
            with self.assertRaises(RuntimeError):
                extract(archive, self.root / 'wrong')
        self.assertFalse((self.root / 'wrong').exists())

    @unittest.skipUnless(shutil.which('gpg'), 'GnuPG required')
    def test_rejects_path_traversal_and_symlinks(self):
        for kind in ('traversal', 'symlink', 'duplicate'):
            tar = self.root / (kind + '.tar.gz')
            with tarfile.open(tar, 'w:gz') as bundle:
                member = tarfile.TarInfo('../escape' if kind == 'traversal' else 'file')
                if kind == 'symlink':
                    member.type = tarfile.SYMTYPE
                    member.linkname = '/etc/passwd'
                bundle.addfile(member, io.BytesIO())
                if kind == 'duplicate':
                    bundle.addfile(member, io.BytesIO())
            archive = self.root / (kind + '.gpg')
            with patch.dict(os.environ, BACKUP_PASSPHRASE='synthetic-' + 'x' * 40):
                crypt(tar, archive)
                with self.assertRaisesRegex(ValueError, 'Unsafe'):
                    extract(archive, self.root / kind)
            self.assertFalse((self.root / kind).exists())

    def test_project_mismatch_and_transaction_pooler_rejected(self):
        api = f'https://{PROJECT}.supabase.co'
        validate_source(f'postgresql://postgres:synthetic@db.{PROJECT}.supabase.co:5432/postgres', api)
        validate_source(f'postgresql://postgres.{PROJECT}:synthetic@aws-0-us-east-2.pooler.supabase.com:5432/postgres', api)
        for url in [f'postgresql://postgres.{PROJECT}:synthetic@aws-0-us-east-2.pooler.supabase.com:6543/postgres',
                    f'postgresql://postgres:synthetic@db.other.supabase.co/postgres?name={PROJECT}']:
            with self.assertRaises(ValueError):
                validate_source(url, api)

    def test_owner_media_paths_cannot_escape_animal_scope(self):
        data = {'tables': {'animals': [{'id': 'one', 'photo_path': 'one/photo.jpg'}],
                           'animal_health_records': []}}
        self.assertEqual(len(list(media_references(data))), 1)
        data['tables']['animals'][0]['photo_path'] = 'other/photo.jpg'
        with self.assertRaisesRegex(ValueError, 'outside'):
            list(media_references(data))

    def test_object_keys_are_collision_safe_and_paths_are_not_filenames(self):
        self.assertNotEqual(object_key('a', 'b/c'), object_key('a/b', 'c'))
        self.assertRegex(object_key('a', '../../escape'), r'^[a-f0-9]{64}$')
        self.assertEqual(literal("a'\\b"), "E'a''\\\\b'")

    def test_b2_completion_marker_is_only_uploaded_after_verified_readback(self):
        archive = self.root / 'snapshot.gpg'
        archive.write_bytes(b'encrypted-synthetic')
        archive.with_name(archive.name + '.complete.json').write_text('{}')
        summary = self.root / 'summary.md'
        summary.write_text('')
        for corrupt in (False, True):
            published = []
            def aws(command, **kwargs):
                source, destination = command[3], command[4]
                if source.startswith('s3://'):
                    Path(destination).write_bytes(b'wrong' if corrupt else archive.read_bytes())
                else:
                    published.append(destination)
            with patch.dict(os.environ, B2_ENDPOINT='https://s3.us-west-004.backblazeb2.com', B2_BUCKET='synthetic', GITHUB_STEP_SUMMARY=str(summary)), patch('service.run', aws):
                if corrupt:
                    with self.assertRaisesRegex(ValueError, 'read-back'):
                        upload(archive)
                else:
                    with redirect_stdout(io.StringIO()):
                        upload(archive)
            self.assertEqual(len(published), 1 if corrupt else 2)
            self.assertTrue(all('/ringmaster-breeder/service/' in p for p in published))
            self.assertEqual(summary.read_text(), '')

    def test_completion_report_preserves_verification_metadata(self):
        archive = self.root / 'snapshot.gpg'
        marker = archive.with_name(archive.name + '.complete.json')
        write_json(marker, {'archive':archive.name,'snapshot_at':'2026-10-19T05:57:10Z',
                            'bytes':100,'owner_count':2,'object_count':3,'sha256':'abc123'})
        summary = self.root / 'summary.md'
        with patch.dict(os.environ, GITHUB_STEP_SUMMARY=str(summary)), redirect_stdout(io.StringIO()):
            report_completion(archive)
        self.assertIn('snapshot.gpg', summary.read_text())
        self.assertIn('abc123', summary.read_text())
        self.assertIn('object_count: `3`', summary.read_text())

    def monthly_fixture(self, point):
        archive = self.root / 'daily.gpg'
        archive.write_bytes(b'encrypted-first-snapshot')
        write_json(archive.with_name(archive.name + '.complete.json'), {
            'archive':archive.name,'snapshot_at':point,'project':PROJECT,
            'bytes':archive.stat().st_size,'sha256':sha256(archive),'format_version':1})
        return archive

    def test_monthly_date_uses_eastern_calendar(self):
        # UTC has reached November, but Indianapolis is still on October 31.
        archive = self.monthly_fixture('2026-11-01T01:00:00+00:00')
        with patch('service.run') as aws, patch('service.subprocess.run') as head:
            self.assertFalse(preserve_first_of_month(archive))
            aws.assert_not_called()
            head.assert_not_called()

    def test_first_day_copy_is_verified_once_and_preserved_on_retry(self):
        archive = self.monthly_fixture('2026-11-01T06:47:00+00:00')
        remote = {}
        writes = []
        def aws(command, **kwargs):
            source,destination = command[3],command[4]
            if source.startswith('s3://'):
                Path(destination).write_bytes(remote[source])
            else:
                remote[destination]=Path(source).read_bytes()
                writes.append(destination)
        def head(command, **kwargs):
            marker='s3://synthetic/'+command[command.index('--key')+1]
            return SimpleNamespace(returncode=0 if marker in remote else 1,
                                   stderr=b'' if marker in remote else b'An error occurred (404)')
        with patch.dict(os.environ, B2_ENDPOINT='https://s3.us-west-004.backblazeb2.com', B2_BUCKET='synthetic', GITHUB_STEP_SUMMARY=''), patch('service.run',aws), patch('service.subprocess.run',head), redirect_stdout(io.StringIO()):
            self.assertTrue(preserve_first_of_month(archive))
            self.assertEqual(len(writes),2)
            self.assertTrue(all('/ringmaster-breeder/monthly/2026-11/' in w for w in writes))
            stored=dict(remote)
            archive.write_bytes(b'later-first-day-snapshot')
            self.assertFalse(preserve_first_of_month(archive))
            self.assertEqual(remote,stored)
            self.assertEqual(len(writes),2)
            # Corruption of a retained monthly copy is surfaced, never replaced.
            object_url=next(k for k in remote if not k.endswith('.json'))
            remote[object_url]=b'corrupt'
            with self.assertRaisesRegex(ValueError,'failed verification'):
                preserve_first_of_month(archive)

    def test_monthly_access_denial_does_not_mean_missing_backup(self):
        archive=self.monthly_fixture('2026-11-01T06:47:00+00:00')
        denied=SimpleNamespace(returncode=1,stderr=b'An error occurred (403)')
        with patch.dict(os.environ,B2_BUCKET='synthetic',B2_ENDPOINT='https://s3.us-west-004.backblazeb2.com'), patch('service.subprocess.run',return_value=denied), patch('service.run') as aws:
            with self.assertRaisesRegex(RuntimeError,'refusing to overwrite'):
                preserve_first_of_month(archive)
            aws.assert_not_called()


if __name__ == '__main__':
    unittest.main()

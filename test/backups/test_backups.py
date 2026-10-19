import copy
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tool' / 'backups'))
from common import literal, sha256, write_json
from files import media_references
from service import PROJECT, crypt, extract, object_key, upload, validate_source, verify_directory


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
        for corrupt in (False, True):
            published = []
            def aws(command, **kwargs):
                source, destination = command[3], command[4]
                if source.startswith('s3://'):
                    Path(destination).write_bytes(b'wrong' if corrupt else archive.read_bytes())
                else:
                    published.append(destination)
            with patch.dict(os.environ, B2_ENDPOINT='https://s3.us-west-004.backblazeb2.com', B2_BUCKET='synthetic'), patch('service.run', aws):
                if corrupt:
                    with self.assertRaisesRegex(ValueError, 'read-back'):
                        upload(archive)
                else:
                    with redirect_stdout(io.StringIO()):
                        upload(archive)
            self.assertEqual(len(published), 1 if corrupt else 2)
            self.assertTrue(all('/ringmaster-breeder/service/' in p for p in published))


if __name__ == '__main__':
    unittest.main()

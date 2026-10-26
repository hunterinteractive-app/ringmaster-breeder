"""Run only against a disposable Breeder schema clone, never production.

BACKUP_TEST_DB_URL must use loopback and the database breeder_backup_test.
All fixture writes are rolled back at the end of each test.
"""
import copy
import os
from pathlib import Path
import sys
import unittest
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tool' / 'backups'))
from common import Database
from owner import TABLES, export_owner, make_plan

OWNER = 'backup-test-owner'
AUTH = '12345678-1234-4234-8234-123456789001'
OTHER_AUTH = '12345678-1234-4234-8234-123456789002'
RING = '12345678-1234-4234-8234-123456789011'
OTHER_RING = '12345678-1234-4234-8234-123456789012'
ANIMAL = '12345678-1234-4234-8234-123456789021'
PARENT = '12345678-1234-4234-8234-123456789022'
OTHER_ANIMAL = '12345678-1234-4234-8234-123456789023'
NEW_ANIMAL = '12345678-1234-4234-8234-123456789024'
DAM = '12345678-1234-4234-8234-123456789025'
WEIGHT = '12345678-1234-4234-8234-123456789031'
SALE = '12345678-1234-4234-8234-123456789041'
CONTACT = '12345678-1234-4234-8234-123456789051'
OTHER_CONTACT = '12345678-1234-4234-8234-123456789052'
BREEDING = '12345678-1234-4234-8234-123456789061'


@unittest.skipUnless(os.environ.get('BACKUP_TEST_DB_URL'), 'Disposable database not configured')
class OwnerIntegrationTests(unittest.TestCase):
    def setUp(self):
        url = os.environ['BACKUP_TEST_DB_URL']
        parsed = urlparse(url)
        if parsed.hostname not in ('127.0.0.1', 'localhost') or parsed.path != '/breeder_backup_test':
            raise ValueError('Refusing a non-disposable database')
        self.db = Database(url)
        self.db.execute('BEGIN;')
        # Populate synthetic history without triggering live workflow actions.
        self.db.execute("""DO $$ DECLARE r record; BEGIN
          FOR r IN SELECT c.oid::regclass t FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
          WHERE n.nspname='public' AND c.relkind='r' LOOP
            EXECUTE format('ALTER TABLE %s DISABLE TRIGGER USER',r.t); END LOOP; END $$;""")
        self.db.execute(f"""
          INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
            ('{AUTH}','backup@example.test',now()),('{OTHER_AUTH}','other-backup@example.test',now());
          INSERT INTO public.users(id,username,email,auth_user_id) VALUES
            ('{OWNER}','backup_fixture','backup@example.test','{AUTH}'),
            ('backup-test-other','backup_other','other-backup@example.test','{OTHER_AUTH}');
          INSERT INTO public.farms(id,name,owner_id) VALUES
            ('{RING}','Recovery herd','{OWNER}'),('{OTHER_RING}','Other herd','backup-test-other');
          INSERT INTO public.animals(id,ring_id,name,species,sex) VALUES
            ('{ANIMAL}','{RING}','Original','rabbit','Buck'),
            ('{PARENT}','{RING}','Father','rabbit','Buck'),
            ('{DAM}','{RING}','Mother','rabbit','Doe'),
            ('{OTHER_ANIMAL}','{OTHER_RING}','Untouched','rabbit','Buck');
          UPDATE public.animals SET sire_id='{PARENT}' WHERE id='{ANIMAL}';
          INSERT INTO public.animal_weights(id,animal_id,weight) VALUES('{WEIGHT}','{ANIMAL}',4);
          INSERT INTO public.animal_sales(id,animal_id,ring_id,animal_name,asking_cents)
            VALUES('{SALE}','{ANIMAL}','{RING}','Original',10000);
          INSERT INTO public.animal_sale_payments(sale_id,kind,amount_cents,created_by)
            VALUES('{SALE}','deposit',2000,'{AUTH}');
          INSERT INTO public.animal_sale_history(sale_id,event,details,created_by)
            VALUES('{SALE}','fixture','{{}}','{AUTH}');
          INSERT INTO public.herd_contacts(id,ring_id,source,source_id,name) VALUES
            ('{CONTACT}','{RING}','fixture','one','Original contact'),
            ('{OTHER_CONTACT}','{OTHER_RING}','fixture','other','Other contact');
          INSERT INTO public.animal_management(animal_id,cage,buyer_contact_id)
            VALUES('{ANIMAL}','A1','{CONTACT}');
          UPDATE public.animal_sales SET buyer_contact_id='{CONTACT}' WHERE id='{SALE}';
          INSERT INTO public.wool_settings(ring_id) VALUES('{RING}');
          INSERT INTO public.animal_feed_weights(animal_id,recorded_date,feed_weight,native_weight_id)
            VALUES('{ANIMAL}','2026-10-18',2,'{WEIGHT}');
          INSERT INTO public.animal_wool_records(animal_id,recorded_date,fleece_grams,native_weight_id)
            VALUES('{ANIMAL}','2026-10-18',100,'{WEIGHT}');
          INSERT INTO public.rabbit_register_sources(ring_id,source) VALUES('{RING}','fixture');
          INSERT INTO public.rabbit_register_files(ring_id,source,filename,original_file_base64)
            VALUES('{RING}','fixture','synthetic.rr','c3ludGhldGlj');
          INSERT INTO public.breeding_records(id,dam_id,import_ring_id,import_source,import_source_id,import_record)
            VALUES('{BREEDING}','{DAM}','{RING}','rabbit_register','litter-one','{{}}');
          INSERT INTO public.breeding_tracking(breeding_id,import_record,notes)
            VALUES('{BREEDING}','{{}}','Unknown sire litter');
          INSERT INTO public.litter_weights(breeding_id,recorded_date,weight)
            VALUES('{BREEDING}','2026-10-18',5);
        """)
        self.db.execute("""DO $$ DECLARE r record; BEGIN
          FOR r IN SELECT c.oid::regclass t FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
          WHERE n.nspname='public' AND c.relkind='r' LOOP
            EXECUTE format('ALTER TABLE %s ENABLE TRIGGER USER',r.t); END LOOP; END $$;""")
        self.snapshot = export_owner(self.db, OWNER, '2026-10-18T00:00:00Z')

    def tearDown(self):
        self.db.close()  # disconnect rolls back fixture and successful restore plans

    def apply_in_fixture(self, data):
        # Keep the outer fixture transaction; do not let a plan commit it.
        plan = make_plan(self.db, data, commit=True)
        self.db.execute(plan.removeprefix('BEGIN;\n').removesuffix('COMMIT;\n'))

    def test_recovery_preserves_other_family_newer_rows_and_sales_history(self):
        self.db.execute(f"""ALTER TABLE public.animals DISABLE TRIGGER USER;
          UPDATE public.animals SET name='Changed',revision=99 WHERE id='{ANIMAL}';
          INSERT INTO public.animals(id,ring_id,name,species,sex)
            VALUES('{NEW_ANIMAL}','{RING}','Newer record','rabbit','Buck');
          ALTER TABLE public.animals ENABLE TRIGGER USER;
          DELETE FROM public.animal_weights WHERE id='{WEIGHT}';""")
        self.apply_in_fixture(self.snapshot)
        result = self.db.json(f"SELECT json_build_object('name',name,'sire',sire_id,'revision',revision) FROM public.animals WHERE id='{ANIMAL}';")
        self.assertEqual(result['name'], 'Original')
        self.assertEqual(result['sire'], PARENT)
        self.assertGreater(result['revision'], 99)
        self.assertEqual(self.db.json(f"SELECT to_json(name) FROM public.animals WHERE id='{OTHER_ANIMAL}';"), 'Untouched')
        self.assertEqual(self.db.json(f"SELECT to_json(name) FROM public.animals WHERE id='{NEW_ANIMAL}';"), 'Newer record')
        self.assertEqual(self.db.json(f"SELECT to_json(weight) FROM public.animal_weights WHERE id='{WEIGHT}';"), 4)
        self.assertEqual(self.db.json(f"SELECT to_json(count(*)) FROM public.animal_sale_history WHERE sale_id='{SALE}';"), 1)
        self.assertEqual(self.db.json(f"SELECT to_json(count(*)) FROM public.animal_sale_payments WHERE sale_id='{SALE}';"), 1)
        self.assertGreater(self.db.json(f"SELECT to_json(version) FROM public.animal_sales WHERE id='{SALE}';"),
                           self.snapshot['tables']['animal_sales'][0]['version'])
        self.assertEqual(self.db.json("SELECT to_json(count(*)) FROM pg_trigger WHERE NOT tgisinternal AND tgenabled='D';"), 0)
        # The same recovery is idempotent for business records and audit history.
        self.db.execute('DROP TABLE ' + ','.join('pg_temp.recover_' + t for t in TABLES) + ';')
        self.apply_in_fixture(self.snapshot)
        self.assertEqual(self.db.json(f"SELECT to_json(count(*)) FROM public.animal_sale_history WHERE sale_id='{SALE}';"), 1)

    def test_id_now_owned_by_another_family_is_rejected(self):
        self.db.execute(f"ALTER TABLE public.animals DISABLE TRIGGER USER; UPDATE public.animals SET ring_id='{OTHER_RING}' WHERE id='{ANIMAL}'; ALTER TABLE public.animals ENABLE TRIGGER USER;")
        with self.assertRaises(RuntimeError):
            self.apply_in_fixture(self.snapshot)

    def test_cross_family_parent_is_rejected(self):
        self.snapshot['tables']['animals'][0]['sire_id'] = OTHER_ANIMAL
        with self.assertRaises(RuntimeError):
            self.apply_in_fixture(self.snapshot)

    def test_new_herd_records_and_unknown_sire_litter_round_trip(self):
        for table in ('herd_contacts', 'animal_management', 'wool_settings',
                      'animal_feed_weights', 'animal_wool_records', 'rabbit_register_files',
                      'breeding_records', 'breeding_tracking', 'litter_weights'):
            self.assertEqual(len(self.snapshot['tables'][table]), 1, table)
        self.assertIsNone(self.snapshot['tables']['breeding_records'][0]['sire_id'])
        self.db.execute(f"""UPDATE public.animal_management SET cage='Changed' WHERE animal_id='{ANIMAL}';
          DELETE FROM public.litter_weights WHERE breeding_id='{BREEDING}';
          DELETE FROM public.rabbit_register_files WHERE ring_id='{RING}';
          UPDATE public.herd_contacts SET name='Changed' WHERE id='{CONTACT}';""")
        self.apply_in_fixture(self.snapshot)
        self.assertEqual(self.db.json(f"SELECT to_json(cage) FROM public.animal_management WHERE animal_id='{ANIMAL}';"), 'A1')
        self.assertEqual(self.db.json(f"SELECT to_json(weight) FROM public.litter_weights WHERE breeding_id='{BREEDING}';"), 5)
        self.assertEqual(self.db.json(f"SELECT to_json(notes) FROM public.breeding_tracking WHERE breeding_id='{BREEDING}';"), 'Unknown sire litter')
        self.assertEqual(self.db.json(f"SELECT to_json(name) FROM public.herd_contacts WHERE id='{CONTACT}';"), 'Original contact')
        self.assertEqual(self.db.json(f"SELECT to_json(name) FROM public.herd_contacts WHERE id='{OTHER_CONTACT}';"), 'Other contact')
        saved = self.snapshot['tables']['rabbit_register_files'][0]
        restored = self.db.json(f"SELECT to_jsonb(t) FROM public.rabbit_register_files t WHERE ring_id='{RING}';")
        self.assertEqual(restored, saved)

    def test_cross_family_management_contact_is_rejected(self):
        self.snapshot['tables']['animal_management'][0]['buyer_contact_id'] = OTHER_CONTACT
        with self.assertRaises(RuntimeError):
            self.apply_in_fixture(self.snapshot)

    def test_schema_drift_is_rejected_before_writes(self):
        self.snapshot['schema']['animals'].append({'name': 'future_field', 'type': 'text'})
        with self.assertRaisesRegex(ValueError, 'Schema differs'):
            make_plan(self.db, self.snapshot)

    def test_invalid_weight_rolls_back_everything(self):
        self.snapshot['tables']['animal_weights'][0]['weight'] = -1
        with self.assertRaises(RuntimeError):
            self.apply_in_fixture(self.snapshot)

    def test_inactive_account_cannot_be_revived(self):
        self.db.execute(f"UPDATE public.users SET is_active=false WHERE id='{OWNER}';")
        with self.assertRaises(RuntimeError):
            self.apply_in_fixture(self.snapshot)


if __name__ == '__main__':
    unittest.main()

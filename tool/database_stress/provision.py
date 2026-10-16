#!/usr/bin/env python3
"""Restore a schema-only snapshot into a fresh, explicitly named test container."""
import subprocess
from pathlib import Path
CONTAINER='ringmaster-breeder-scale-test-20261016'
base=['docker','exec','-i','--env','PGPASSWORD=local-synthetic-test-only',CONTAINER,'psql','-h','127.0.0.1','-X','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1','-q']
def sql(text):
 r=subprocess.run(base,input=text,text=True,capture_output=True)
 if r.returncode:raise RuntimeError(r.stderr[-1800:])
# Only a fresh disposable database is accepted; never clear an existing schema.
r=subprocess.run(base+['-Atc',"select count(*) from pg_tables where schemaname in ('public','breeder_private');"],text=True,capture_output=True,check=True)
assert r.stdout.strip()=='0','Provisioning requires a fresh, empty application schema'
sql('''create table storage.buckets(id text primary key,name text not null,public boolean default false,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),name text,metadata jsonb,owner_id text,owner uuid);
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated;
grant select,insert,delete on storage.objects to authenticated;
''')
sql(Path('tool/database_stress/support.sql').read_text())
sql(Path('/private/tmp/ringmaster-breeder-scale-schema.sql').read_text())
for path in sorted(Path('supabase/migrations').glob('*_animal_edit_revision.sql')):sql(path.read_text())
policy="insert into storage.buckets(id,name) values('health_attachments','health_attachments'),('animal_photos','animal_photos');"
for bucket,tag in [('health_attachments','attachment'),('animal_photos','photo')]:
 for cmd,suffix in [('select','read'),('insert','insert'),('delete','delete')]:
  condition=f"bucket_id='{bucket}' and breeder_private.attachment_access(name)"
  policy+=f"create policy family_{tag}_{suffix} on storage.objects for {cmd} to authenticated "+(f"with check ({condition});" if cmd=='insert' else f"using ({condition});")
sql(policy)
sql(Path('tool/database_stress/seed.sql').read_text())
sql("alter role authenticator password 'local-synthetic-test-only';")
print('Restored application schema, migration, and 500000 synthetic history records.')

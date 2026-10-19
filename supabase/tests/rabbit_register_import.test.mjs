// Rabbit Register isolated PostgreSQL fixture; never connects to the live database.
// Install @electric-sql/pglite@0.3.14 into a temporary directory and set
// PGLITE_MODULE to its dist/index.js to run this test.
const { PGlite } = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const repo=new URL('../../', import.meta.url).pathname.replace(/\/$/, '');
const db=new PGlite();
await db.exec(`
create role anon; create role authenticated; create role service_role;
create schema auth; create schema breeder_private;
create table auth.users(id uuid primary key);
insert into auth.users values('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222');
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table public.users(id text primary key,auth_user_id uuid,is_active boolean default true);
create table public.farms(id uuid primary key,name text,owner_id text references public.users,is_demo boolean default false);
create table public.animals(id uuid primary key default gen_random_uuid(),ring_id uuid references public.farms,name text,tattoo text,species text,breed text,variety text,sex text,dob date,status text default 'active',notes text,registration_number text,grand_champion_number text,legs integer,pedigree_only boolean default false,sire_id uuid references public.animals,dam_id uuid references public.animals,constraint animals_status_check check(status in ('active','sold','retired','deceased')),check(sex in ('Buck','Doe','Boar','Sow')));
create unique index animals_herd_tattoo_unique on public.animals(ring_id,lower(btrim(tattoo))) where nullif(btrim(tattoo),'') is not null;
create table public.animal_weights(id uuid primary key default gen_random_uuid(),animal_id uuid references public.animals,weight numeric check(weight>0 and weight<1000),recorded_at timestamptz default now());
create function breeder_private.owns(p_owner text) returns boolean language sql security definer set search_path='' as $$select exists(select 1 from public.users where id=p_owner and auth_user_id=auth.uid() and is_active)$$;
create function public.catalog_key(value text) returns text language sql immutable as $$select lower(trim(value))$$;
grant usage on schema public,auth,breeder_private to authenticated;
grant select,update on public.farms to authenticated;
grant select,insert,update on public.animals,public.animal_weights to authenticated;
alter table public.farms enable row level security;
alter table public.animals enable row level security;
create policy farm_access on public.farms for all to authenticated using(breeder_private.owns(owner_id)) with check(breeder_private.owns(owner_id));
create policy animal_access on public.animals for all to authenticated using(exists(select 1 from public.farms f where f.id=ring_id)) with check(exists(select 1 from public.farms f where f.id=ring_id));
insert into public.users values('owner','11111111-1111-4111-8111-111111111111',true),('other','22222222-2222-4222-8222-222222222222',true);
insert into public.farms values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Fixture herd','owner',false),('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Other herd','other',false);
`);
const trigger=readFileSync(repo+'/supabase/migrations/20261010011243_species_sex_names.sql','utf8');
await db.exec(trigger.slice(trigger.indexOf('create or replace function breeder_private.validate_animal()'),trigger.indexOf('create or replace function breeder_private.apply_cross_app_import')));
await db.exec('create trigger breeder_validate_animal before insert or update on public.animals for each row execute function breeder_private.validate_animal();');
await db.exec("alter table public.animals add column global_pedigree_identity text; alter table public.animals drop constraint animals_status_check; alter table public.animals add constraint animals_status_check check(status in ('active','archived','sold','deceased','retired'));");
const historyMigration=readFileSync(repo+'/supabase/migrations/20261013194706_global_pedigree_history.sql','utf8');
// Use the production historical-weight guard too, with an empty GP history table.
await db.exec("create table public.global_pedigree_history(animal_id uuid,kind text,record jsonb); grant select on public.global_pedigree_history to authenticated;");
await db.exec(historyMigration.slice(historyMigration.indexOf('create or replace function breeder_private.validate_weight()')));
await db.exec('create trigger breeder_validate_weight before insert on public.animal_weights for each row execute function breeder_private.validate_weight();');
await db.exec(readFileSync(repo+'/supabase/migrations/20261018215207_rabbit_register_import.sql','utf8'));
await db.exec("set role authenticated; select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false)");
const ring='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
async function run(animals,records=[],commit=false,source='fixture',extra={},herd=ring){
 return (await db.query('select public.import_rabbit_register($1,$2,$3::jsonb,$4) as result',[herd,source,JSON.stringify({animals,records,warnings_acknowledged:true,...extra}),commit])).rows[0].result;
}
function animal(id,name,sex='Buck',extra={}) {return {source_id:id,name,sex,status:'active',raw:{CID:id,Name:name,Breed:'Dutch'},...extra};}
const animals=[animal('1','Root','Buck',{tattoo:'ROOT',sire_id:'2',dam_id:'3',dob:'2014-01-02'}),animal('2','Father','Buck',{status:'deceased'}),animal('3','Mother','Doe',{status:'archived'})];
const records=[{kind:'weight',source_id:'1',animal_source_id:'2',weight:4,recorded_date:'2014-02-07',raw:{ID:'1',CRITTERKEY:'2',CRITTERWT:'1814.368'}},{kind:'litter',source_id:'1',animal_source_id:'3',sire_source_id:'2',raw:{ID:'1',DATEWEANED:'0100-01-01'}},{kind:'show',source_id:'1',animal_source_id:'1',raw:{ID:'1',WINS:'BOB'}},{kind:'contact',source_id:'1',raw:{ID:'1',FirstName:'Test'}}];
let result=await run(animals,records);
assert.equal(result.status,'preview');assert.equal(result.animals_added,3);assert.deepEqual(result.issues,[]);
assert.equal((await db.query('select count(*)::int n from public.rabbit_register_sources')).rows[0].n,0);
assert.equal((await db.query('select count(*)::int n from public.animals')).rows[0].n,0);
result=await run(animals,records,true);assert.equal(result.status,'imported');assert.equal(result.animals_added,3);assert.equal(result.history_added,4);
assert.deepEqual((await db.query("select s.name sire,d.name dam from public.animals a join public.animals s on s.id=a.sire_id join public.animals d on d.id=a.dam_id where a.name='Root'")).rows,[{sire:'Father',dam:'Mother'}]);
assert.deepEqual((await db.query("select weight::text w,recorded_at::date::text d from public.animal_weights")).rows,[{w:'4',d:'2014-02-07'}]);
assert.equal((await db.query("select status from public.animals where name='Father'")).rows[0].status,'deceased');
assert.equal((await db.query("select record->'raw'->>'DATEWEANED' d from public.rabbit_register_records where kind='litter'")).rows[0].d,'0100-01-01');
result=await run(animals,records,true);assert.equal(result.animals_added,0);assert.equal(result.animals_existing,3);assert.equal(result.history_added,0);
assert.equal((await db.query('select count(*)::int n from public.animal_weights')).rows[0].n,1);
// Source labels are normalized, not derived from the export filename.
assert.equal((await run(animals,records,true,' FIXTURE ')).animals_added,0);
result=await run([animal('1','Wrong breeder')],[],true);assert(result.issues.some(x=>x.includes('changed identity')));
await assert.rejects(run(animals,[],true,'x',{},'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),/Select a herd you own/);
await db.exec("reset role; insert into public.farms values('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Demo','owner',true);set role authenticated;");
await assert.rejects(run(animals,[],true,'x',{},'cccccccc-cccc-4ccc-8ccc-cccccccccccc'),/Select a herd you own/);
await assert.rejects(run([animals[0],animals[0]]),/Duplicate source animal ID/);
result=await run([animal('10','Missing','Buck',{sire_id:'99'})],[],true,'missing',{warnings_acknowledged:false});assert.equal(result.status,'preview');assert(result.issues.some(x=>x.includes('Acknowledge')));
result=await run([animal('10','Missing','Buck',{sire_id:'99'})],[],true,'missing');assert.equal(result.status,'imported');
assert.equal((await db.query("select sire_id from public.animals where name='Missing'")).rows[0].sire_id,null);
result=await run([animal('11','No sex',null)],[],true);assert.equal(result.status,'preview');assert(result.issues.some(x=>x.includes('Buck or Doe')));
result=await run([animal('12','Cycle A','Buck',{sire_id:'13'}),animal('13','Cycle B','Buck',{sire_id:'12'})],[],true);assert(result.issues.some(x=>x.includes('cycle')));
result=await run([animal('14','Wrong parent','Buck',{sire_id:'15'}),animal('15','Doe parent','Doe')],[],true);assert(result.issues.some(x=>x.includes('wrong sex')));
for(const date of ['2999-01-01','not-a-date','2014-02-30']){
 result=await run([animal('16','Bad date','Buck',{dob:date})],[],true);assert(result.issues.some(x=>x.includes('birth date')));
}
// Reused tattoos are preserved as distinct source identities.
result=await run([animal('20','One','Buck',{tattoo:'SAME'}),animal('21','Two','Doe',{tattoo:'SAME'})],[],true);assert.equal(result.animals_added,2);
await db.exec("insert into public.animals(ring_id,name,tattoo,species,sex,breed,status) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Manual','MANUAL','rabbit','Buck','Dutch','active');");
const manual=(await db.query("select id from public.animals where name='Manual'")).rows[0].id;
const candidate=animal('22','Manual','Buck',{tattoo:'MANUAL',breed:'Dutch'});
result=await run([candidate],[],true);assert(result.issues.some(x=>x.includes('Review existing matches')));assert.equal(result.rows[0].candidates[0].id,manual);
result=await run([{...candidate,existing_id:manual}],[],true);assert.equal(result.animals_existing,1);assert.equal(result.animals_added,0);
// Matching never changes an existing animal's parents, status, notes, or weights.
result=await run([{...candidate,existing_id:manual,status:'deceased',notes:'Overwrite?'}],[{kind:'weight',source_id:'22',animal_source_id:'22',weight:9,recorded_date:'2014-01-01',raw:{ID:'22'}}],true);
assert.deepEqual((await db.query("select status,notes from public.animals where id=$1",[manual])).rows,[{status:'active',notes:null}]);
assert.equal((await db.query('select count(*)::int n from public.animal_weights where animal_id=$1',[manual])).rows[0].n,0);
result=await run([animal('23','Manual','Buck',{tattoo:'MANUAL',breed:'Dutch',keep_separate:true})],[],true);assert.equal(result.animals_added,1);
result=await run([animal('24','Fake choice','Buck',{existing_id:manual})],[],true);assert(result.issues.some(x=>x.includes('invalid existing-animal choice')));
const bad=animal('25','Rollback');
result=await run([bad],[{kind:'weight',source_id:'25',animal_source_id:'25',weight:0,recorded_date:'2014-01-01',raw:{ID:'25'}}],true);assert.equal(result.status,'preview');
assert.equal((await db.query("select count(*)::int n from public.animals where name='Rollback'")).rows[0].n,0);
// A late storage failure rolls back animals, provenance, weights and source.
await db.exec("reset role; alter table public.rabbit_register_records add constraint fixture_failure check(source_id<>'999'); set role authenticated;");
await assert.rejects(run([animal('26','Atomic rollback')],[{kind:'contact',source_id:'999',raw:{ID:'999'}}],true,'atomic'),/fixture_failure/);
assert.equal((await db.query("select count(*)::int n from public.animals where name='Atomic rollback'")).rows[0].n,0);
assert.equal((await db.query("select count(*)::int n from public.rabbit_register_sources where source='atomic'")).rows[0].n,0);
// Neither provenance nor contact data is visible to another owner.
await db.exec("select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false)");
for(const table of ['rabbit_register_sources','rabbit_register_animals','rabbit_register_records']) assert.equal((await db.query(`select count(*)::int n from public.${table}`)).rows[0].n,0);
await assert.rejects(run(animals),/Select a herd you own/);
await assert.rejects(db.query('insert into public.rabbit_register_sources(ring_id,source) values($1,$2)',[ring,'intruder']),/row-level security/);
await db.exec("reset role;set role anon;");
await assert.rejects(db.query('select public.import_rabbit_register($1,$2,$3::jsonb,false)',[ring,'x',JSON.stringify({animals,records:[]})]),/permission denied/);
await db.exec("reset role;set role authenticated;select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false)");
// Optional integration payload produced locally from the user's real export.
if(process.env.RABBIT_REGISTER_PAYLOAD){
 const payload=JSON.parse(readFileSync(process.env.RABBIT_REGISTER_PAYLOAD,'utf8'));
 // Test-only corrections let the complete sample exercise the transaction.
 const corrected=payload.animals.map(a=>{
  const node={...a,sex:a.sex??'Buck'};
  for(const link of payload.review_parent_links??[]) if(link.source_id===a.source_id) node[link.side]=null;
  return node;
 });
 result=await run(corrected,payload.records,false,'sample',{...payload,animals:corrected});
 assert.deepEqual(result.issues,[]);assert.equal(result.animals_added,592);
 result=await run(corrected,payload.records,true,'sample',{...payload,animals:corrected});
 assert.equal(result.status,'imported');assert.equal(result.animals_added,592);assert.equal(result.history_added,792);
 assert.equal((await run(corrected,payload.records,true,'sample',{...payload,animals:corrected})).animals_added,0);
 console.log('Real export: 592 rabbits, 792 history records, parent links and retry verified in isolated database.');
}
await db.close();
console.log('Rabbit Register PostgreSQL import/access/rollback tests passed.');

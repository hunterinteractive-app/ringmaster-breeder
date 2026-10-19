// Kintraks isolated PostgreSQL fixture; never connects to the live database.
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
await db.exec('reset role;');
await db.exec(readFileSync(repo+'/supabase/migrations/20261019015628_kintraks_import.sql','utf8'));
await db.exec("set role authenticated;select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false)");
await db.exec('reset role;');
assert.equal((await db.query("select bool_and(relrowsecurity) enabled from pg_class where oid in ('public.kintraks_sources'::regclass,'public.kintraks_animals'::regclass)")).rows[0].enabled,true);
assert.deepEqual((await db.query("select prosecdef,has_function_privilege('anon','public.import_kintraks(uuid,text,jsonb,boolean)','execute') anon_execute from pg_proc where oid='public.import_kintraks(uuid,text,jsonb,boolean)'::regprocedure")).rows,[{prosecdef:false,anon_execute:false}]);
await db.exec('set role authenticated;');
const ring='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
async function run(animals,commit=false,source='fixture',extra={},herd=ring){
 return (await db.query('select public.import_kintraks($1,$2,$3::jsonb,$4) as result',[herd,source,JSON.stringify({animals,warnings_acknowledged:true,...extra}),commit])).rows[0].result;
}
function animal(id,name,sex='Buck',extra={}) {return {source_id:id,name,sex,status:'archived',pedigree_only:true,raw:{Id:id,Name:name,Breed:'Dutch',Deceased:'False',Sold:'False',Weight:'',_csv_headers:['Id','Name','Breeder','Breeder']},...extra};}
const animals=[animal('1','Root','Buck',{tattoo:'ROOT',sire_id:'2',dam_id:'3',dob:'2014-01-02',status:'active',pedigree_only:false,profile_weight:3.625,raw:{Id:'1',Name:'Root',Weight:'3.10','Breeder [1]':'True','Breeder [2]':'Example',Vaccine:'Batch1',_csv_headers:['Id','Name','Breeder','Breeder']}}),animal('2','Father'),animal('3','Mother','Doe',{status:'deceased',pedigree_only:false,raw:{Id:'3',Name:'Mother',Deceased:'True',_csv_headers:[]}})];
let result=await run(animals);assert.equal(result.status,'preview');assert.deepEqual(result.issues,[]);
assert.equal((await db.query('select count(*)::int n from public.kintraks_sources')).rows[0].n,0);
result=await run(animals,true);assert.equal(result.animals_added,3);assert.equal(result.history_added,3);
const saved=(await db.query("select a.name,a.status,a.pedigree_only,s.name sire,d.name dam from public.animals a left join public.animals s on a.sire_id=s.id left join public.animals d on a.dam_id=d.id where a.name='Root'")).rows[0];
assert.deepEqual(saved,{name:'Root',status:'active',pedigree_only:false,sire:'Father',dam:'Mother'});
assert.equal((await db.query("select pedigree_only from public.animals where name='Father'")).rows[0].pedigree_only,true);
const snapshot=(await db.query("select raw,profile_weight from public.kintraks_animals where source_id='1'")).rows[0];
assert.equal(Number(snapshot.profile_weight),3.625);assert.equal(snapshot.raw.Weight,'3.10');assert.equal(snapshot.raw['Breeder [2]'],'Example');assert.equal(snapshot.raw.Vaccine,'Batch1');
assert.equal((await db.query('select count(*)::int n from public.animal_weights')).rows[0].n,0);
result=await run(animals,true,' FIXTURE ');assert.equal(result.animals_added,0);assert.equal(result.animals_existing,3);assert.equal(result.history_added,0);
result=await run([{...animals[0],status:'archived',pedigree_only:true},...animals.slice(1)],true);assert.equal(result.status,'imported');assert.equal((await db.query("select status from public.animals where name='Root'")).rows[0].status,'active');
result=await run([animal('1','Different source')],true);assert(result.issues.some(x=>x.includes('changed identity')));
await assert.rejects(run(animals,true,'x',{},'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),/Select a herd you own/);
await db.exec("reset role;insert into public.farms values('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Demo','owner',true);set role authenticated;");
await assert.rejects(run(animals,true,'x',{},'cccccccc-cccc-4ccc-8ccc-cccccccccccc'),/Select a herd you own/);
await assert.rejects(run([animals[0],animals[0]]),/Duplicate source animal ID/);
result=await run([animal('10','Missing','Buck',{sire_id:'99'})],true,'missing',{warnings_acknowledged:false});assert.equal(result.status,'preview');
result=await run([animal('10','Missing','Buck',{sire_id:'99'})],true,'missing');assert.equal(result.status,'imported');assert.equal((await db.query("select sire_id from public.animals where name='Missing'")).rows[0].sire_id,null);
result=await run([animal('11','Unknown',null)],true);assert(result.issues.some(x=>x.includes('Buck or Doe')));
result=await run([animal('12','Cycle A','Buck',{sire_id:'13'}),animal('13','Cycle B','Buck',{sire_id:'12'})],true);assert(result.issues.some(x=>x.includes('cycle')));
result=await run([animal('14','Child','Buck',{sire_id:'15'}),animal('15','Doe','Doe')],true);assert(result.issues.some(x=>x.includes('wrong sex')));
for(const dob of ['2999-01-01','invalid','2020-02-30']) {result=await run([animal('16','Bad date','Buck',{dob})],true);assert(result.issues.some(x=>x.includes('birth date')));}
result=await run([animal('17','Wrong conversion','Buck',{...animals[0],source_id:'17',profile_weight:3.10})],true);assert(result.issues.some(x=>x.includes('conversion')));
result=await run([animal('18','Wrong active','Doe',{status:'active'})],true);assert(result.issues.some(x=>x.includes('herd/pedigree')));
result=await run([{...animals[2],source_id:'19',status:'active'}],true);assert(result.issues.some(x=>x.includes('deceased status')));
result=await run([animal('20','One','Buck',{tattoo:'SAME'}),animal('21','Two','Doe',{tattoo:'SAME'})],true);assert.equal(result.animals_added,2);
// Explicit correction overlays are validated and stored without altering originals.
const corrected = animal('27','Corrected','Buck',{profile_weight:4.1875,corrections:{Legs:'',Weight:'4.03',Dob:'2021-01-01'},dob:'2021-01-01',raw:{Id:'27',Name:'Corrected',Legs:'4.03',Weight:'',Dob:'2001-01-01',_csv_headers:[]}});
result=await run([corrected],true,'corrections');assert.deepEqual(result.issues,[]);assert.equal(result.animals_added,1);
const correctionRow=(await db.query("select raw,decisions,profile_weight from public.kintraks_animals where source='corrections'")).rows[0];
assert.equal(correctionRow.raw.Legs,'4.03');assert.equal(correctionRow.raw.Weight,'');assert.equal(correctionRow.decisions.corrections.Weight,'4.03');assert.equal(Number(correctionRow.profile_weight),4.1875);
await assert.rejects(run([{...corrected,source_id:'28',corrections:{Id:'999'}}],true,'bad-corrections'),/never source IDs/);
result=await run([{...corrected,source_id:'28',profile_weight:4.03}],true,'bad-conversion');assert(result.issues.some(x=>x.includes('conversion')));
// Existing animals require an explicit exact match decision and keep their fields.
await db.exec("insert into public.animals(ring_id,name,tattoo,species,sex,breed,status) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Manual','MANUAL','rabbit','Buck','Dutch','active');");
const manual=(await db.query("select id from public.animals where name='Manual'")).rows[0].id;
const candidate=animal('22','Manual','Buck',{tattoo:'MANUAL',breed:'Dutch'});
result=await run([candidate],true);assert(result.issues.some(x=>x.includes('Review existing matches')));
result=await run([{...candidate,existing_id:manual,notes:'Do not overwrite'}],true);assert.equal(result.animals_existing,1);assert.equal(result.animals_added,0);
assert.deepEqual((await db.query('select status,notes,pedigree_only from public.animals where id=$1',[manual])).rows,[{status:'active',notes:null,pedigree_only:false}]);
result=await run([animal('23','Manual','Buck',{tattoo:'MANUAL',breed:'Dutch',keep_separate:true})],true);assert.equal(result.animals_added,1);
result=await run([animal('24','Fake choice','Buck',{existing_id:manual})],true);assert(result.issues.some(x=>x.includes('invalid existing-animal choice')));
// A late snapshot failure must roll back the complete transaction.
await db.exec("reset role;alter table public.kintraks_animals add constraint fixture_failure check(source_id<>'999');set role authenticated;");
await assert.rejects(run([animal('999','Atomic rollback')],true,'atomic'),/fixture_failure/);
assert.equal((await db.query("select count(*)::int n from public.animals where name='Atomic rollback'")).rows[0].n,0);
assert.equal((await db.query("select count(*)::int n from public.kintraks_sources where source='atomic'")).rows[0].n,0);
// Original Rabbit Register rows remain excluded from the manual tattoo index.
await db.exec("insert into public.animals(ring_id,name,tattoo,species,sex,rabbit_register_identity) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','RR1','MANUAL','rabbit','Buck','rr-one');");
await assert.rejects(db.exec("insert into public.animals(ring_id,name,tattoo,species,sex) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Manual duplicate','MANUAL','rabbit','Buck');"),/unique/);
await db.exec("select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false)");
await assert.rejects(db.exec("insert into public.kintraks_sources(ring_id,source) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','wrong-owner')"),/row-level security/);
for(const table of ['kintraks_sources','kintraks_animals']) assert.equal((await db.query(`select count(*)::int n from public.${table}`)).rows[0].n,0);
await db.exec('reset role;set role anon;');
await assert.rejects(db.query('select public.import_kintraks($1,$2,$3::jsonb,true)',[ring,'bad','{}']),/permission denied/);
await db.exec("reset role;set role authenticated;select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false)");
if(process.env.KINTRAKS_PAYLOAD){
 const payload=JSON.parse(readFileSync(process.env.KINTRAKS_PAYLOAD,'utf8'));
 result=await run(payload.animals,false,'sample');assert.deepEqual(result.issues,[]);assert.equal(result.animals_added,537);
 result=await run(payload.animals,true,'sample');assert.equal(result.animals_added,537);assert.equal(result.history_added,537);
 assert.deepEqual((await db.query("select a.status,count(*)::int n from public.animals a join public.kintraks_animals k on k.animal_id=a.id where k.source='sample' group by a.status order by a.status")).rows,[{status:'archived',n:533},{status:'deceased',n:1},{status:'sold',n:3}]);
 assert.equal((await db.query("select count(*)::int n from public.animals a join public.kintraks_animals k on k.animal_id=a.id where k.source='sample' and (a.sire_id is not null)")).rows[0].n,432);
 assert.equal((await db.query("select count(*)::int n from public.animals a join public.kintraks_animals k on k.animal_id=a.id where k.source='sample' and (a.dam_id is not null)")).rows[0].n,430);
 assert.equal((await db.query("select count(*)::int n from public.kintraks_animals where source='sample' and profile_weight is not null")).rows[0].n,328);
 result=await run(payload.animals,true,'sample');assert.equal(result.animals_added,0);assert.equal(result.animals_existing,537);assert.equal(result.history_added,0);
 console.log('Full CSV: 537 animals, 862 links, 328 undated weights; retry added zero.');
}
await db.close();console.log('Kintraks isolated database checks passed.');

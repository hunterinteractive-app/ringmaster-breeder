// Isolated PostgreSQL fixture; never connects to the live database.
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
await db.exec(readFileSync(repo+'/supabase/migrations/20261013133020_global_pedigree_import.sql','utf8'));
await db.exec(readFileSync(repo+'/supabase/migrations/20261013154734_global_pedigree_identity_review.sql','utf8'));
await db.exec(readFileSync(repo+'/supabase/migrations/20261013194706_global_pedigree_history.sql','utf8'));
await db.exec(readFileSync(repo+'/supabase/migrations/20261013202924_global_pedigree_history_profile_weights.sql','utf8'));
await db.exec(readFileSync(repo+'/supabase/migrations/20261014011410_global_pedigree_live_membership.sql','utf8'));
await db.exec(readFileSync(repo+'/supabase/migrations/20261020105258_animal_genotype_record.sql','utf8'));
await db.exec(readFileSync(repo+'/supabase/migrations/20261020112220_global_pedigree_genotype.sql','utf8'));
await db.exec('create trigger breeder_validate_weight before insert on public.animal_weights for each row execute function breeder_private.validate_weight();');
await db.exec("set role authenticated; select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);");
const ring='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
async function run(animals,commit=false,herd=ring,account='fixture'){
 const r=await db.query('select public.import_global_pedigree($1,$2,$3::jsonb,$4) as result',[herd,account,JSON.stringify(animals),commit]);
 return r.rows[0].result;
}
const animals=[
 {source_id:'root',name:'Root',tattoo:'ROOT',sex:'Buck',breed:'Mini Rex',sire_id:'sire',dam_id:'dam',weight:'4.5'},
 {source_id:'dam',name:'Dam',sex:'Doe',pedigree_only:true},
 {source_id:'sire',name:'Sire',sex:'Buck',pedigree_only:true,status:'deceased'},
];
let result=await run(animals);
assert.equal(result.animals_added,3);assert.deepEqual(result.issues,[]);
assert.equal((await db.query('select jsonb_array_length(animals)::int as n from public.global_pedigree_import_drafts')).rows[0].n,3);
assert.equal((await db.query('select count(*)::int as n from public.animals')).rows[0].n,0);
result=await run(animals,true);assert.equal(result.status,'imported');assert.equal(result.animals_added,3);
assert.equal((await db.query('select count(*)::int as n from public.global_pedigree_import_drafts')).rows[0].n,0);
const roots=await db.query("select a.name,s.name as sire,d.name as dam from public.animals a join public.animals s on s.id=a.sire_id join public.animals d on d.id=a.dam_id where a.tattoo='ROOT'");
assert.deepEqual(roots.rows,[{name:'Root',sire:'Sire',dam:'Dam'}]);
result=await run(animals,true);assert.equal(result.animals_added,0);assert.equal(result.animals_existing,3);
assert.equal((await db.query('select count(*)::int as n from public.animal_weights')).rows[0].n,1);
result=await run([{source_id:'missing',name:'Missing',sex:'Buck',sire_id:'absent'}],true);
assert(result.issues.some(x=>x.includes('missing its sire')));
result=await run([{source_id:'a',name:'A',sex:'Buck',sire_id:'b'},{source_id:'b',name:'B',sex:'Buck',sire_id:'a'}],true);
assert(result.issues.some(x=>x.includes('cycle')));
result=await run([{source_id:'x',name:'X',sex:'Doe',tattoo:'ROOT'}]);
assert.deepEqual(result.issues,[]);assert.equal(result.animals_added,1);
result=await run([{source_id:'new-root',name:'Root',sex:'Buck',breed:'Mini Rex',tattoo:'ROOT'}],true);
assert.equal(result.animals_existing,1);assert.equal(result.animals_added,0);
assert.equal((await db.query("select name from public.animals where tattoo='ROOT'")).rows[0].name,'Root');
await assert.rejects(run(animals,true,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),/Select a herd you own/);
await assert.rejects(run([{source_id:'d',name:'D',sex:'Buck'},{source_id:'d',name:'D',sex:'Buck'}]),/Duplicate source animal ID/);
result=await run([{source_id:'no-sex',name:'No Sex'},{source_id:'future',name:'Future',sex:'Buck',dob:'2999-01-01'}],true);
assert.equal(result.issues.length,2);
assert.equal((await db.query('select count(*)::int as n from public.animals')).rows[0].n,3);

// Distinct identities may reuse a tattoo, even when breed and sex are the same.
const reused=[{source_id:'ice',name:'Ice Cream',tattoo:'S2',breed:'Netherland Dwarf',sex:'Doe'}, {source_id:'silver',name:'Silver Dollar',tattoo:'S2',breed:'Netherland Dwarf',sex:'Buck',pedigree_only:true}];
result=await run(reused,true);assert.equal(result.status,'imported');assert.equal(result.animals_added,2);
assert.equal((await db.query("select count(*)::int as n from public.animals where tattoo='S2'")).rows[0].n,2);
assert.equal((await run(reused,true)).animals_added,0);
// Apparent duplicates require a decision. Neither matching nor merging is implicit.
const pair=[{source_id:'dup1',name:'Same Rabbit',tattoo:'SM1',breed:'Mini Rex',sex:'Buck',weight:4}, {source_id:'dup2',name:'Same Rabbit',tattoo:'SM1',breed:'Mini Rex',sex:'Buck',weight:5}];
result=await run(pair,true);assert.equal(result.status,'preview');assert.equal(result.duplicate_groups.length,1);assert(result.issues.some(x=>x.includes('possible duplicate')));
const separate=pair.map(a=>({...a,keep_separate:true}));
result=await run(separate,true);assert.equal(result.animals_added,2);
assert.equal((await run(separate,true)).animals_existing,2);
// An explicit merge selects one record's details, redirects children, and records both IDs.
const merge=[{...pair[0],source_id:'merge1',tattoo:'MERGE',name:'Merge Rabbit',keep_separate:true,pedigree_only:true}, {...pair[1],source_id:'merge2',tattoo:'MERGE',name:'Merge Rabbit',same_as:'merge1'}, {source_id:'child',name:'Child',sex:'Doe',sire_id:'merge2'}];
result=await run(merge,true);assert.equal(result.status,'imported');assert.equal(result.animals_added,2);
const merged=await db.query("select a.pedigree_only,w.weight::text as weight from public.animals a join public.animal_weights w on w.animal_id=a.id where a.name='Merge Rabbit'");
assert.deepEqual(merged.rows,[{pedigree_only:false,weight:'4'}]);
assert.equal((await db.query("select count(distinct animal_id)::int as n from public.global_pedigree_animals where source_id in ('merge1','merge2')")).rows[0].n,1);
assert.equal((await db.query("select p.name from public.animals a join public.animals p on p.id=a.sire_id where a.name='Child'")).rows[0].name,'Merge Rabbit');
assert.equal((await run(merge,true)).animals_added,0);
result=await run([{...pair[0],source_id:'bad1',dob:'2020-01-01',keep_separate:true}, {...pair[1],source_id:'bad2',dob:'2021-01-01',same_as:'bad1'}],true);
assert(result.issues.some(x=>x.includes('birth date')));
result=await run([{...pair[0],keep_separate:true}, {...pair[1],same_as:'dup1'}],true);
assert(result.issues.some(x=>x.includes('previously imported separately')));
result=await run([{source_id:'invalid-date',name:'Invalid',tattoo:'BAD',sex:'Buck',dob:'not-a-date'}]);assert(result.issues.some(x=>x.includes('invalid birth date')));

// "Keep separate" must also override an otherwise exact match to an existing animal.
await db.exec("insert into public.animals(ring_id,name,tattoo,species,breed,sex) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Prior Rabbit','PRIOR','rabbit','Mini Rex','Doe')");
result=await run([{source_id:'prior1',name:'Prior Rabbit',tattoo:'PRIOR',breed:'Mini Rex',sex:'Doe',keep_separate:true},{source_id:'prior2',name:'Prior Rabbit',tattoo:'PRIOR',breed:'Mini Rex',sex:'Doe',keep_separate:true}],true);
assert.equal(result.animals_added,2);assert.equal(result.animals_existing,0);
// Drafts are private to the authenticated owner.
await run([{source_id:'draft',name:'Private Draft',sex:'Doe'}]);
await db.exec("select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false)");
assert.equal((await db.query('select count(*)::int as n from public.global_pedigree_import_drafts')).rows[0].n,0);
await assert.rejects(db.exec("insert into public.global_pedigree_import_drafts(auth_user_id,ring_id,account,animals) values('22222222-2222-4222-8222-222222222222','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','test','[]')"),/row-level security/);
await db.exec("select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false)");
// Ordinary manually entered tattoos still have the original uniqueness rule.
await db.exec("insert into public.animals(ring_id,name,tattoo,species,sex) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Manual1','MANUAL','rabbit','Doe')");
await assert.rejects(db.exec("insert into public.animals(ring_id,name,tattoo,species,sex) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Manual2','MANUAL','rabbit','Doe')"),/unique/);
console.log('Database checks passed: preview has no writes; atomic parent links; safe retries; existing preservation; missing parents; cycles; conflicts; invalid data; unrelated herd denial.');

// A kept archived duplicate becomes active when a merged source record is live.
result=await run([{source_id:'archive-canonical',name:'Live Alias',tattoo:'LIVE',sex:'Doe',status:'archived',keep_separate:true},{source_id:'live-alias',name:'Live Alias',tattoo:'LIVE',sex:'Doe',status:'active',source_live:true,same_as:'archive-canonical'}],true);
assert.equal(result.status,'imported');assert.equal((await db.query("select status from public.animals where name='Live Alias'")).rows[0].status,'active');
result=await run([{source_id:'archive-only',name:'Archive Only',sex:'Buck',status:'archived'}],true);assert.equal(result.status,'imported');
assert.equal((await db.query("select status from public.animals where name='Archive Only'")).rows[0].status,'archived');
// Historical weights and litters are atomic, preserve aliases, and retry safely.
async function runHistory(a,h,commit=false,complete=true){ return (await db.query('select public.import_global_pedigree_with_history($1,$2,$3::jsonb,$4::jsonb,$5,$6) result',[ring,'history-fixture',JSON.stringify(a),JSON.stringify(h),complete,commit])).rows[0].result; }
await db.exec("select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false)");
const ha=[{source_id:'h1',name:'Historic Doe',sex:'Doe',status:'deceased',tattoo:'H1',weight:8,keep_separate:true},{source_id:'h2',name:'Historic Doe',sex:'Doe',status:'deceased',tattoo:'H1',same_as:'h1'},{source_id:'hs',name:'Historic Sire',sex:'Buck',pedigree_only:true,weight:6}];
const hh=[{kind:'weight',source_id:'h2:1',animal_source_id:'h2',weight:4.5,recorded_date:'2022-05-15'},{kind:'litter',source_id:'l1',animal_source_id:'h2',sire_source_id:'hs',fields:{'Date Bred':'02/05/1970','Date Kindled':'04/10/2926'}},{kind:'litter',source_id:'l2',animal_source_id:'h1',sire_source_id:'hs',fields:{'Date Bred':'02/05/1970'}}];
result=await runHistory(ha,hh);assert.equal(result.history_count,3);assert.equal(result.history_warnings.length,3);assert.equal((await db.query('select count(*)::int n from public.global_pedigree_history')).rows[0].n,0);
assert.equal((await db.query('select jsonb_array_length(history)::int n from public.global_pedigree_import_drafts')).rows[0].n,3);
result=await runHistory(ha,hh,true);assert.equal(result.status,'imported');assert.equal(result.history_added,3);
assert.equal((await db.query("select count(*)::int n from public.animal_weights w join public.animals a on a.id=w.animal_id where a.name='Historic Doe'")).rows[0].n,1);
assert.equal((await db.query("select recorded_at::date::text dt from public.animal_weights w join public.animals a on a.id=w.animal_id where a.name='Historic Doe'")).rows[0].dt,'2022-05-15');
assert.equal((await runHistory(ha,hh,true)).history_added,0);
assert.equal((await db.query("select weight::text value from public.animal_weights w join public.animals a on a.id=w.animal_id where a.name='Historic Sire'")).rows[0].value,'6');
await assert.rejects(runHistory([{source_id:'rollback',name:'Rollback',sex:'Buck'}],[{kind:'weight',source_id:'badweight',animal_source_id:'rollback',weight:0,recorded_date:'2022-05-15'}],true),/Invalid historical weight/);
assert.equal((await db.query("select count(*)::int n from public.animals where name='Rollback'")).rows[0].n,0);
await assert.rejects(db.exec("insert into public.animal_weights(animal_id,weight) select id,7 from public.animals where name='Historic Doe'"),/Historical animal is locked/);
await db.exec("select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false)");
assert.equal((await db.query('select count(*)::int n from public.global_pedigree_history')).rows[0].n,0);
await assert.rejects(runHistory(ha,hh,true),/Select a herd you own/);
await db.exec("select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false)");
await db.exec('reset role; create function breeder_private.has_access(p_owner text) returns boolean language sql as $$select breeder_private.owns(p_owner)$$;');
await db.exec(readFileSync(repo+'/supabase/migrations/20261014012604_sales_dashboard.sql','utf8'));
await db.exec(readFileSync(repo+'/supabase/migrations/20261014021444_global_pedigree_sales_source_preview.sql','utf8'));
await db.exec(readFileSync(repo+'/supabase/migrations/20261014020726_global_pedigree_sales_history.sql','utf8'));
await db.exec('set role authenticated');
const sa=[{source_id:'sale-animal',name:'Historic Sale',sex:'Buck',status:'archived'}];
const sh=[{kind:'sale',source_id:'sale-1',animal_source_id:'sale-animal',sale_date:'2021-05-30',sale_cents:300},{kind:'sale',source_id:'sale-2',animal_source_id:'sale-animal',sale_date:'2021-05-30',sale_cents:0}];
async function runSales(h,commit=false){return (await db.query('select public.import_global_pedigree_with_sales($1,$2,$3::jsonb,$4::jsonb,true,$5,true) result',[ring,'sales-fixture',JSON.stringify(sa),JSON.stringify(h),commit])).rows[0].result;}
result=await runSales(sh);assert.equal(result.sales_count,2);assert.equal(result.status,'preview');
assert.equal((await db.query('select count(*)::int n from animal_sales')).rows[0].n,0);
result=await runSales(sh,true);assert.equal(result.status,'imported');assert.equal(result.sales_added,2);
assert.equal((await db.query("select status from animals where name='Historic Sale'")).rows[0].status,'archived');
assert.equal((await db.query('select count(*)::int n from animal_sale_payments')).rows[0].n,0);
assert.deepEqual((await db.query('select buyer_name,payment_history_complete,sale_cents::int from animal_sales order by import_source_id')).rows,[{buyer_name:'',payment_history_complete:false,sale_cents:300},{buyer_name:'',payment_history_complete:false,sale_cents:0}]);
assert.equal((await runSales(sh,true)).sales_added,0);
result=await runSales([{...sh[0],source_id:'future',sale_date:'2999-01-01'}],true);assert.equal(result.status,'preview');assert(result.issues.length>0);
await db.exec("select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false)");
assert.equal((await db.query('select count(*)::int n from animal_sales')).rows[0].n,0);await assert.rejects(runSales(sh,true),/Select a herd you own/);
console.log('Historical sales checks passed: separate source IDs, zero price, blank buyer, unknown receipts, stable animal status, retries, future date and ownership.');
// Genotype reference import: source unknowns remain literal, no biology is guessed.
await db.exec("select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false)");
const ga=[{source_id:'gene-new',name:'Source Genotype',sex:'Doe',known_genotype:'aa bb C_ dd E_',sire_id:'gene-ancestor'},
 {source_id:'gene-ancestor',name:'Ancestor Genotype',sex:'Buck',pedigree_only:true,known_genotype:'aa bb C? D- E- enen Sa-'},
 {source_id:'gene-blank',name:'No Genotype',sex:'Buck'}];
result=await run(ga);
assert.equal(result.rows.find(r=>r.source_id==='gene-new').known_genotype,'aa bb C_ dd E_');
assert.equal((await db.query("select count(*)::int n from animals where name='Source Genotype'")).rows[0].n,0);
assert.equal((await db.query("select animals->0->>'known_genotype' g from global_pedigree_import_drafts")).rows[0].g,'aa bb C_ dd E_');
assert.equal((await run(ga,true)).status,'imported');
let genotype=(await db.query("select genotype from animals where name='Source Genotype'")).rows[0].genotype;
assert.deepEqual(genotype,{notation:'aa bb C_ dd E_',basis:'imported',source:'Global Pedigree: Known Genotype (rabbit gene-new). Method not verified.'});
assert.equal((await db.query("select genotype->>'notation' g from animals where name='Ancestor Genotype'")).rows[0].g,'aa bb C? D- E- enen Sa-');
assert.deepEqual((await db.query("select genotype from animals where name='No Genotype'")).rows[0].genotype,{});
const changed=ga.map(a=>a.source_id==='gene-new'?{...a,known_genotype:'aa bb CC dd EE'}:a);
assert.equal((await run(changed,true)).animals_added,0);
assert.deepEqual((await db.query("select genotype from animals where name='Source Genotype'")).rows[0].genotype,genotype);
assert.equal((await db.query("select source_known_genotype g from global_pedigree_animals where source_id='gene-new'")).rows[0].g,'aa bb CC dd EE');
await run(ga.map(({known_genotype,...a})=>a),true);
assert.equal((await db.query("select source_known_genotype g from global_pedigree_animals where source_id='gene-new'")).rows[0].g,'aa bb CC dd EE');
// A pre-existing manual entry is never overwritten, even if source differs.
await db.exec("insert into animals(ring_id,name,tattoo,species,sex,genotype) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Manual Gene','G1','rabbit','Doe','{\"notation\":\"bb dd\",\"basis\":\"breeder_entered\"}')");
result=await run([{source_id:'manual-gene',name:'Manual Gene',tattoo:'G1',sex:'Doe',known_genotype:'bb D-'}],true);
assert.equal(result.animals_existing,1);
assert.equal((await db.query("select genotype->>'notation' g from animals where name='Manual Gene'")).rows[0].g,'bb dd');
assert.equal((await db.query("select source_known_genotype g from global_pedigree_animals where source_id='manual-gene'")).rows[0].g,'bb D-');
// Merges retain the selected genotype and each source's differing evidence.
const gm=[{source_id:'gm1',name:'Gene Merge',tattoo:'GM',sex:'Buck',keep_separate:true,known_genotype:'aa bb C-'},
 {source_id:'gm2',name:'Gene Merge',tattoo:'GM',sex:'Buck',same_as:'gm1',known_genotype:'aa bb cc'}];
assert.equal((await run(gm,true)).status,'imported');
assert.equal((await db.query("select genotype->>'notation' g from animals where name='Gene Merge'")).rows[0].g,'aa bb C-');
assert.deepEqual((await db.query("select source_known_genotype g from global_pedigree_animals where source_id in ('gm1','gm2') order by source_id")).rows,[{g:'aa bb C-'},{g:'aa bb cc'}]);
for(const invalid of [123,{},[],true,'a'.repeat(501)]) {
 result=await run([{source_id:'bad-gene',name:'Bad Gene',sex:'Buck',known_genotype:invalid}],true);
 assert.equal(result.status,'preview');assert(result.issues.some(x=>x.includes('invalid source genotype')));
}
assert.equal((await db.query("select count(*)::int n from animals where name='Bad Gene'")).rows[0].n,0);
// Genotype also survives the actual sales/history wrapper used by the client.
assert.equal((await db.query('select public.import_global_pedigree_with_sales($1,$2,$3::jsonb,$4::jsonb,true,true,true) result',
 [ring,'gene-wrapper',JSON.stringify([{source_id:'gw',name:'Wrapper Gene',sex:'Doe',known_genotype:'bb dd'}]),'[]'])).rows[0].result.status,'imported');
assert.equal((await db.query("select genotype->>'notation' g from animals where name='Wrapper Gene'")).rows[0].g,'bb dd');
await db.exec("select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false)");
assert.equal((await db.query('select count(*)::int n from global_pedigree_animals')).rows[0].n,0);
await assert.rejects(run(ga,true),/Select a herd you own/);
assert.equal((await db.query("update global_pedigree_animals set source_known_genotype='cc' returning source_id")).rows.length,0);
await assert.rejects(db.exec("update global_pedigree_animals set source_account='other'"),/permission denied/);
console.log('Genotype checks passed: preview/draft, imported references and ancestors, literal unknowns, missing values, repeat/manual preservation, source evidence, merges, invalid inputs, wrapper and owner isolation.');
await db.close();

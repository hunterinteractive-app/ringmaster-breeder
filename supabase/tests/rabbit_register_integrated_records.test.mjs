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

await db.exec(`
alter table public.users add column display_name text default '',add column phone text default '',add column address text default '',add column city text default '',add column state text default '',add column zip text default '';
grant select,update on public.users to authenticated;
alter table public.users enable row level security;
create policy self_profile on public.users for all to authenticated using(breeder_private.owns(id)) with check(breeder_private.owns(id));
create function breeder_private.has_access(p_owner text) returns boolean language sql stable as $$select breeder_private.owns(p_owner)$$;
create function breeder_private.animal_access(p_animal uuid) returns boolean language sql stable as $$select exists(select 1 from public.animals a join public.farms f on f.id=a.ring_id where a.id=p_animal and breeder_private.has_access(f.owner_id))$$;
create table public.breeder_show_history(id uuid primary key default gen_random_uuid(),owner_id text references public.users,source_app text,source_entry_id uuid,animal_id uuid references public.animals,exhibitor_source_id uuid,record jsonb,source_available boolean default true,unique(owner_id,source_app,source_entry_id));
alter table public.breeder_show_history enable row level security;
grant select on public.breeder_show_history to authenticated;
create policy show_read on public.breeder_show_history for select to authenticated using(breeder_private.has_access(owner_id));
create table public.breeder_exhibitor_profiles(id uuid primary key default gen_random_uuid(),owner_id text references public.users,source_app text constraint breeder_exhibitor_profiles_source_app_check check(source_app in ('ringmaster_show','ringmaster_club','ringmaster_breeder')),source_id uuid,profile jsonb,unique(owner_id,source_app,source_id));
alter table public.breeder_exhibitor_profiles enable row level security;
grant select on public.breeder_exhibitor_profiles to authenticated;
create policy profile_read on public.breeder_exhibitor_profiles for select to authenticated using(breeder_private.has_access(owner_id));
create table public.global_pedigree_import_drafts(sales_complete_placeholder boolean);
`);
for(const name of ['20261010161513_breeding_records','20261010173452_litter_tracking','20261010173929_litter_tracking_hardening','20261011162024_litter_sex_counts'])await db.exec(readFileSync(repo+'/supabase/migrations/'+name+'.sql','utf8'));
const sales=readFileSync(repo+'/supabase/migrations/20261014012604_sales_dashboard.sql','utf8');
await db.exec(sales.slice(0,sales.indexOf('-- Keep verified account deletion')));
const gp=readFileSync(repo+'/supabase/migrations/20261014020726_global_pedigree_sales_history.sql','utf8');
await db.exec(gp.slice(0,gp.indexOf('create function public.import_global_pedigree_with_sales')));
await db.exec(readFileSync(repo+'/supabase/migrations/20261014091326_automatic_sale_status.sql','utf8'));
await db.exec(readFileSync(repo+'/supabase/migrations/20261021144237_rabbit_register_integrated_records.sql','utf8'));
await db.exec(readFileSync(repo+'/supabase/migrations/20261021230151_rabbit_register_import_archive_quota_fix.sql','utf8'));
await db.exec("set role authenticated;select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false)");
const ring='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
async function run(data,commit=false,source='full') {return (await db.query('select public.import_rabbit_register($1,$2,$3::jsonb,$4) r',[ring,source,JSON.stringify(data),commit])).rows[0].r;}
function animal(id,sex='Buck',raw={}){return {source_id:id,name:'Animal '+id,breed:'Dutch',sex,status:id==='1'?'sold':'active',raw:{CID:id,Name:'Animal '+id,Breed:'Dutch',...raw}};}
const originalXml='\ufeff<?xml version="1.0"?><ExportedData><Header><ProgramVersion>15.fixture</ProgramVersion></Header><Animals /></ExportedData>\r\n';
const data={original_file_base64:Buffer.from(originalXml).toString('base64'),header:{ProgramVersion:'15.fixture'},filename:'Original.XML',warnings_acknowledged:true,animals:[animal('1','Buck',{SellerKey:'1',BuyerKey:'2',AmountPaid:'12.50',DateBought:'2010-01-01',DateSold:'2014-01-01',SoldFor:'50',Cage:'A12',Breeder1:'Custom breeder'}),animal('2','Doe')],records:[
 {kind:'contact',source_id:'1',raw:{ID:'1',FirstName:'Seller',Rabbitry:'Seller rabbits',Phone0:'123'}},
 {kind:'contact',source_id:'2',raw:{ID:'2',FirstName:'Buyer',Rabbitry:'Buyer rabbits'}},
 {kind:'litter',source_id:'1',animal_source_id:'2',sire_source_id:'1',raw:{ID:'1',DATEBRED:'2013-01-01',DATEBORN:'2013-02-01',NUMBERBORN:'5',NUMBERWEANED:'4',DIED:'1',DATEWEANED:'0100-01-01',REMOVELITTERCOMPLETE:'True',DATEPAIRED:'2012-12-30',DATESPLIT:'2013-01-02',SCHEDULEDBREEDINGDATE:'2013-04-01',BREEDINGOCCURRED:'True',INSTALLNESTBOXCOMPLETE:'True',REMOVENESTBOXCOMPLETE:'False',REBREEDINGENABLED:'True',REBREEDINGOVERRIDDEN:'False',CAGE:'L1',BUCKS:'3',DOES:'1',ADDED:'1',RAISED:'4',KEPT:'2',SOLD:'2',SHOWQUALITY:'2',BreedNotes:'Custom litter value',PALPATERESULTS:'F'}},
 {kind:'litter',source_id:'2',animal_source_id:'2',raw:{ID:'2',DATEBRED:'0100-01-02',NUMBERBORN:'0'}},
 {kind:'show',source_id:'1',animal_source_id:'1',raw:{ID:'1',ShowName:'Show',ShowDate:'2013-06-01',Judge:'Judge A',WINS:'BOB',IsALeg:'True',RankInClass:'1'}},
 {kind:'weight',source_id:'1',animal_source_id:'1',weight:4,recorded_date:'2013-01-01',raw:{ID:'1',FEEDWT:'2267.96'}},
 {kind:'weight',source_id:'2',animal_source_id:'1',weight:null,recorded_date:null,raw:{ID:'2',CRITTERWT:'0',WEIGHINGDATE:'0100-01-03',FEEDWT:'-1.5'}},
 {kind:'weight',source_id:'3',animal_source_id:'1',weight:null,recorded_date:'2013-01-02',raw:{ID:'3',CRITTERWT:'0',FEEDWT:'453.592',WEIGHINGDATE:'2013-01-02'}},
 {kind:'litter_weight',source_id:'1',litter_source_id:'1',raw:{ID:'1',LITTERKEY:'1',LITTERWT:'1814.368',FEEDWT:'2267.96',WEIGHINGDATE:'2013-03-01'}},
 {kind:'litter_weight',source_id:'2',raw:{ID:'2',LITTERKEY:'1',LITTERWT:'0',WEIGHINGDATE:'0100-01-02'}},
 {kind:'wool',source_id:'1',animal_source_id:'1',raw:{WID:'1',CID:'1',SHEARDATE:'2013-07-01',FLEECEWT:'0',PRIME:'20',AFD:'12'}},
 {kind:'picture',source_id:'1',animal_source_id:'1',raw:{PID:'1',FILENAME:'pic.jpg'}},
]};
let r=await run(data);assert.deepEqual(r.issues,[]);assert.equal((await db.query('select count(*)::int n from public.rabbit_register_files')).rows[0].n,0);assert.equal((await db.query('select count(*)::int n from public.animals')).rows[0].n,0);
r=await run(data,true);assert.equal(r.status,'imported');
assert.equal((await db.query('select count(*)::int n from public.herd_contacts')).rows[0].n,2);
let management=(await db.query('select * from public.animal_management where cage=\'A12\'')).rows[0];assert.equal(management.purchase_cents,1250);assert.equal(management.custom_fields.Breeder1,'Custom breeder');assert(management.buyer_contact_id&&management.seller_contact_id);
assert.equal((await db.query('select count(*)::int n from public.breeding_records')).rows[0].n,2);
assert.equal((await db.query('select count(*)::int n from public.breeding_records where breeding_date is null and sire_id is null')).rows[0].n,1);
assert.equal((await db.query('select count(*)::int n from public.litter_weights')).rows[0].n,1);
assert.equal((await db.query('select weight::text from public.litter_weights')).rows[0].weight,'4.0000000000000000');
assert.equal((await db.query('select count(*)::int n from public.animal_weights')).rows[0].n,1);
assert.equal((await db.query('select count(*)::int n from public.animal_wool_records')).rows[0].n,1);
const show=(await db.query('select record from public.breeder_show_history')).rows[0].record;assert.equal(show.judge,'Judge A');assert.equal(show.is_leg,true);
const sale=(await db.query('select * from public.animal_sales')).rows[0];assert.equal(sale.sale_cents,5000);assert.equal(sale.payment_history_complete,false);assert.equal(sale.buyer_name,'Buyer');
assert.equal((await db.query('select count(*)::int n from public.animal_sale_payments')).rows[0].n,0);
await run(data,true);
for(const [table,count] of [['animals',2],['animal_sales',1],['breeding_records',2],['herd_contacts',2],['litter_weights',1],['animal_wool_records',1],['breeder_show_history',1],['animal_weights',1]])assert.equal((await db.query('select count(*)::int n from public.'+table)).rows[0].n,count,table+' retry');
// Explicit account setup fills gaps or replaces populated contact fields; login identity stays intact.
await db.query("update public.users set display_name='Current' where id='owner'");
await db.query('select public.use_herd_contact($1,\'fill\',true)',[management.seller_contact_id]);
assert.equal((await db.query("select display_name,rabbitry_name from public.users where id='owner'")).rows[0].display_name,'Current');
await db.query('select public.use_herd_contact($1,\'replace\',false)',[management.seller_contact_id]);assert.equal((await db.query("select display_name from public.users where id='owner'")).rows[0].display_name,'Seller');
assert.equal((await db.query('select count(*)::int n from public.breeder_exhibitor_profiles')).rows[0].n,1);
// Manual management edits survive repeat linking. A stale revision is rejected.
await db.query('select public.save_animal_management($1,$2::jsonb,$3)',[management.animal_id,JSON.stringify({cage:'Manual cage',custom_fields:{Breeder1:'Edited'}}),(await db.query('select revision from public.animal_management where animal_id=$1',[management.animal_id])).rows[0].revision]);
await assert.rejects(db.query('select public.save_animal_management($1,$2::jsonb,0)',[management.animal_id,'{}']),/changed/);
await run(data,true);assert.equal((await db.query('select cage from public.animal_management where animal_id=$1',[management.animal_id])).rows[0].cage,'Manual cage');
// A failure after source insertion rolls back the complete promotion.
const beforeCount=(await db.query('select count(*)::int n from public.animals')).rows[0].n;
await db.exec("reset role;alter table public.herd_contacts add constraint fixture_late_failure check(name<>'ROLLBACK');set role authenticated");
await assert.rejects(run({warnings_acknowledged:true,animals:[animal('90')],records:[{kind:'contact',source_id:'90',raw:{ID:'90',FirstName:'ROLLBACK'}}]},true,'rollback-native'),/fixture_late_failure/);
assert.equal((await db.query('select count(*)::int n from public.animals')).rows[0].n,beforeCount);
assert.equal((await db.query("select count(*)::int n from public.rabbit_register_sources where source='rollback-native'")).rows[0].n,0);
const bid=(await db.query('select id from public.breeding_records limit 1')).rows[0].id;
// Contacts and show results support ongoing additions and revision-checked edits.
const contactId='33333333-3333-4333-8333-333333333333';
const person={name:'New breeder',rabbitry:'New rabbitry',phone:'123'};
await db.query('select public.save_herd_contact($1,$2,$3::jsonb,0)',[contactId,ring,JSON.stringify(person)]);
await db.query('select public.save_herd_contact($1,$2,$3::jsonb,0)',[contactId,ring,JSON.stringify(person)]);
assert.equal((await db.query('select count(*)::int n from public.herd_contacts where id=$1',[contactId])).rows[0].n,1);
await db.query('select public.save_herd_contact($1,$2,$3::jsonb,1)',[contactId,ring,JSON.stringify({...person,phone:'456'})]);
await assert.rejects(db.query('select public.save_herd_contact($1,$2,$3::jsonb,1)',[contactId,ring,JSON.stringify({...person,phone:'789'})]),/changed/);
const showId=(await db.query('select id from public.breeder_show_history limit 1')).rows[0].id;
const editShow={show_name:'Show',show_date:'2013-06-01',judge:'Judge B',placement:'2',awards:'BOV',is_leg:true};
await db.query('select public.save_managed_show_result($1,$2,$3::jsonb,1)',[showId,management.animal_id,JSON.stringify(editShow)]);
await run(data,true);
assert.equal((await db.query('select record from public.breeder_show_history where id=$1',[showId])).rows[0].record.judge,'Judge B');
assert.equal((await db.query("select record->'raw'->>'Judge' j from public.rabbit_register_records where kind='show'")).rows[0].j,'Judge A');
const manualShowId='55555555-5555-4555-8555-555555555555';
await db.query('select public.save_managed_show_result($1,$2,$3::jsonb,0)',[manualShowId,management.animal_id,JSON.stringify({...editShow,show_name:'Next show'})]);
await db.query('select public.save_managed_show_result($1,$2,$3::jsonb,0)',[manualShowId,management.animal_id,JSON.stringify({...editShow,show_name:'Next show'})]);
const woolId=(await db.query('select id from public.animal_wool_records limit 1')).rows[0].id;
await db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,1)',['wool',woolId,management.animal_id,JSON.stringify({recorded_date:'2013-07-01',fleece_grams:30,measurements:{PRIME:25},notes:'Corrected harvest'})]);
assert.equal((await db.query('select fleece_grams::text w from public.animal_wool_records where id=$1',[woolId])).rows[0].w,'30');
await assert.rejects(db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,1)',['wool',woolId,management.animal_id,JSON.stringify({recorded_date:'2013-07-01',fleece_grams:40})]),/changed/);
// Link an existing kit, fill the missing historical weaning date, and create only the remainder.
const litter=(await db.query("select * from public.breeding_records where import_source_id='1'")).rows[0];
const child='44444444-4444-4444-8444-444444444444';
await db.query("insert into public.animals(id,ring_id,name,tattoo,species,sex,breed,dob,sire_id,dam_id,status) values($1,$2,'Existing kit','KIT1','rabbit','Buck','Dutch','2013-02-01',$3,$4,'active')",[child,ring,litter.sire_id,litter.dam_id]);
await db.query('select public.link_litter_offspring($1,$2::uuid[])',[litter.id,[child]]);
await db.query('select public.link_litter_offspring($1,$2::uuid[])',[litter.id,[child]]);
const tracking=(await db.query('select * from public.breeding_tracking where breeding_id=$1',[litter.id])).rows[0];
await db.query('select public.save_breeding_tracking($1,$2::jsonb,$3)',[litter.id,JSON.stringify({birth_date:'2013-02-01',wean_date:'2013-03-01',weaned:4,check_result:'Not checked',status:'completed'}),tracking.revision]);
const young=[{name:'New kit 2',tattoo:'KIT2',sex:'M'},{name:'New kit 3',tattoo:'KIT3',sex:'F'},{name:'New kit 4',tattoo:'KIT4',sex:'F'}];
assert.equal((await db.query('select public.create_litter_animals($1,$2::jsonb) n',[litter.id,JSON.stringify(young)])).rows[0].n,3);
assert.equal((await db.query('select count(*)::int n from public.breeding_offspring where breeding_id=$1',[litter.id])).rows[0].n,4);
await assert.rejects(db.query('select public.create_litter_animals($1,$2::jsonb)',[litter.id,JSON.stringify(young)]),/already created/);
// Regular future sales still reserve on buyer details and complete on payment.
const currentAnimal=(await db.query("select id from public.animals where tattoo='KIT2'")).rows[0].id;
const currentSale=(await db.query("insert into public.animal_sales(animal_id,ring_id,animal_name,asking_cents) values($1,$2,'',5000) returning id",[currentAnimal,ring])).rows[0].id;
await db.query("update public.animal_sales set buyer_contact_id=$1,buyer_name='New breeder',sale_cents=5000 where id=$2",[contactId,currentSale]);
assert.equal((await db.query('select status from public.animal_sales where id=$1',[currentSale])).rows[0].status,'reserved');
await db.query("insert into public.animal_sale_payments(sale_id,kind,amount_cents,paid_on) values($1,'payment',5000,'2014-02-01')",[currentSale]);
assert.equal((await db.query('select status from public.animal_sales where id=$1',[currentSale])).rows[0].status,'sold');
assert.equal((await db.query('select buyer_contact_id from public.animal_management where animal_id=$1',[currentAnimal])).rows[0].buyer_contact_id,contactId);
// Extra litter fields are native/editable and survive reimport without replacing edits.
let extraTracking=(await db.query('select * from public.breeding_tracking where breeding_id=$1',[litter.id])).rows[0];
assert.equal(extraTracking.cage,'L1');assert.equal(extraTracking.nest_installed,true);assert.equal(extraTracking.nest_removed,false);
assert.equal(extraTracking.added,1);assert.equal(extraTracking.bucks,3);assert.equal(extraTracking.custom_fields.BreedNotes,'Custom litter value');
await db.query('select public.save_breeding_tracking($1,$2::jsonb,$3)',[litter.id,JSON.stringify({nest_removed:true,kept:3,custom_fields:{BreedNotes:'Edited litter value'}}),extraTracking.revision]);
await run(data,true);extraTracking=(await db.query('select * from public.breeding_tracking where breeding_id=$1',[litter.id])).rows[0];
assert.equal(extraTracking.nest_removed,true);assert.equal(extraTracking.kept,3);assert.equal(extraTracking.custom_fields.BreedNotes,'Edited litter value');
assert.equal(extraTracking.import_record.KEPT,'2');
// A missing-sire litter remains editable through ordinary tracking.
const unknownLitter=(await db.query("select id from public.breeding_records where import_source_id='2' and import_source='full'")).rows[0].id;
await db.query('select public.save_breeding_tracking($1,$2::jsonb,1)',[unknownLitter,JSON.stringify({notes:'Continued tracking',cage:'L2',status:'active'})]);
assert.equal((await db.query('select cage from public.breeding_tracking where breeding_id=$1',[unknownLitter])).rows[0].cage,'L2');
// Exact XML and header are archived at commit, not preview; retries are deduplicated.
const archive=(await db.query('select * from public.rabbit_register_files')).rows[0];assert.equal(Buffer.from(archive.original_file_base64,'base64').toString('utf8'),originalXml);assert.equal(archive.header.ProgramVersion,'15.fixture');
await run({...data,original_file_base64:Buffer.from(originalXml+' ').toString('base64')},true);
assert.equal((await db.query('select count(*)::int n from public.rabbit_register_files')).rows[0].n,2);
await assert.rejects(db.query("update public.rabbit_register_files set original_file_base64='changed'"),/permission denied/);
// Feed-only source readings do not fabricate zero body weights or chart dates.
assert.equal((await db.query('select count(*)::int n from public.animal_feed_weights')).rows[0].n,2);
assert.equal((await db.query('select count(*)::int n from public.animal_feed_weights where weight is null and feed_weight=1')).rows[0].n,1);
assert.equal((await db.query('select count(*)::int n from public.animal_feed_weights where native_weight_id is not null')).rows[0].n,1);
const feedId='66666666-6666-4666-8666-666666666666';
const feedData={recorded_date:'2014-01-01',weight:null,feed_weight:12,notes:'Feed without body weight'};
const beforeFeedCharts=(await db.query('select count(*)::int n from public.animal_weights')).rows[0].n;
await db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,0)',['animal_feed',feedId,management.animal_id,JSON.stringify(feedData)]);
await db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,0)',['animal_feed',feedId,management.animal_id,JSON.stringify(feedData)]);
assert.equal((await db.query('select count(*)::int n from public.animal_weights')).rows[0].n,beforeFeedCharts);
await db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,1)',['animal_feed',feedId,management.animal_id,JSON.stringify({...feedData,voided:true})]);
assert.equal((await db.query('select voided from public.animal_feed_weights where id=$1',[feedId])).rows[0].voided,true);
await db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,2)',['animal_feed',feedId,management.animal_id,JSON.stringify({...feedData,voided:false})]);
// Wool evaluations can have no known harvest date, with all laboratory values retained.
const evaluationId='77777777-7777-4777-8777-777777777777';
const advanced={fleece_grams:null,recorded_date:null,measurements:{CRIMPCOUNT:3,SD:2,CV:15,CEM:4,CF:99,LT15:20,GT30:1,VEGMATTERBASE:2,WOOLBASE:90,COLOR:'White',XMLDATA:'<JudgingInfo><Judge>A &amp; B</Judge><WoolPerf>Good</WoolPerf><Extra>Keep</Extra></JudgingInfo>'}};
await db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,0)',['wool',evaluationId,management.animal_id,JSON.stringify(advanced)]);
assert.equal((await db.query('select measurements from public.animal_wool_records where id=$1',[evaluationId])).rows[0].measurements.CF,99);
await assert.rejects(db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,1)',['wool',evaluationId,management.animal_id,JSON.stringify({...advanced,measurements:{CF:101}})]),/Percentage/);
await assert.rejects(db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,1)',['wool',evaluationId,management.animal_id,JSON.stringify({...advanced,measurements:{SD:-2}})]),/Invalid wool/);
// Reviewed wool preferences control units, yield factors, pedigree output and
// optional dated body-weight links. Retried saves cannot add duplicate readings.
const woolSettings={unit:'oz',metric:'adjusted',period:'lifetime',factors:{PRIME:100,GRADE2:75,COMBINGS:25,FELTEDSTAINED:25},show_on_pedigree:true,update_body_weight:true};
await db.query('select public.save_wool_settings($1,$2::jsonb,0)',[management.animal_id,JSON.stringify(woolSettings)]);
await db.query('select public.save_wool_settings($1,$2::jsonb,0)',[management.animal_id,JSON.stringify(woolSettings)]);
assert.equal((await db.query('select revision from public.wool_settings')).rows[0].revision,1);
await assert.rejects(db.query('select public.save_wool_settings($1,$2::jsonb,0)',[management.animal_id,JSON.stringify({...woolSettings,unit:'g'})]),/changed/);
await assert.rejects(db.query('update public.wool_settings set factors=$1::jsonb',[JSON.stringify({PRIME:101})]),/Scale factors/);
const datedWool='88888888-8888-4888-8888-888888888888';
const datedWoolData={recorded_date:'2015-01-01',fleece_grams:20,measurements:{PRIME:20,BODYWT:1814.368},notes:'New harvest'};
const chartBefore=(await db.query('select count(*)::int n from public.animal_weights')).rows[0].n;
await db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,0)',['wool',datedWool,child,JSON.stringify(datedWoolData)]);
await db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,0)',['wool',datedWool,child,JSON.stringify(datedWoolData)]);
assert.equal((await db.query('select count(*)::int n from public.animal_weights')).rows[0].n,chartBefore+1);
const savedWool=(await db.query('select * from public.animal_wool_records where id=$1',[datedWool])).rows[0];assert(savedWool.native_weight_id);
await assert.rejects(db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,1)',['wool',datedWool,child,JSON.stringify({...datedWoolData,measurements:{BODYWT:2267.96}})]),/Weight History/);
await assert.rejects(db.query("update public.animal_wool_records set native_weight_id=$1 where id=$2",[savedWool.native_weight_id,evaluationId]),/Invalid linked/);
const undatedBody='99999999-9999-4999-8999-999999999999';
await db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,0)',['wool',undatedBody,child,JSON.stringify({recorded_date:null,measurements:{BODYWT:1814.368}})]);
assert.equal((await db.query('select count(*)::int n from public.animal_weights')).rows[0].n,chartBefore+1);
// An unresolved negative source ID stays untouched until a breeder chooses its
// rabbit. A retry reuses the link, and it cannot be moved to another animal.
const unlinked={kind:'wool',source_id:'3',raw:{WID:'3',CID:'-1',SHEARDATE:'0100-01-03',CF:'95',XMLDATA:'<JudgingInfo><Judge>Judge A</Judge></JudgingInfo>'}};
await run({...data,records:[...data.records,unlinked]},true);
const explicitLink=(await db.query("select public.link_rabbit_register_wool($1,'full','3',$2) id",[ring,management.animal_id])).rows[0].id;
assert.equal((await db.query("select public.link_rabbit_register_wool($1,'full','3',$2) id",[ring,management.animal_id])).rows[0].id,explicitLink);
assert.equal((await db.query("select record->'raw'->>'CID' cid from public.rabbit_register_records where kind='wool' and source_id='3'")).rows[0].cid,'-1');
assert.equal((await db.query('select recorded_date from public.animal_wool_records where id=$1',[explicitLink])).rows[0].recorded_date,null);
await assert.rejects(db.query("select public.link_rabbit_register_wool($1,'full','3',$2)",[ring,currentAnimal]),/already linked/);
// Another owner's contact, sale, wool, litter and management data cannot be read or written.
await db.exec("select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false)");
for(const table of ['herd_contacts','animal_management','litter_weights','animal_wool_records','animal_feed_weights','rabbit_register_files','wool_settings','breeding_records','breeder_show_history'])assert.equal((await db.query('select count(*)::int n from public.'+table)).rows[0].n,0,table+' owner isolation');
await assert.rejects(db.query('select public.save_herd_contact($1,$2,$3::jsonb,0)',[contactId,ring,JSON.stringify(person)]),/access denied/);
await assert.rejects(db.query('select public.save_managed_show_result($1,$2,$3::jsonb,0)',[showId,management.animal_id,JSON.stringify(editShow)]),/access denied/);
await assert.rejects(db.query('select public.save_production_measurement($1,$2,$3,$4::jsonb,1)',['wool',woolId,management.animal_id,'{}']),/access denied/);
await assert.rejects(db.query('select public.link_litter_offspring($1,$2::uuid[])',[litter.id,[child]]),/access denied/);
await assert.rejects(db.query('select public.use_herd_contact($1,\'replace\',false)',[management.seller_contact_id]),/Select a contact/);
await assert.rejects(db.query('select public.link_rabbit_register_history($1,\'full\',true)',[ring]),/Select a herd/);
await assert.rejects(db.query("insert into public.herd_contacts(ring_id,source,source_id) values($1,'intruder','1')",[ring]),/row-level security/);
await assert.rejects(db.query("insert into public.animal_management(animal_id,cage) values($1,'intruder')",[management.animal_id]),/row-level security/);
await assert.rejects(db.query("insert into public.litter_weights(breeding_id,weight,recorded_date) values($1,1,'2014-01-01')",[bid]),/row-level security/);
await assert.rejects(db.query("insert into public.animal_wool_records(animal_id,recorded_date) values($1,'2014-01-01')",[management.animal_id]),/row-level security/);
await assert.rejects(db.query('select public.save_wool_settings($1,$2::jsonb,0)',[management.animal_id,JSON.stringify(woolSettings)]),/access denied/);
await assert.rejects(db.query("select public.link_rabbit_register_wool($1,'full','3',$2)",[ring,management.animal_id]),/access denied/);
await db.exec('reset role;set role anon');
await assert.rejects(db.query('select public.link_rabbit_register_history($1,\'full\',true)',[ring]),/permission denied/);
await db.exec("reset role;set role authenticated;select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false)");
// Historical rows must not temporarily consume active-animal slots. This
// reproduces a Hobby-size active cap while importing a larger archived herd.
await db.exec(`reset role;
create function public.fixture_active_quota() returns trigger language plpgsql as $$ begin
 if new.status='active' and (select count(*) from public.animals where status='active')>=50 then raise exception 'Fixture active quota exceeded';end if;return new;end $$;
create trigger fixture_active_quota before insert on public.animals for each row execute function public.fixture_active_quota();
set role authenticated;`);
const largeArchive={warnings_acknowledged:true,animals:Array.from({length:55},(_,i)=>({...animal(String(1000+i)),status:i===0?'active':'archived'})),records:[]};
assert.equal((await run(largeArchive,true,'archive-quota')).animals_added,55);
assert.equal((await db.query("select count(*)::int n from public.animals where rabbit_register_identity like '%archive-quota%' and status='active'")).rows[0].n,1);
await db.exec('reset role;drop trigger fixture_active_quota on public.animals;drop function public.fixture_active_quota();set role authenticated;');
// Optional real exports are parsed locally and never sent to production.
for(const path of (process.env.RABBIT_REGISTER_EXTENDED_PAYLOADS??'').split(':').filter(Boolean)){
 const sample=JSON.parse(readFileSync(path,'utf8'));sample.warnings_acknowledged=true;
 sample.animals=sample.animals.map(a=>{const n={...a,sex:a.sex??'Buck'};for(const l of sample.review_parent_links??[])if(l.source_id===a.source_id)n[l.side]=null;return n;});
 const source='sample-'+path;let result=await run(sample,false,source);assert.deepEqual(result.issues,[]);
 result=await run(sample,true,source);assert.equal(result.status,'imported');console.log(path,result.animals_added,result.history_added);
 assert.equal((await run(sample,true,source)).animals_added,0);
}
await db.close();console.log('Integrated Rabbit Register records, retries, account choices and owner isolation passed.');

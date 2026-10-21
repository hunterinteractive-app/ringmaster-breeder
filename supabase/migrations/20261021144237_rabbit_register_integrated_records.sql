-- Promote retained Rabbit Register evidence into the normal management screens.
-- Original snapshots remain immutable. Native records have stable source identities.
alter table public.rabbit_register_records drop constraint rabbit_register_records_kind_check;
alter table public.rabbit_register_records add constraint rabbit_register_records_kind_check check(kind in
 ('contact','litter','show','weight','litter_weight','wool','mileage','picture','growth','finance','journal','sweep'));

create table public.rabbit_register_files (
 id uuid primary key default gen_random_uuid(), ring_id uuid not null, source text not null,
 imported_at timestamptz not null default now(), filename text not null,
 original_file_base64 text not null check(octet_length(decode(original_file_base64,'base64'))<=10485760),
 header jsonb not null default '{}' check(jsonb_typeof(header)='object'), recovered boolean not null default false,
 fingerprint text generated always as (md5(original_file_base64)) stored,
 foreign key(ring_id,source) references public.rabbit_register_sources(ring_id,source) on delete cascade,
 unique(ring_id,source,fingerprint)
);
alter table public.rabbit_register_files enable row level security;
revoke all on public.rabbit_register_files from public,anon,authenticated;
grant select,insert on public.rabbit_register_files to authenticated;
grant all on public.rabbit_register_files to service_role;
create policy rr_file_read on public.rabbit_register_files for select to authenticated using(exists(select 1 from public.rabbit_register_sources s where s.ring_id=rabbit_register_files.ring_id and s.source=rabbit_register_files.source));
create policy rr_file_add on public.rabbit_register_files for insert to authenticated with check(exists(select 1 from public.rabbit_register_sources s where s.ring_id=rabbit_register_files.ring_id and s.source=rabbit_register_files.source));

create table public.herd_contacts (
 id uuid primary key default gen_random_uuid(), ring_id uuid not null references public.farms(id) on delete cascade,
 source text not null, source_id text not null, name text not null default '', rabbitry text not null default '',
 email text not null default '', phone text not null default '', address text not null default '',
 city text not null default '', state text not null default '', zip text not null default '', country text not null default '',
 raw jsonb not null default '{}', unique(ring_id,source,source_id)
);
alter table public.rabbit_register_records add column native_weight_id uuid references public.animal_weights(id) on delete set null;
grant update(native_weight_id) on public.rabbit_register_records to authenticated;
create index rabbit_register_native_weight on public.rabbit_register_records(native_weight_id);

alter table public.animal_sales add column buyer_contact_id uuid references public.herd_contacts(id) on delete set null;
create index sales_buyer_contact on public.animal_sales(buyer_contact_id);

create table public.animal_management (
 animal_id uuid primary key references public.animals(id) on delete cascade,
 cage text not null default '' check(length(cage)<=100), custom_fields jsonb not null default '{}' check(jsonb_typeof(custom_fields)='object' and octet_length(custom_fields::text)<=20000),
 death_date date, sale_date date, purchase_date date, asking_cents bigint check(asking_cents between 0 and 99999999999),
 purchase_cents bigint check(purchase_cents between 0 and 99999999999),
 buyer_contact_id uuid references public.herd_contacts(id) on delete set null,
 seller_contact_id uuid references public.herd_contacts(id) on delete set null,
 revision integer not null default 1,
 check(death_date>=date '1800-01-01'), check(sale_date>=date '1800-01-01'), check(purchase_date>=date '1800-01-01')
);
create index animal_management_buyer on public.animal_management(buyer_contact_id);
create index animal_management_seller on public.animal_management(seller_contact_id);
alter table public.users add column rabbitry_name text not null default '';

-- A historical litter can have an unknown breeding date or sire. No invented parent/date.
alter table public.breeding_records alter column sire_id drop not null;
alter table public.breeding_records alter column breeding_date drop not null;
alter table public.breeding_records add column import_source text, add column import_ring_id uuid references public.farms(id) on delete cascade,
 add column import_source_id text, add column import_record jsonb;
alter table public.breeding_records add constraint breeding_import_identity check(
 (import_source is null and import_ring_id is null and import_source_id is null and import_record is null and sire_id is not null and breeding_date is not null)
 or (import_source is not null and import_ring_id is not null and import_source_id is not null and jsonb_typeof(import_record)='object'));
alter table public.breeding_records drop constraint breeding_records_sire_id_dam_id_breeding_date_key;
create unique index breeding_manual_identity on public.breeding_records(sire_id,dam_id,breeding_date) where import_source is null;
create unique index breeding_import_identity on public.breeding_records(import_ring_id,import_source,import_source_id) where import_source is not null;
create policy imported_breeding_read on public.breeding_records for select to authenticated using(
 import_source is not null and exists(select 1 from public.farms f where f.id=import_ring_id and breeder_private.has_access(f.owner_id)));
create policy imported_breeding_add on public.breeding_records for insert to authenticated with check(
 import_source is not null and exists(select 1 from public.farms f join public.animals d on d.id=breeding_records.dam_id and d.ring_id=f.id
 where f.id=import_ring_id and not coalesce(f.is_demo,false) and breeder_private.owns(f.owner_id))
 and (sire_id is null or exists(select 1 from public.animals s where s.id=breeding_records.sire_id and s.ring_id=breeding_records.import_ring_id and s.sex='Buck'))
 and exists(select 1 from public.animals d where d.id=breeding_records.dam_id and d.sex='Doe'));
alter table public.breeding_tracking add column import_record jsonb, add column born_total integer check(born_total between 0 and 100), add column recorded_deaths integer check(recorded_deaths between 0 and 100);
alter table public.breeding_tracking
 add column paired_date date, add column split_date date, add column scheduled_breeding_date date,
 add column breeding_occurred boolean, add column nest_installed boolean, add column nest_removed boolean,
 add column rebreeding_enabled boolean, add column rebreeding_overridden boolean,
 add column cage text not null default '' check(length(cage)<=100),
 add column breed_label text not null default '' check(length(breed_label)<=100),
 add column palpation_source text,
 add column added integer check(added between 0 and 100), add column raised integer check(raised between 0 and 100),
 add column bucks integer check(bucks between 0 and 100), add column does integer check(does between 0 and 100),
 add column kept integer check(kept between 0 and 100), add column sold integer check(sold between 0 and 100),
 add column show_quality integer check(show_quality between 0 and 100),
 add column custom_fields jsonb not null default '{}' check(jsonb_typeof(custom_fields)='object' and octet_length(custom_fields::text)<=20000);
alter table public.breeding_tracking add constraint tracking_import_record_object check(import_record is null or (jsonb_typeof(import_record)='object' and octet_length(import_record::text)<=100000));
-- Keep original counts even when the source omitted an event date. Manual tracking stays strict.
do $$declare c record; begin
 for c in select conname,pg_get_constraintdef(oid) def from pg_constraint where conrelid='public.breeding_tracking'::regclass and contype='c'
 and (pg_get_constraintdef(oid) like '%birth_date IS NULL%' or pg_get_constraintdef(oid) like '%wean_date IS NULL%' or pg_get_constraintdef(oid) like '%check_date IS NOT NULL%' or conname='litter_sex_counts') loop
  execute format('alter table public.breeding_tracking drop constraint %I',c.conname);
  execute format('alter table public.breeding_tracking add constraint %I check (import_record is not null or (%s))',c.conname,replace(substring(c.def from 8 for length(c.def)-8),'weaned <= born_alive','weaned <= born_alive + COALESCE(added, 0)'));
 end loop;
end $$;

create table public.litter_weights (
 id uuid primary key default gen_random_uuid(), breeding_id uuid not null references public.breeding_records(id) on delete cascade,
 weight numeric check(weight>0 and weight<1000), feed_weight numeric check(feed_weight>=0 and feed_weight<1000000), recorded_date date not null check(recorded_date>=date '1800-01-01'),
 notes text not null default '', import_source text, import_source_id text, unique(breeding_id,import_source,import_source_id), check(weight is not null or feed_weight is not null)
);
create index litter_weights_breeding on public.litter_weights(breeding_id,recorded_date);
create table public.animal_feed_weights (
 id uuid primary key default gen_random_uuid(), animal_id uuid not null references public.animals(id) on delete cascade,
 recorded_date date not null check(recorded_date>=date '1800-01-01'),
 weight numeric check(weight>0 and weight<1000), feed_weight numeric check(feed_weight>=0 and feed_weight<1000000),
 notes text not null default '', revision integer not null default 1,
 import_source text, import_source_id text, native_weight_id uuid references public.animal_weights(id) on delete set null,
 unique(animal_id,import_source,import_source_id), check(weight is not null or feed_weight is not null)
);
create index animal_feed_parent on public.animal_feed_weights(animal_id,recorded_date);
alter table public.animal_feed_weights enable row level security;
revoke all on public.animal_feed_weights from public,anon,authenticated;
grant select,insert on public.animal_feed_weights to authenticated;
grant update(recorded_date,weight,feed_weight,notes,revision,native_weight_id) on public.animal_feed_weights to authenticated;
grant all on public.animal_feed_weights to service_role;
create policy animal_feed_read on public.animal_feed_weights for select to authenticated using(breeder_private.animal_access(animal_id));
create policy animal_feed_add on public.animal_feed_weights for insert to authenticated with check(breeder_private.animal_access(animal_id) and recorded_date<=current_date);
create policy animal_feed_edit on public.animal_feed_weights for update to authenticated using(breeder_private.animal_access(animal_id)) with check(breeder_private.animal_access(animal_id) and recorded_date<=current_date);
create table public.animal_wool_records (
 id uuid primary key default gen_random_uuid(), animal_id uuid not null references public.animals(id) on delete cascade,
 recorded_date date check(recorded_date>=date '1800-01-01'), fleece_grams numeric check(fleece_grams>0 and fleece_grams<1000000),
 measurements jsonb not null default '{}' check(jsonb_typeof(measurements)='object' and octet_length(measurements::text)<=50000),
 notes text not null default '', import_source text, import_source_id text, native_weight_id uuid references public.animal_weights(id) on delete set null, unique(animal_id,import_source,import_source_id)
);
create index animal_wool_animal on public.animal_wool_records(animal_id,recorded_date);
alter table public.rabbit_register_records add column native_wool_id uuid references public.animal_wool_records(id) on delete set null;
create index rabbit_register_native_wool on public.rabbit_register_records(native_wool_id) where native_wool_id is not null;
grant update(native_wool_id) on public.rabbit_register_records to authenticated;

alter table public.herd_contacts enable row level security;
alter table public.animal_management enable row level security;
alter table public.litter_weights enable row level security;
alter table public.animal_wool_records enable row level security;
revoke all on public.herd_contacts,public.animal_management,public.litter_weights,public.animal_wool_records from public,anon,authenticated;
grant select,insert,update on public.herd_contacts,public.animal_management to authenticated;
grant select,insert on public.litter_weights,public.animal_wool_records to authenticated;
grant all on public.herd_contacts,public.animal_management,public.litter_weights,public.animal_wool_records to service_role;
create policy contacts_access on public.herd_contacts for all to authenticated
 using(exists(select 1 from public.farms f where f.id=ring_id and not coalesce(f.is_demo,false) and breeder_private.has_access(f.owner_id)))
 with check(exists(select 1 from public.farms f where f.id=ring_id and not coalesce(f.is_demo,false) and breeder_private.has_access(f.owner_id)));
create policy management_access on public.animal_management for all to authenticated
 using(breeder_private.animal_access(animal_id)) with check(breeder_private.animal_access(animal_id)
 and (buyer_contact_id is null or exists(select 1 from public.herd_contacts c join public.animals a on a.id=animal_id where c.id=buyer_contact_id and c.ring_id=a.ring_id))
 and (seller_contact_id is null or exists(select 1 from public.herd_contacts c join public.animals a on a.id=animal_id where c.id=seller_contact_id and c.ring_id=a.ring_id)));
create policy litter_weight_read on public.litter_weights for select to authenticated using(exists(select 1 from public.breeding_records b where b.id=breeding_id));
create policy litter_weight_add on public.litter_weights for insert to authenticated with check(recorded_date<=current_date and exists(select 1 from public.breeding_records b where b.id=breeding_id));
create policy wool_read on public.animal_wool_records for select to authenticated using(breeder_private.animal_access(animal_id));
create policy wool_add on public.animal_wool_records for insert to authenticated with check(breeder_private.animal_access(animal_id) and (recorded_date is null or recorded_date<=current_date));

-- Import show entries into the same history consumed by show screens and pedigrees.
grant insert on public.breeder_show_history to authenticated;
create policy rabbit_register_show_add on public.breeder_show_history for insert to authenticated with check(
 source_app='rabbit_register' and breeder_private.owns(owner_id) and
 (animal_id is null or exists(select 1 from public.animals a join public.farms f on f.id=a.ring_id where a.id=animal_id and f.owner_id=breeder_show_history.owner_id)));

create function public.rabbit_register_date(value text) returns date language plpgsql immutable set search_path='' as $$
declare d date;
begin
 if value is null or btrim(value)='' or value in ('0100-01-01','0100-01-02','0100-01-03','2100-12-12') then return null; end if;
 d:=value::date; if d<date '1800-01-01' then return null; end if; return d;
exception when others then return null;
end $$;
create function public.rabbit_register_number(value text) returns numeric language plpgsql immutable set search_path='' as $$
begin
 if value is null or value !~ '^-?[0-9]+(\.[0-9]+)?$' then return null; end if; return value::numeric;
end $$;
create function public.save_animal_management(p_animal uuid,p_data jsonb,p_revision integer default 0) returns void
language plpgsql security invoker set search_path='' as $$
declare rev integer;
begin
 perform 1 from public.animals where id=p_animal for update;
 if not found or not breeder_private.animal_access(p_animal) then raise exception 'Animal access denied'; end if;
 select revision into rev from public.animal_management where animal_id=p_animal;
 if coalesce(rev,0)<>p_revision then raise exception 'These details changed. Refresh before saving.'; end if;
 if public.rabbit_register_date(p_data->>'death_date')>current_date or public.rabbit_register_date(p_data->>'sale_date')>current_date or public.rabbit_register_date(p_data->>'purchase_date')>current_date then raise exception 'Event dates cannot be in the future'; end if;
 insert into public.animal_management(animal_id,cage,custom_fields,death_date,sale_date,purchase_date,purchase_cents,buyer_contact_id,seller_contact_id,revision)
 values(p_animal,coalesce(p_data->>'cage',''),coalesce(p_data->'custom_fields','{}'),nullif(p_data->>'death_date','')::date,nullif(p_data->>'sale_date','')::date,nullif(p_data->>'purchase_date','')::date,nullif(p_data->>'purchase_cents','')::bigint,nullif(p_data->>'buyer_contact_id','')::uuid,nullif(p_data->>'seller_contact_id','')::uuid,p_revision+1)
 on conflict(animal_id) do update set cage=excluded.cage,custom_fields=excluded.custom_fields,death_date=excluded.death_date,sale_date=excluded.sale_date,purchase_date=excluded.purchase_date,purchase_cents=excluded.purchase_cents,buyer_contact_id=excluded.buyer_contact_id,seller_contact_id=excluded.seller_contact_id,revision=excluded.revision;
end $$;

create function public.rabbit_register_flag(value text) returns boolean language sql immutable set search_path='' as $$
 select case lower(btrim(value)) when 'true' then true when 'false' then false end
$$;
create function public.rabbit_register_count(value text) returns integer language sql immutable set search_path='' as $$
 select case when value ~ '^[0-9]{1,3}$' and value::numeric between 0 and 100 then value::integer end
$$;
create function public.link_rabbit_register_history(p_ring uuid,p_source text,p_commit boolean default false,p_updates jsonb default '[]')
returns jsonb language plpgsql security invoker set search_path='' as $$
#variable_conflict use_variable
declare owner text; r record; a record; raw jsonb; x jsonb; custom jsonb; aid uuid; bid uuid; buyer uuid; seller uuid;
 dt date; wt numeric; fw numeric; amount numeric; cnt integer:=0; notices jsonb:='[]'; identities jsonb:='{}';
begin
 select owner_id into owner from public.farms f where f.id=p_ring and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false) for update;
 if owner is null then raise exception 'Select a herd you own'; end if;
 p_source:=lower(btrim(p_source));
 if not exists(select 1 from public.rabbit_register_sources where ring_id=p_ring and source=p_source) then raise exception 'Source not found'; end if;
 if not coalesce(p_commit,false) then
  return jsonb_build_object('status','preview','contacts',(select count(*) from public.rabbit_register_records where ring_id=p_ring and source=p_source and kind='contact'),
  'litters',(select count(*) from public.rabbit_register_records where ring_id=p_ring and source=p_source and kind='litter'),
  'shows',(select count(*) from public.rabbit_register_records where ring_id=p_ring and source=p_source and kind='show'),
  'message','Add these retained records to contacts, animal details, litter tracking, shows and sales. Repeating this step does not duplicate source records.');
 end if;
 select coalesce(jsonb_object_agg(source_id,animal_id),'{}') into identities from public.rabbit_register_animals where ring_id=p_ring and source=p_source;
 for r in select * from public.rabbit_register_records where ring_id=p_ring and source=p_source and kind='contact' loop
  raw:=r.record->'raw';
  insert into public.herd_contacts(ring_id,source,source_id,name,rabbitry,email,phone,address,city,state,zip,country,raw)
  values(p_ring,p_source,r.source_id,btrim(concat_ws(' ',raw->>'FirstName',raw->>'LastName')),coalesce(raw->>'Rabbitry',''),coalesce(raw->>'Email',''),coalesce(raw->>'Phone0',''),concat_ws(E'\n',nullif(raw->>'Address0',''),nullif(raw->>'Address1','')),coalesce(raw->>'City',''),coalesce(raw->>'State',''),coalesce(raw->>'Zip',raw->>'ZIP',''),coalesce(raw->>'Country',''),raw) on conflict do nothing;
 end loop;
 for a in select * from public.rabbit_register_animals where ring_id=p_ring and source=p_source loop
  raw:=a.raw;
  -- Supplemental export fields can fill gaps without replacing the first snapshot.
  for x in select value from jsonb_array_elements(p_updates) where value->>'source_id'=a.source_id loop
   if coalesce(x->'raw'->>'Name','')=coalesce(a.raw->>'Name','') and coalesce(x->'raw'->>'Breed','')=coalesce(a.raw->>'Breed','') and coalesce(x->'raw'->>'Ear_Num','')=coalesce(a.raw->>'Ear_Num','') then raw:=raw||(x->'raw'); end if;
  end loop;
  buyer:=null;seller:=null;
  select id into buyer from public.herd_contacts where ring_id=p_ring and source=p_source and source_id=raw->>'BuyerKey';
  select id into seller from public.herd_contacts where ring_id=p_ring and source=p_source and source_id=raw->>'SellerKey';
  if raw ? 'BuyerKey' and raw->>'BuyerKey'<>'0' and buyer is null then notices:=notices||jsonb_build_array('Rabbit '||a.source_id||': buyer contact is missing.'); end if;
  if raw ? 'SellerKey' and raw->>'SellerKey'<>'0' and seller is null then notices:=notices||jsonb_build_array('Rabbit '||a.source_id||': seller contact is missing.'); end if;
  select coalesce(jsonb_object_agg(key,value),'{}') into custom from jsonb_each(raw)
   where key not in ('CID','Breed','Storage_Area','Ear_Num','Ear_Number','Name','Sex','Variety','Reg_','Legs','Grand_Ch.__Num','Grand_Ch_Num','SireKey','DamKey','Weight','DOB','DOBTag','DOD','DODTag','DateSold','DateBought','DateWeaned','Comments','Cage','BuyerKey','SellerKey','AmountPaid','ForSalePrice','ForSalePprice','SoldFor');
  amount:=public.rabbit_register_number(raw->>'AmountPaid')*100;
  insert into public.animal_management(animal_id,cage,custom_fields,death_date,sale_date,purchase_date,purchase_cents,buyer_contact_id,seller_contact_id)
  values(a.animal_id,coalesce(raw->>'Cage',''),custom,public.rabbit_register_date(raw->>'DOD'),public.rabbit_register_date(raw->>'DateSold'),public.rabbit_register_date(raw->>'DateBought'),case when amount between 0 and 99999999999 then round(amount)::bigint end,buyer,seller)
  on conflict(animal_id) do update set cage=coalesce(nullif(public.animal_management.cage,''),excluded.cage),
  custom_fields=excluded.custom_fields||public.animal_management.custom_fields,
  death_date=coalesce(public.animal_management.death_date,excluded.death_date),sale_date=coalesce(public.animal_management.sale_date,excluded.sale_date),
  purchase_date=coalesce(public.animal_management.purchase_date,excluded.purchase_date),purchase_cents=coalesce(public.animal_management.purchase_cents,excluded.purchase_cents),
  buyer_contact_id=coalesce(public.animal_management.buyer_contact_id,excluded.buyer_contact_id),seller_contact_id=coalesce(public.animal_management.seller_contact_id,excluded.seller_contact_id),revision=public.animal_management.revision+1;
  if public.rabbit_register_number(raw->>'ForSalePrice')*100 between 0 and 99999999999 then
   update public.animal_management set asking_cents=round(public.rabbit_register_number(raw->>'ForSalePrice')*100)::bigint where animal_id=a.animal_id and asking_cents is null;
  end if;
  dt:=public.rabbit_register_date(raw->>'DateSold');amount:=public.rabbit_register_number(raw->>'SoldFor')*100;
  if dt is not null or buyer is not null or amount is not null then
   insert into public.animal_sales(animal_id,ring_id,animal_name,status,asking_cents,sale_cents,sale_date,buyer_contact_id,buyer_name,buyer_email,buyer_phone,buyer_address,notes,import_source,import_source_account,import_source_id,import_record,payment_history_complete)
   select a.animal_id,p_ring,'','sold',case when public.rabbit_register_number(raw->>'ForSalePrice')*100 between 0 and 99999999999 then round(public.rabbit_register_number(raw->>'ForSalePrice')*100)::bigint end,
    case when amount between 0 and 99999999999 then round(amount)::bigint end,dt,buyer,coalesce(nullif(c.name,''),c.rabbitry,''),coalesce(c.email,''),coalesce(c.phone,''),concat_ws(', ',c.address,c.city,c.state,c.zip),
    'Imported Rabbit Register sale. Payment history was not supplied.','rabbit_register',p_source,a.source_id,raw,false
   from (select 1) seed left join public.herd_contacts c on c.id=buyer on conflict do nothing;
  end if;
 end loop;
 for r in select * from public.rabbit_register_records where ring_id=p_ring and source=p_source and kind='litter' loop
  raw:=r.record->'raw'; bid:=null;
  if r.animal_id is null or not exists(select 1 from public.animals d where d.id=r.animal_id and d.sex='Doe') then notices:=notices||jsonb_build_array('Litter '||r.source_id||': dam is missing or has the wrong sex; retained in source history.');continue;end if;
  aid:=r.sire_id;
  if aid is not null and not exists(select 1 from public.animals s where s.id=aid and s.sex='Buck') then aid:=null;end if;
  insert into public.breeding_records(sire_id,dam_id,breeding_date,notes,status,import_source,import_ring_id,import_source_id,import_record)
  values(aid,r.animal_id,public.rabbit_register_date(raw->>'DATEBRED'),left(coalesce(raw->>'COMMENTS',''),4000),case when raw->>'REMOVELITTERCOMPLETE'='True' then 'completed' else 'active' end,p_source,p_ring,r.source_id,raw) on conflict do nothing;
  select id into bid from public.breeding_records where import_ring_id=p_ring and import_source=p_source and import_source_id=r.source_id;
  select coalesce(jsonb_object_agg(key,value),'{}') into custom from jsonb_each(raw)
   where key not in ('ID','DATEBRED','DATEBORN','DATEWEANED','SIREIDKEY','DAMIDKEY','NUMBERBORN','NUMBERWEANED','DIED','COMMENTS','DATEPAIRED','DATESPLIT','SCHEDULEDBREEDINGDATE','BREEDINGOCCURRED','PALPATERESULTS','INSTALLNESTBOXCOMPLETE','REMOVENESTBOXCOMPLETE','REMOVELITTERCOMPLETE','REBREEDINGENABLED','REBREEDINGOVERRIDDEN','BREEDNAMEDECODED','CAGE','BUCKS','DOES','ADDED','RAISED','KEPT','SOLD','SHOWQUALITY');
  insert into public.breeding_tracking(breeding_id,birth_date,born_total,recorded_deaths,wean_date,weaned,status,notes,import_record,
   paired_date,split_date,scheduled_breeding_date,breeding_occurred,nest_installed,nest_removed,rebreeding_enabled,rebreeding_overridden,
   cage,breed_label,palpation_source,added,raised,bucks,does,kept,sold,show_quality,custom_fields)
  values(bid,public.rabbit_register_date(raw->>'DATEBORN'),public.rabbit_register_count(raw->>'NUMBERBORN'),public.rabbit_register_count(raw->>'DIED'),
   public.rabbit_register_date(raw->>'DATEWEANED'),public.rabbit_register_count(raw->>'NUMBERWEANED'),
   case when raw->>'REMOVELITTERCOMPLETE'='True' then 'completed' else 'active' end,left(coalesce(raw->>'COMMENTS',''),4000),raw,
   public.rabbit_register_date(raw->>'DATEPAIRED'),public.rabbit_register_date(raw->>'DATESPLIT'),public.rabbit_register_date(raw->>'SCHEDULEDBREEDINGDATE'),
   public.rabbit_register_flag(raw->>'BREEDINGOCCURRED'),public.rabbit_register_flag(raw->>'INSTALLNESTBOXCOMPLETE'),public.rabbit_register_flag(raw->>'REMOVENESTBOXCOMPLETE'),
   public.rabbit_register_flag(raw->>'REBREEDINGENABLED'),public.rabbit_register_flag(raw->>'REBREEDINGOVERRIDDEN'),
   left(coalesce(raw->>'CAGE',''),100),left(coalesce(raw->>'BREEDNAMEDECODED',''),100),raw->>'PALPATERESULTS',
   public.rabbit_register_count(raw->>'ADDED'),public.rabbit_register_count(raw->>'RAISED'),public.rabbit_register_count(raw->>'BUCKS'),public.rabbit_register_count(raw->>'DOES'),
   public.rabbit_register_count(raw->>'KEPT'),public.rabbit_register_count(raw->>'SOLD'),public.rabbit_register_count(raw->>'SHOWQUALITY'),custom) on conflict do nothing;
  -- DIED includes later deaths, so it must not be relabelled as stillborn.
 end loop;
 for r in select * from public.rabbit_register_records where ring_id=p_ring and source=p_source loop
  raw:=r.record->'raw';
  if r.kind='show' then
   select * into a from public.animals where id=r.animal_id;
   insert into public.breeder_show_history(owner_id,source_app,source_entry_id,animal_id,exhibitor_source_id,record)
   values(owner,'rabbit_register',md5(jsonb_build_array(p_ring,p_source,'show',r.source_id)::text)::uuid,r.animal_id,md5(owner)::uuid,
   jsonb_build_object('animal_name',coalesce(a.name,''),'tattoo',coalesce(a.tattoo,''),'breed',coalesce(a.breed,''),'variety',coalesce(a.variety,''),'sex',coalesce(a.sex,''),
   'shows',jsonb_build_object('name',raw->>'ShowName','start_date',public.rabbit_register_date(raw->>'ShowDate'),'location',raw->>'Location'),
   'placement',raw->>'RankInClass','special_awards',coalesce(raw->>'WINS',''),'judge',raw->>'Judge','is_leg',raw->>'IsALeg'='True','is_youth',raw->>'IsAYouthShow'='True',
   'number_in_class',raw->>'NumberInClass','number_of_exhibitors',raw->>'NumberOfExhibitors','total_shown',raw->>'TotalShown','comments',raw->>'Comments','other_winnings',raw->>'OtherWinnings','date_qualifier',raw->>'ShowDateTag','pedigree_rank',raw->>'Rank','source','Rabbit Register','raw',raw)) on conflict do nothing;
  elsif r.kind='weight' and r.animal_id is not null then
   dt:=(r.record->>'recorded_date')::date;wt:=(r.record->>'weight')::numeric;fw:=public.rabbit_register_number(raw->>'FEEDWT')/453.592;aid:=r.native_weight_id;
   if dt is not null and dt<=current_date and dt>=date '1800-01-01' then
    if aid is null and wt>0 and wt<1000 then
     select id into aid from public.animal_weights where animal_id=r.animal_id and weight=wt and (recorded_at at time zone 'UTC')::date=dt order by id limit 1;
     if aid is null then
      insert into public.animal_weights(animal_id,weight,recorded_at) values(r.animal_id,wt,(dt::text||'T12:00:00Z')::timestamptz) returning id into aid;
     end if;
     update public.rabbit_register_records set native_weight_id=aid where ring_id=p_ring and source=p_source and kind='weight' and source_id=r.source_id;
    end if;
    if wt>0 or fw>=0 then
     insert into public.animal_feed_weights(animal_id,recorded_date,weight,feed_weight,native_weight_id,import_source,import_source_id)
      values(r.animal_id,dt,case when wt>0 and wt<1000 then wt end,case when fw>=0 and fw<1000000 then fw end,aid,p_source,r.source_id) on conflict do nothing;
    end if;
   end if;
  elsif r.kind='litter_weight' then
   dt:=public.rabbit_register_date(raw->>'WEIGHINGDATE');wt:=public.rabbit_register_number(raw->>'LITTERWT')/453.592;fw:=public.rabbit_register_number(raw->>'FEEDWT')/453.592;bid:=null;
   select id into bid from public.breeding_records where import_ring_id=p_ring and import_source=p_source and import_source_id=raw->>'LITTERKEY';
   if bid is not null and dt is not null and (wt>0 and wt<1000 or fw>=0 and fw<1000000) then
    insert into public.litter_weights(breeding_id,weight,feed_weight,recorded_date,import_source,import_source_id) values(bid,case when wt>0 and wt<1000 then wt end,case when fw>=0 and fw<1000000 then fw end,dt,p_source,r.source_id) on conflict do nothing;
   else notices:=notices||jsonb_build_array('Litter weight '||r.source_id||': missing litter, date or usable measurement; retained in source history.');end if;
  elsif r.kind='wool' and r.animal_id is not null and r.native_wool_id is null then
   wt:=public.rabbit_register_number(raw->>'FLEECEWT');
   insert into public.animal_wool_records(animal_id,recorded_date,fleece_grams,measurements,notes,import_source,import_source_id)
   values(r.animal_id,case when public.rabbit_register_date(raw->>'SHEARDATE')<=current_date then public.rabbit_register_date(raw->>'SHEARDATE') end,case when wt>0 and wt<1000000 then wt end,raw,coalesce(raw->>'COMMENTS',''),p_source,r.source_id) on conflict do nothing;
   select id into aid from public.animal_wool_records where animal_id=r.animal_id and import_source=p_source and import_source_id=r.source_id;
   update public.rabbit_register_records set native_wool_id=aid where ring_id=p_ring and source=p_source and kind='wool' and source_id=r.source_id;
  elsif r.kind='wool' and r.native_wool_id is null then
   notices:=notices||jsonb_build_array('Wool record '||r.source_id||': rabbit reference needs review. Link it from source history.');
  end if;
 end loop;
 return jsonb_build_object('status','linked','warnings',notices);
end $$;

alter table public.animal_sales drop constraint animal_sales_import_source_check;
alter table public.animal_sales add constraint animal_sales_import_source_check check(
 (import_source is null and import_source_account is null and import_source_id is null and import_record is null)
 or (import_source in ('global_pedigree','rabbit_register') and import_source_account is not null and length(import_source_account) between 1 and 200
 and import_source_id is not null and length(import_source_id) between 1 and 200 and jsonb_typeof(import_record)='object' and octet_length(import_record::text)<=50000 and status='sold'));
create or replace function breeder_private.sales_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare a public.animals; paid bigint; owner text;
begin
 select f.owner_id into owner from public.farms f where f.id=new.ring_id and not coalesce(f.is_demo,false);
 if auth.uid() is null or not coalesce(breeder_private.has_access(owner),false) then raise exception 'Sales access denied'; end if;
 if new.buyer_contact_id is not null and not exists(select 1 from public.herd_contacts c where c.id=new.buyer_contact_id and c.ring_id=new.ring_id) then raise exception 'Buyer contact must belong to this herd';end if;
 if new.import_source is not null and (new.import_source not in ('global_pedigree','rabbit_register') or nullif(btrim(new.import_source_account),'') is null or nullif(btrim(new.import_source_id),'') is null or new.status<>'sold') then raise exception 'Invalid historical sale source'; end if;
 if tg_op='INSERT' then
  select * into a from public.animals where id=new.animal_id for update;
  if a.id is null or a.ring_id<>new.ring_id then raise exception 'Choose an animal in this herd'; end if;
  if new.import_source is null and (a.status<>'active' or coalesce(a.pedigree_only,false)) then raise exception 'Choose an active herd animal'; end if;
  if new.import_source is not null and not coalesce(breeder_private.owns(owner),false) then raise exception 'Only the herd owner can import historical sales'; end if;
  new.animal_name=concat_ws(' - ',nullif(a.name,''),nullif(a.tattoo,''));
  if new.animal_name='' then new.animal_name='Unnamed animal'; end if;
  new.version=1;new.created_at=now();
 else
  if new.id<>old.id or new.animal_id<>old.animal_id or new.ring_id<>old.ring_id or new.created_at<>old.created_at then raise exception 'Sale identity cannot change'; end if;
  if new.import_source is distinct from old.import_source or new.import_source_account is distinct from old.import_source_account or new.import_source_id is distinct from old.import_source_id or new.import_record is distinct from old.import_record then raise exception 'Imported sale identity cannot change'; end if;
  new.animal_name=old.animal_name;
  if old.status='sold' and new.status<>'sold' then raise exception 'Completed sales remain in history'; end if;
  if old.status='cancelled' then raise exception 'Cancelled listings are read-only; create a new listing'; end if;
  new.version=old.version+1;
 end if;
 select coalesce(sum(case when kind='refund' then -amount_cents else amount_cents end),0) into paid from public.animal_sale_payments where sale_id=new.id;
 if paid>0 and (coalesce(new.sale_cents,new.asking_cents) is null or paid>coalesce(new.sale_cents,new.asking_cents)) then raise exception 'Price cannot be below payments received'; end if;
 -- Only current listings participate; imported history and completed sales stay unchanged.
 if new.import_source is null and new.status in ('for_sale','reserved')
    and nullif(btrim(new.buyer_name),'') is not null then
  if new.sale_cents is not null and new.sale_cents>0 and paid=new.sale_cents then
   new.status='sold';
   new.sale_date=coalesce(new.sale_date,(select max(paid_on) from public.animal_sale_payments where sale_id=new.id),current_date);
  else
   new.status='reserved';
  end if;
 end if;
 if new.status='cancelled' and paid<>0 then raise exception 'Record refunds before cancelling this sale'; end if;
 if new.import_source is null and new.status in ('reserved','sold') and trim(new.buyer_name)='' then raise exception 'Enter the buyer name'; end if;
 if new.import_source is null and new.status='sold' and (new.sale_cents is null or new.sale_date is null or new.sale_date>current_date) then raise exception 'Enter a sale price and sale date that is not in the future'; end if;
 if length(new.buyer_name)>500 or length(new.buyer_email)>500 or length(new.buyer_phone)>100 or length(new.buyer_address)>2000 or length(new.notes)>10000 then raise exception 'Sale details are too long'; end if;
 if new.import_source is not null and new.sale_date>current_date then raise exception 'Historical sale date cannot be in the future'; end if;
 new.updated_at=clock_timestamp();return new;
end $$;

create or replace function public.import_rabbit_register(p_ring uuid,p_source text,p_data jsonb,p_commit boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
#variable_conflict use_variable
declare
 animals jsonb:=p_data->'animals'; records jsonb:=p_data->'records';
 nodes jsonb:='{}'; ids jsonb:='{}'; fresh jsonb:='{}'; rows jsonb:='[]';
 issues jsonb:='[]'; warnings jsonb:='[]'; candidates jsonb; prior public.rabbit_register_animals;
 n jsonb; r jsonb; sid text; parent text; side text; kind text; k text;
 aid uuid; sire uuid; dt date; chosen text; added int:=0; existing int:=0; history_added int:=0;
 seen text[]:='{}'; done text[]:='{}'; visiting text[]:='{}'; frames jsonb; frame jsonb; current_key text;
begin
 if auth.uid() is null then raise exception 'Sign in to import'; end if;
 perform 1 from public.farms f where f.id=p_ring and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false) for update;
 if not found then raise exception 'Select a herd you own'; end if;
 p_source:=lower(btrim(p_source));
 if p_source is null or length(p_source) not between 1 and 120 then raise exception 'Name the source Rabbit Register database'; end if;
 if jsonb_typeof(animals) is distinct from 'array' or jsonb_typeof(records) is distinct from 'array' then raise exception 'Invalid import data'; end if;
 if jsonb_array_length(animals) not between 1 and 2000 or jsonb_array_length(records)>20000 or octet_length(p_data::text)>35000000 then raise exception 'Import is too large'; end if;
 if coalesce((p_data->>'recovered')::boolean,false) then warnings:=warnings||jsonb_build_array('The XML closing tag was recovered. Additional sections may be missing.'); end if;
 for n in select value from jsonb_array_elements(animals) loop
  sid:=n->>'source_id';
  if jsonb_typeof(n) is distinct from 'object' or sid is null or sid !~ '^[1-9][0-9]{0,9}$' or jsonb_typeof(n->'raw') is distinct from 'object' then raise exception 'Invalid rabbit record'; end if;
  if nodes ? sid then raise exception 'Duplicate source animal ID'; end if;
  if n->>'sex' is null or n->>'sex' not in ('Buck','Doe') then issues:=issues||jsonb_build_array('Rabbit '||sid||' needs Buck or Doe selected.'); end if;
  if nullif(btrim(n->>'name'),'') is null then issues:=issues||jsonb_build_array('Rabbit '||sid||' needs a name.'); end if;
  if n->>'status' is null or n->>'status' not in ('active','archived','sold','deceased') then issues:=issues||jsonb_build_array('Rabbit '||sid||' has an invalid status.'); end if;
  begin
   dt:=nullif(n->>'dob','')::date;
   if dt>current_date or dt<date '1800-01-01' then raise exception 'Invalid date'; end if;
  exception when others then issues:=issues||jsonb_build_array('Rabbit '||sid||' has an invalid birth date.'); end;
  begin
   if nullif(n->>'legs','') is not null and (n->>'legs')::integer<0 then raise exception 'Invalid legs'; end if;
   if nullif(n->>'profile_weight','') is not null and not ((n->>'profile_weight')::numeric>0 and (n->>'profile_weight')::numeric<1000) then raise exception 'Invalid weight'; end if;
  exception when others then issues:=issues||jsonb_build_array('Rabbit '||sid||' has an invalid weight or leg count.'); end;
  nodes:=nodes||jsonb_build_object(sid,n);
 end loop;
 for sid,n in select key,value from jsonb_each(nodes) loop
  foreach side in array array['sire_id','dam_id'] loop
   parent:=nullif(n->>side,'');
   if parent is not null then
    if not nodes ? parent then warnings:=warnings||jsonb_build_array('Rabbit '||sid||' references missing '||side||' '||parent||'. The link will remain empty.');
    elsif nodes->parent->>'sex' is not null and nodes->parent->>'sex' is distinct from (case side when 'sire_id' then 'Buck' else 'Doe' end) then
     issues:=issues||jsonb_build_array('Rabbit '||sid||' has a parent with the wrong sex ('||parent||').');
    end if;
   end if;
  end loop;
 end loop;
 -- Bounded iterative DFS checks all connected components, including ancestors.
 for sid in select key from jsonb_each(nodes) loop
  frames:=jsonb_build_array(jsonb_build_object('id',sid,'exit',false));
  while jsonb_array_length(frames)>0 loop
   frame:=frames->(jsonb_array_length(frames)-1); frames:=frames-(jsonb_array_length(frames)-1); current_key:=frame->>'id';
   if (frame->>'exit')::boolean then visiting:=array_remove(visiting,current_key);done:=array_append(done,current_key);
   elsif current_key=any(visiting) then issues:=issues||jsonb_build_array('Pedigree cycle at rabbit '||current_key||'.');frames:='[]';
   elsif not current_key=any(done) and nodes ? current_key then
    visiting:=array_append(visiting,current_key); frames:=frames||jsonb_build_array(jsonb_build_object('id',current_key,'exit',true));
    foreach side in array array['sire_id','dam_id'] loop
     parent:=nullif(nodes->current_key->>side,'');
     if parent is not null then frames:=frames||jsonb_build_array(jsonb_build_object('id',parent,'exit',false)); end if;
    end loop;
   end if;
  end loop;
 end loop;
 for sid,n in select key,value from jsonb_each(nodes) loop
  aid:=null; chosen:=nullif(n->>'existing_id',''); candidates:='[]';
  select * into prior from public.rabbit_register_animals g where g.ring_id=p_ring and g.source=p_source and g.source_id=sid;
  if found then
   aid:=prior.animal_id;
   -- A reused label must never silently map another breeder's numeric IDs.
   if lower(coalesce(prior.raw->>'Name','')) is distinct from lower(coalesce(n->'raw'->>'Name',''))
    or lower(coalesce(prior.raw->>'Ear_Num','')) is distinct from lower(coalesce(n->'raw'->>'Ear_Num',''))
    or lower(coalesce(prior.raw->>'Breed','')) is distinct from lower(coalesce(n->'raw'->>'Breed','')) then
    issues:=issues||jsonb_build_array('Source ID '||sid||' has changed identity. Check that this is the same Rabbit Register database.');
   elsif prior.raw is distinct from n->'raw' then warnings:=warnings||jsonb_build_array('Rabbit '||sid||' was imported before; its existing details and first source snapshot will be preserved.'); end if;
   if chosen is not null and chosen<>aid::text then issues:=issues||jsonb_build_array('Rabbit '||sid||' already has an import identity.'); end if;
  else
   -- Ear number alone is never sufficient. Require an explicit decision for
   -- every exact candidate; otherwise retain distinct source IDs as distinct rabbits.
   select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'tattoo',a.tattoo,'status',a.status) order by a.id),'[]') into candidates
    from public.animals a where a.ring_id=p_ring and a.species='rabbit'
    and nullif(btrim(n->>'tattoo'),'') is not null and nullif(btrim(n->'raw'->>'Name'),'') is not null
    and lower(btrim(a.tattoo))=lower(btrim(n->>'tattoo')) and lower(btrim(a.name))=lower(btrim(n->>'name'))
    and a.sex=n->>'sex' and public.catalog_key(a.breed) is not distinct from public.catalog_key(n->>'breed')
    and public.catalog_key(a.variety) is not distinct from public.catalog_key(n->>'variety')
    and a.dob::text is not distinct from nullif(n->>'dob','');
   if chosen is not null then
    if not exists(select 1 from jsonb_array_elements(candidates) c where c->>'id'=chosen) then issues:=issues||jsonb_build_array('Rabbit '||sid||' has an invalid existing-animal choice.');
    else aid:=chosen::uuid; end if;
   elsif jsonb_array_length(candidates)>0 and not coalesce((n->>'keep_separate')::boolean,false) then
    issues:=issues||jsonb_build_array('Review existing matches for rabbit '||sid||'.');
   end if;
  end if;
  if aid is null then added:=added+1;else existing:=existing+1;ids:=ids||jsonb_build_object(sid,aid);end if;
  rows:=rows||jsonb_build_array(jsonb_build_object('source_id',sid,'name',n->>'name','action',case when aid is null then 'New rabbit' else 'Existing rabbit preserved' end,'candidates',candidates));
 end loop;
 -- Validate historical measurements before any writes. Other source fields are
 -- retained verbatim; Access's empty-date sentinel is never converted to an event.
 for r in select value from jsonb_array_elements(records) loop
  kind:=r->>'kind';sid:=r->>'source_id';k:=kind||':'||sid;
  if jsonb_typeof(r) is distinct from 'object' or kind is null or kind not in ('contact','show','litter','weight','litter_weight','wool','mileage','picture','growth','finance','journal','sweep') or sid is null or sid !~ '^[1-9][0-9]{0,9}$' or jsonb_typeof(r->'raw') is distinct from 'object' or octet_length(r::text)>100000 then raise exception 'Invalid source history record'; end if;
  if k=any(seen) then raise exception 'Duplicate history source ID'; end if;seen:=array_append(seen,k);
  foreach side in array array['animal_source_id','sire_source_id'] loop
   parent:=nullif(r->>side,'');
   if parent is not null and not nodes ? parent then warnings:=warnings||jsonb_build_array(kind||' '||sid||' references absent rabbit '||parent||'; source history will remain unlinked.'); end if;
  end loop;
  if kind='weight' then
   if nullif(r->>'recorded_date','') is null or coalesce((r->>'weight')::numeric,0)=0 then
    warnings:=warnings||jsonb_build_array('Weight '||sid||' has no positive weight or date; retained in source history only.');
   end if;
   begin
    dt:=(r->>'recorded_date')::date;
    if (dt is not null and (dt>current_date or dt<date '1800-01-01')) or (nullif(r->>'weight','') is not null and not ((r->>'weight')::numeric>=0 and (r->>'weight')::numeric<1000)) then raise exception 'Invalid measurement'; end if;
   exception when others then issues:=issues||jsonb_build_array('Weight '||sid||' needs a valid measurement and date.'); end;
  end if;
 end loop;
 if jsonb_array_length(warnings)>0 and not coalesce((p_data->>'warnings_acknowledged')::boolean,false) then issues:=issues||jsonb_build_array('Acknowledge the source warnings before importing.');end if;
 if not coalesce(p_commit,false) or jsonb_array_length(issues)>0 then
  return jsonb_build_object('status','preview','animals_added',added,'animals_existing',existing,'history_count',jsonb_array_length(records),'issues',issues,'warnings',warnings,'rows',rows);
 end if;
 insert into public.rabbit_register_sources(ring_id,source) values(p_ring,p_source) on conflict do nothing;
 if p_data ? 'original_file_base64' then
  if jsonb_typeof(p_data->'original_file_base64') is distinct from 'string' or octet_length(decode(p_data->>'original_file_base64','base64'))>10485760 or jsonb_typeof(coalesce(p_data->'header','{}')) is distinct from 'object' then raise exception 'Invalid original export';end if;
  insert into public.rabbit_register_files(ring_id,source,filename,original_file_base64,header,recovered)
  values(p_ring,p_source,left(coalesce(nullif(p_data->>'filename',''),'RabbitRegister.XML'),255),p_data->>'original_file_base64',coalesce(p_data->'header','{}'),coalesce((p_data->>'recovered')::boolean,false)) on conflict do nothing;
 end if;
 for sid,n in select key,value from jsonb_each(nodes) loop
  if not ids ? sid then
   insert into public.animals(ring_id,rabbit_register_identity,name,tattoo,species,breed,variety,sex,dob,status,registration_number,grand_champion_number,legs,notes)
    values(p_ring,jsonb_build_array(p_source,sid)::text,n->>'name',nullif(n->>'tattoo',''),'rabbit',nullif(n->>'breed',''),nullif(n->>'variety',''),n->>'sex',nullif(n->>'dob','')::date,'active',nullif(n->>'registration_number',''),nullif(n->>'grand_champion_number',''),nullif(n->>'legs','')::integer,nullif(n->>'notes','')) returning id into aid;
   ids:=ids||jsonb_build_object(sid,aid);fresh:=fresh||jsonb_build_object(sid,true);
  end if;
  insert into public.rabbit_register_animals(ring_id,source,source_id,animal_id,raw,profile_weight,decisions)
   values(p_ring,p_source,sid,(ids->>sid)::uuid,n->'raw',nullif(n->>'profile_weight','')::numeric,jsonb_build_object('sex',n->>'sex','sire_id',n->>'sire_id','dam_id',n->>'dam_id','existing_id',n->>'existing_id')) on conflict do nothing;
 end loop;
 for r in select value from jsonb_array_elements(records) loop
  if exists(select 1 from public.rabbit_register_records h where h.ring_id=p_ring and h.source=p_source and h.kind=r->>'kind' and h.source_id=r->>'source_id') then continue;end if;
  aid:=(ids->>(r->>'animal_source_id'))::uuid;sire:=(ids->>(r->>'sire_source_id'))::uuid;
  insert into public.rabbit_register_records(ring_id,source,kind,source_id,animal_id,sire_id,record)
   values(p_ring,p_source,r->>'kind',r->>'source_id',aid,sire,r);
  -- Existing animal records/weights remain unchanged, even when sold/deceased.
  if r->>'kind'='weight' and aid is not null and fresh ? (r->>'animal_source_id') and (r->>'weight')::numeric>0 and nullif(r->>'recorded_date','') is not null then
   insert into public.animal_weights(animal_id,weight,recorded_at) values(aid,(r->>'weight')::numeric,((r->>'recorded_date')||'T12:00:00Z')::timestamptz);
  end if;
  history_added:=history_added+1;
 end loop;
 -- Set links before final status, respecting normal historical-animal locks.
 for sid,n in select key,value from jsonb_each(nodes) loop
  if fresh ? sid then
   update public.animals set sire_id=(ids->>(n->>'sire_id'))::uuid,dam_id=(ids->>(n->>'dam_id'))::uuid,status=n->>'status' where id=(ids->>sid)::uuid;
  end if;
 end loop;
 candidates:=public.link_rabbit_register_history(p_ring,p_source,true,animals);
 warnings:=warnings||coalesce(candidates->'warnings','[]');
 return jsonb_build_object('status','imported','animals_added',added,'animals_existing',existing,'history_added',history_added,'issues','[]'::jsonb,'warnings',warnings);
end $$;
revoke all on function public.import_rabbit_register(uuid,text,jsonb,boolean) from public,anon;
grant execute on function public.import_rabbit_register(uuid,text,jsonb,boolean) to authenticated;

-- A contact selection changes contact/show details, never login identity or email.
alter table public.breeder_exhibitor_profiles drop constraint breeder_exhibitor_profiles_source_app_check;
alter table public.breeder_exhibitor_profiles add constraint breeder_exhibitor_profiles_source_app_check check(source_app in ('ringmaster_show','ringmaster_club','ringmaster_breeder','rabbit_register'));
grant insert,update on public.breeder_exhibitor_profiles to authenticated;
create policy rr_profile_add on public.breeder_exhibitor_profiles for insert to authenticated with check(source_app='rabbit_register' and breeder_private.owns(owner_id));
create policy rr_profile_edit on public.breeder_exhibitor_profiles for update to authenticated using(source_app='rabbit_register' and breeder_private.owns(owner_id)) with check(source_app='rabbit_register' and breeder_private.owns(owner_id));
create function public.use_herd_contact(p_contact uuid,p_mode text default 'fill',p_show boolean default false)
returns void language plpgsql security invoker set search_path='' as $$
declare c public.herd_contacts; own text;
begin
 select * into c from public.herd_contacts where id=p_contact;
 select owner_id into own from public.farms where id=c.ring_id and breeder_private.owns(owner_id) and not coalesce(is_demo,false) for update;
 if own is null or p_mode not in ('fill','replace','show') then raise exception 'Select a contact from your own herd'; end if;
 if p_mode<>'show' then
 update public.users set
 display_name=case when p_mode='replace' or nullif(btrim(display_name),'') is null then coalesce(nullif(c.name,''),display_name) else display_name end,
 rabbitry_name=case when p_mode='replace' or rabbitry_name='' then coalesce(nullif(c.rabbitry,''),rabbitry_name) else rabbitry_name end,
 phone=case when p_mode='replace' or nullif(btrim(phone),'') is null then coalesce(nullif(c.phone,''),phone) else phone end,
 address=case when p_mode='replace' or nullif(btrim(address),'') is null then coalesce(nullif(c.address,''),address) else address end,
 city=case when p_mode='replace' or nullif(btrim(city),'') is null then coalesce(nullif(c.city,''),city) else city end,
 state=case when p_mode='replace' or nullif(btrim(state),'') is null then coalesce(nullif(c.state,''),state) else state end,
 zip=case when p_mode='replace' or nullif(btrim(zip),'') is null then coalesce(nullif(c.zip,''),zip) else zip end where id=own;
 end if;
 if p_show or p_mode='show' then
 insert into public.breeder_exhibitor_profiles(owner_id,source_app,source_id,profile)
 values(own,'rabbit_register',c.id,jsonb_build_object('display_name',c.name,'showing_name',coalesce(nullif(c.rabbitry,''),c.name),'email',c.email,'phone',c.phone,'address_line1',c.address,'city',c.city,'state',c.state,'zip',c.zip,'country',c.country,'type','individual','is_active',true))
 on conflict(owner_id,source_app,source_id) do update set profile=excluded.profile;
 end if;
end $$;
revoke all on function public.link_rabbit_register_history(uuid,text,boolean,jsonb),public.save_animal_management(uuid,jsonb,integer),public.use_herd_contact(uuid,text,boolean) from public,anon;
grant execute on function public.link_rabbit_register_history(uuid,text,boolean,jsonb),public.save_animal_management(uuid,jsonb,integer),public.use_herd_contact(uuid,text,boolean) to authenticated;
revoke all on function public.rabbit_register_date(text),public.rabbit_register_number(text) from public,anon;
grant execute on function public.rabbit_register_date(text),public.rabbit_register_number(text) to authenticated;

grant update(rabbitry_name) on public.users to authenticated;

create or replace function public.purge_account_data(p_user uuid) returns void
language plpgsql security invoker set search_path='' as $$
declare own text; ids uuid[]; breedings uuid[];
begin
 perform pg_advisory_xact_lock(hashtextextended(p_user::text,0));
 select owner_id into strict own from public.account_deletions where user_id=p_user;
 select coalesce(array_agg(a.id),'{}') into ids from public.animals a join public.farms f on f.id=a.ring_id where f.owner_id=own;
 select coalesce(array_agg(id),'{}') into breedings from public.breeding_records where (sire_id=any(ids) and dam_id=any(ids)) or import_ring_id in(select id from public.farms where owner_id=own);
 delete from public.breeding_offspring where breeding_id=any(breedings) or animal_id=any(ids);
 delete from public.breeding_tracking where breeding_id=any(breedings);
 delete from public.breeding_records where id=any(breedings);
 delete from public.pedigree_drafts where user_id=p_user or ring_id in(select id from public.farms where owner_id=own);
 delete from public.breeding_settings where ring_id in(select id from public.farms where owner_id=own);
 delete from public.connected_show_reports where owner_id=own;
 delete from public.breeder_show_history where owner_id=own;
 delete from public.breeder_imported_animals where owner_id=own;
 delete from public.breeder_exhibitor_profiles where owner_id=own;
 delete from public.show_connections where user_id=p_user;
 delete from public.animal_sales where ring_id in(select id from public.farms where owner_id=own);
 delete from public.animals where id=any(ids);
 delete from public.farms where owner_id=own;
 delete from public.user_licenses where user_id=own;
 delete from breeder_private.invitations where owner_id=own or member_user_id=p_user or email=(select lower(trim(email)) from public.users where auth_user_id=p_user);
 -- Keep the inactive profile until Auth deletes it through its foreign key.
 -- This prevents an interrupted deletion from recreating an empty profile.
end $$;

-- Ongoing management uses the same native rows as the import. Source snapshots
-- remain unchanged, and revisions reject stale edits from another device.
alter table public.herd_contacts add column revision integer not null default 1;
alter table public.breeder_show_history add column revision integer not null default 1;
alter table public.litter_weights add column revision integer not null default 1;
alter table public.animal_wool_records add column revision integer not null default 1;
create function public.save_herd_contact(p_id uuid,p_ring uuid,p_data jsonb,p_revision integer default 0)
returns void language plpgsql security invoker set search_path='' as $$
declare old public.herd_contacts; k text; v text; desired jsonb:='{}';
begin
 perform 1 from public.farms where id=p_ring and not coalesce(is_demo,false) and breeder_private.has_access(owner_id) for update;
 if not found then raise exception 'Herd access denied'; end if;
 select * into old from public.herd_contacts where id=p_id for update;
 if old.id is not null and old.ring_id<>p_ring then raise exception 'Contact identity cannot change'; end if;
 foreach k in array array['name','rabbitry','email','phone','address','city','state','zip','country'] loop
  v:=btrim(coalesce(p_data->>k,''));if length(v)>(case when k='address' then 2000 else 500 end) then raise exception 'Contact field is too long';end if;
  desired:=desired||jsonb_build_object(k,v);
 end loop;
 if coalesce(desired->>'name','')='' and coalesce(desired->>'rabbitry','')='' then raise exception 'Enter a person or rabbitry name'; end if;
 if coalesce(old.revision,0)<>p_revision then
  if old.id is not null and to_jsonb(old) @> desired then return; end if;
  raise exception 'Contact changed. Refresh before saving.';
 end if;
 insert into public.herd_contacts(id,ring_id,source,source_id,name,rabbitry,email,phone,address,city,state,zip,country,revision)
 values(p_id,p_ring,'manual',p_id::text,desired->>'name',desired->>'rabbitry',desired->>'email',desired->>'phone',desired->>'address',desired->>'city',desired->>'state',desired->>'zip',desired->>'country',1)
 on conflict(id) do update set name=excluded.name,rabbitry=excluded.rabbitry,email=excluded.email,phone=excluded.phone,address=excluded.address,city=excluded.city,state=excluded.state,zip=excluded.zip,country=excluded.country,revision=public.herd_contacts.revision+1;
end $$;

grant update on public.breeder_show_history to authenticated;
create policy managed_show_add on public.breeder_show_history for insert to authenticated with check(
 source_app='breeder_manual' and breeder_private.has_access(owner_id) and exists(select 1 from public.animals a join public.farms f on f.id=a.ring_id where a.id=animal_id and f.owner_id=breeder_show_history.owner_id));
create policy managed_show_edit on public.breeder_show_history for update to authenticated
 using(source_app in ('rabbit_register','breeder_manual') and breeder_private.has_access(owner_id))
 with check(source_app in ('rabbit_register','breeder_manual') and breeder_private.has_access(owner_id) and (animal_id is null or exists(select 1 from public.animals a join public.farms f on f.id=a.ring_id where a.id=animal_id and f.owner_id=breeder_show_history.owner_id)));
create function breeder_private.show_identity_guard() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.id<>old.id or new.owner_id<>old.owner_id or new.source_app<>old.source_app or new.source_entry_id<>old.source_entry_id or new.exhibitor_source_id<>old.exhibitor_source_id then raise exception 'Show source identity cannot change';end if;
 new.revision:=old.revision+1;return new;
end $$;
create trigger managed_show_identity before update on public.breeder_show_history for each row execute function breeder_private.show_identity_guard();
revoke all on function breeder_private.show_identity_guard() from public,anon,authenticated;
create function public.save_managed_show_result(p_id uuid,p_animal uuid,p_data jsonb,p_revision integer default 0)
returns void language plpgsql security invoker set search_path='' as $$
declare old public.breeder_show_history; a public.animals; owner text; d date; result jsonb; k text;
begin
 select * into old from public.breeder_show_history where id=p_id for update;
 if old.id is not null and old.source_app not in ('rabbit_register','breeder_manual') then raise exception 'Connected show results are supplied by the show';end if;
 if p_animal is not null then
  select * into a from public.animals where id=p_animal;
  select owner_id into owner from public.farms where id=a.ring_id and not coalesce(is_demo,false) and breeder_private.has_access(owner_id);
 else owner:=old.owner_id;end if;
 if owner is null or not breeder_private.has_access(owner) or (old.id is not null and old.owner_id<>owner) then raise exception 'Show access denied';end if;
 if nullif(btrim(p_data->>'show_name'),'') is null then raise exception 'Enter the show name';end if;
 d:=nullif(p_data->>'show_date','')::date;
 if d>current_date or d<date '1800-01-01' then raise exception 'Check the show date';end if;
 if old.id is null and (a.id is null or d is null) then raise exception 'Choose an animal and show date';end if;
 for k in select key from jsonb_each(p_data) loop if length(coalesce(p_data->>k,''))>4000 then raise exception 'Show field is too long';end if;end loop;
 result:=coalesce(old.record,'{}')||jsonb_build_object('shows',jsonb_build_object('name',btrim(p_data->>'show_name'),'start_date',d,'location',p_data->>'location'),
 'animal_name',coalesce(a.name,old.record->>'animal_name',''),'tattoo',coalesce(a.tattoo,old.record->>'tattoo',''),'breed',coalesce(a.breed,old.record->>'breed',''),'variety',coalesce(a.variety,old.record->>'variety',''),'sex',coalesce(a.sex,old.record->>'sex',''),
 'judge',p_data->>'judge','placement',p_data->>'placement','special_awards',p_data->>'awards','is_leg',coalesce((p_data->>'is_leg')::boolean,false),'is_youth',coalesce((p_data->>'is_youth')::boolean,false),
 'number_in_class',p_data->>'number_in_class','number_of_exhibitors',p_data->>'number_of_exhibitors','total_shown',p_data->>'total_shown','comments',p_data->>'comments');
 if coalesce(old.revision,0)<>p_revision then
  if old.animal_id is not distinct from p_animal and old.record=result then return;end if;
  raise exception 'Show result changed. Refresh before saving.';
 end if;
 if old.id is null then
  insert into public.breeder_show_history(id,owner_id,source_app,source_entry_id,animal_id,exhibitor_source_id,record) values(p_id,owner,'breeder_manual',p_id,p_animal,md5(owner)::uuid,result||jsonb_build_object('source','Breeder entered'));
 else update public.breeder_show_history set animal_id=p_animal,record=result where id=p_id;end if;
end $$;

grant update on public.litter_weights,public.animal_wool_records to authenticated;
create policy litter_weight_edit on public.litter_weights for update to authenticated
 using(exists(select 1 from public.breeding_records b where b.id=breeding_id)) with check(recorded_date<=current_date and exists(select 1 from public.breeding_records b where b.id=breeding_id));
create policy wool_edit on public.animal_wool_records for update to authenticated
 using(breeder_private.animal_access(animal_id)) with check(breeder_private.animal_access(animal_id) and (recorded_date is null or recorded_date<=current_date));
alter table public.litter_weights add column voided boolean not null default false;
alter table public.animal_wool_records add column voided boolean not null default false;
alter table public.animal_feed_weights add column voided boolean not null default false;
grant update(voided) on public.litter_weights,public.animal_wool_records,public.animal_feed_weights to authenticated;
create function public.save_production_measurement(p_kind text,p_id uuid,p_parent uuid,p_data jsonb,p_revision integer default 0)
returns void language plpgsql security invoker set search_path='' as $$
declare w public.animal_wool_records; l public.litter_weights; f public.animal_feed_weights; d date; weight numeric; feed numeric; details jsonb; k text; n numeric; chart public.animal_weights; removed boolean;
begin
 if auth.uid() is null then raise exception 'Sign in to save';end if;
 d:=nullif(p_data->>'recorded_date','')::date;removed:=coalesce((p_data->>'voided')::boolean,false);
 if d>current_date or d<date '1800-01-01' or length(coalesce(p_data->>'notes',''))>10000 then raise exception 'Check date and notes';end if;
 if p_kind='wool' then
  if not breeder_private.animal_access(p_parent) then raise exception 'Animal access denied';end if;
  select * into w from public.animal_wool_records where id=p_id for update;
  if w.id is not null and w.animal_id<>p_parent then raise exception 'Measurement identity cannot change';end if;
  weight:=nullif(p_data->>'fleece_grams','')::numeric;details:=coalesce(p_data->'measurements','{}');
  if jsonb_typeof(details)<>'object' or octet_length(details::text)>50000 then raise exception 'Invalid wool details';end if;
  foreach k in array array['PRIME','GRADE2','COMBINGS','FELTEDSTAINED','BODYWT','LENGTH','AFD','STRENGTH','CRIMPCOUNT','SD','CV','CEM','CF','LT15','GT30','VEGMATTERBASE','WOOLBASE'] loop
   n:=nullif(details->>k,'')::numeric;
   if n is not null and not (n>=0 and n<1000000 and n<>'NaN'::numeric) then raise exception 'Invalid wool measurement %',k;end if;
   if k in ('CF','LT15','GT30','VEGMATTERBASE','WOOLBASE') and n>100 then raise exception 'Percentage must be between 0 and 100';end if;
  end loop;
  if w.native_weight_id is not null then
   select * into chart from public.animal_weights where id=w.native_weight_id;
   if abs(public.rabbit_register_number(details->>'BODYWT')/453.592-chart.weight)>0.00000001 or public.rabbit_register_number(details->>'BODYWT') is null or d is distinct from (chart.recorded_at at time zone 'UTC')::date then raise exception 'Correct linked body weights in Weight History';end if;
  end if;
  if coalesce(w.revision,0)<>p_revision then
   if w.recorded_date is not distinct from d and w.fleece_grams is not distinct from weight and w.measurements=details and w.notes=coalesce(p_data->>'notes','') and w.voided=removed then return;end if;
   raise exception 'Measurement changed. Refresh before saving.';end if;
  if w.id is null and weight is null and details='{}' then raise exception 'Enter a harvest measurement or evaluation';end if;
  if w.native_weight_id is null and not removed and d is not null and public.rabbit_register_number(details->>'BODYWT')>0 and exists(select 1 from public.animals a where a.id=p_parent and a.status not in ('sold','deceased'))
   and exists(select 1 from public.wool_settings s join public.animals a on a.ring_id=s.ring_id where a.id=p_parent and s.update_body_weight) then
   insert into public.animal_weights(animal_id,weight,recorded_at) values(p_parent,public.rabbit_register_number(details->>'BODYWT')/453.592,(d::text||'T12:00:00Z')::timestamptz) returning * into chart;
  end if;
  insert into public.animal_wool_records(id,animal_id,recorded_date,fleece_grams,measurements,notes,voided,native_weight_id) values(p_id,p_parent,d,weight,details,coalesce(p_data->>'notes',''),removed,coalesce(w.native_weight_id,chart.id))
  on conflict(id) do update set recorded_date=excluded.recorded_date,fleece_grams=excluded.fleece_grams,measurements=excluded.measurements,notes=excluded.notes,voided=excluded.voided,native_weight_id=excluded.native_weight_id,revision=public.animal_wool_records.revision+1;
 elsif p_kind in ('litter','animal_feed') then
  weight:=nullif(p_data->>'weight','')::numeric;feed:=nullif(p_data->>'feed_weight','')::numeric;
  if d is null or (weight is null and feed is null) then raise exception 'Enter a date and feed or live weight';end if;
  if p_kind='litter' then
   perform 1 from public.breeding_records where id=p_parent for update;if not found then raise exception 'Litter access denied';end if;
   select * into l from public.litter_weights where id=p_id for update;
   if l.id is not null and l.breeding_id<>p_parent then raise exception 'Measurement identity cannot change';end if;
   if coalesce(l.revision,0)<>p_revision then
    if l.recorded_date=d and l.weight is not distinct from weight and l.feed_weight is not distinct from feed and l.notes=coalesce(p_data->>'notes','') and l.voided=removed then return;end if;
    raise exception 'Measurement changed. Refresh before saving.';end if;
   insert into public.litter_weights(id,breeding_id,recorded_date,weight,feed_weight,notes,voided) values(p_id,p_parent,d,weight,feed,coalesce(p_data->>'notes',''),removed)
   on conflict(id) do update set recorded_date=excluded.recorded_date,weight=excluded.weight,feed_weight=excluded.feed_weight,notes=excluded.notes,voided=excluded.voided,revision=public.litter_weights.revision+1;
  else
   if not breeder_private.animal_access(p_parent) then raise exception 'Animal access denied';end if;
   perform 1 from public.animals where id=p_parent for update;
   select * into f from public.animal_feed_weights where id=p_id for update;
   if f.id is not null and f.animal_id<>p_parent then raise exception 'Measurement identity cannot change';end if;
   if f.native_weight_id is not null then
    select * into chart from public.animal_weights where id=f.native_weight_id;
    if weight is distinct from chart.weight or d is distinct from (chart.recorded_at at time zone 'UTC')::date then raise exception 'Correct linked body weights in Weight History';end if;
   end if;
   if coalesce(f.revision,0)<>p_revision then
    if f.recorded_date=d and f.weight is not distinct from weight and f.feed_weight is not distinct from feed and f.notes=coalesce(p_data->>'notes','') and f.voided=removed then return;end if;
    raise exception 'Measurement changed. Refresh before saving.';end if;
   if f.native_weight_id is null and weight>0 and exists(select 1 from public.animals a where a.id=p_parent and a.status not in ('sold','deceased')) then
    insert into public.animal_weights(animal_id,weight,recorded_at) values(p_parent,weight,(d::text||'T12:00:00Z')::timestamptz) returning * into chart;
   end if;
   insert into public.animal_feed_weights(id,animal_id,recorded_date,weight,feed_weight,notes,voided,native_weight_id) values(p_id,p_parent,d,weight,feed,coalesce(p_data->>'notes',''),removed,coalesce(f.native_weight_id,chart.id))
   on conflict(id) do update set recorded_date=excluded.recorded_date,weight=excluded.weight,feed_weight=excluded.feed_weight,notes=excluded.notes,voided=excluded.voided,native_weight_id=excluded.native_weight_id,revision=public.animal_feed_weights.revision+1;
  end if;
 else raise exception 'Unknown measurement type';end if;
end $$;

create function public.link_litter_offspring(p_id uuid,p_animals uuid[]) returns void language plpgsql security invoker set search_path='' as $$
declare b public.breeding_records; t public.breeding_tracking; child uuid; a public.animals; n integer;
begin
 select * into b from public.breeding_records where id=p_id for update;
 if b.id is null then raise exception 'Litter access denied';end if;
 select * into t from public.breeding_tracking where breeding_id=p_id;
 if cardinality(p_animals)>100 or cardinality(p_animals)=0 then raise exception 'Choose up to 100 offspring';end if;
 for child in select distinct unnest(p_animals) loop
  select * into a from public.animals where id=child;
  if a.id is null or a.dam_id is distinct from b.dam_id or (b.sire_id is not null and a.sire_id is distinct from b.sire_id)
   or (t.birth_date is not null and a.dob is not null and a.dob<>t.birth_date) then raise exception 'Offspring must match the litter parents and known birth date';end if;
  if exists(select 1 from public.breeding_offspring where animal_id=child and breeding_id<>p_id) then raise exception 'Animal already belongs to another litter';end if;
  insert into public.breeding_offspring(animal_id,breeding_id) values(child,p_id) on conflict do nothing;
 end loop;
 select count(*) into n from public.breeding_offspring where breeding_id=p_id;
 if t.weaned is not null and n>t.weaned then raise exception 'Linked animals exceed the recorded weaning count';end if;
end $$;
revoke all on function public.save_herd_contact(uuid,uuid,jsonb,integer),public.save_managed_show_result(uuid,uuid,jsonb,integer),public.save_production_measurement(text,uuid,uuid,jsonb,integer),public.link_litter_offspring(uuid,uuid[]) from public,anon;
grant execute on function public.save_herd_contact(uuid,uuid,jsonb,integer),public.save_managed_show_result(uuid,uuid,jsonb,integer),public.save_production_measurement(text,uuid,uuid,jsonb,integer),public.link_litter_offspring(uuid,uuid[]) to authenticated;

revoke update on public.herd_contacts,public.litter_weights,public.animal_wool_records from authenticated;
grant update(name,rabbitry,email,phone,address,city,state,zip,country,revision) on public.herd_contacts to authenticated;
grant update(recorded_date,weight,feed_weight,notes,revision,voided) on public.litter_weights to authenticated;
grant update(recorded_date,fleece_grams,measurements,notes,revision,voided,native_weight_id) on public.animal_wool_records to authenticated;
create policy managed_offspring_add on public.breeding_offspring for insert to authenticated with check(
 exists(select 1 from public.breeding_records b join public.animals a on a.id=breeding_offspring.animal_id
 join public.animals d on d.id=b.dam_id where b.id=breeding_offspring.breeding_id and a.ring_id=d.ring_id and a.species=d.species
 and a.dam_id=b.dam_id and (b.sire_id is null or a.sire_id=b.sire_id)) and breeder_private.animal_access(animal_id));

create or replace function public.create_litter_animals(p_id uuid,p_young jsonb)
returns integer language plpgsql security invoker set search_path='' as $$
declare b public.breeding_records; t public.breeding_tracking; dam public.animals; y jsonb; aid uuid; n integer=0; linked integer; linked_males integer; linked_females integer;
begin
 select * into b from public.breeding_records where id=p_id for update;
 if b.id is null then raise exception 'Breeding access denied'; end if;
 select * into t from public.breeding_tracking where breeding_id=p_id;
 if t.weaned is null or t.weaned=0 or t.status='cancelled' then raise exception 'Record weaning first'; end if;
 if t.birth_date is null or t.wean_date is null or b.sire_id is null then raise exception 'Record the sire, birth date and weaning date before creating new offspring';end if;
 select count(*),count(*) filter(where a.sex in ('Buck','Boar')),count(*) filter(where a.sex in ('Doe','Sow')) into linked,linked_males,linked_females
 from public.breeding_offspring o join public.animals a on a.id=o.animal_id where o.breeding_id=p_id;
 if linked>=t.weaned then raise exception 'Offspring records already created';end if;
 if jsonb_typeof(p_young) is distinct from 'array' or jsonb_array_length(p_young)<>t.weaned-linked then raise exception 'Enter one row for each weaned animal'; end if;
 if t.weaned_males is not null and ((select count(*) from jsonb_array_elements(p_young) as item(value) where item.value->>'sex'='M')<>t.weaned_males-linked_males or (select count(*) from jsonb_array_elements(p_young) as item(value) where item.value->>'sex'='F')<>t.weaned_females-linked_females) then raise exception 'Offspring sexes must match the recorded weaning counts'; end if;
 select * into dam from public.animals where id=b.dam_id;
 for y in select value from jsonb_array_elements(p_young) loop
  if nullif(trim(y->>'tattoo'),'') is null or coalesce(y->>'sex','') not in ('M','F') then raise exception 'Enter an ear number and sex for each animal'; end if;
  if exists(select 1 from public.animals a where a.ring_id=dam.ring_id and a.species=dam.species and lower(trim(a.tattoo))=lower(trim(y->>'tattoo'))) then raise exception 'An ear number already exists in this Ring'; end if;
  insert into public.animals(ring_id,name,tattoo,species,breed,variety,sex,dob,sire_id,dam_id,status,pedigree_only)
  values(dam.ring_id,nullif(trim(y->>'name'),''),trim(y->>'tattoo'),dam.species,nullif(trim(y->>'breed'),''),nullif(trim(y->>'variety'),''),case when dam.species='cavy' then case when y->>'sex'='M' then 'Boar' else 'Sow' end else case when y->>'sex'='M' then 'Buck' else 'Doe' end end,t.birth_date,b.sire_id,b.dam_id,'active',false) returning id into aid;
  insert into public.breeding_offspring(animal_id,breeding_id) values(aid,p_id);
  n=n+1;
 end loop;
 update public.breeding_tracking set status='completed',revision=revision+1 where breeding_id=p_id;
 update public.breeding_records set status='completed' where id=p_id;
 return n;
end $$;

grant update(breeding_date) on public.breeding_records to authenticated;
create policy imported_breeding_edit on public.breeding_records for update to authenticated
 using(import_source is not null and breeder_private.animal_access(dam_id) and exists(select 1 from public.farms f where f.id=import_ring_id and breeder_private.has_access(f.owner_id)))
 with check(import_source is not null and breeder_private.animal_access(dam_id) and exists(select 1 from public.farms f where f.id=import_ring_id and breeder_private.has_access(f.owner_id)) and (sire_id is null or breeder_private.animal_access(sire_id)));
create or replace function public.save_breeding_tracking(p_id uuid,p_data jsonb,p_revision integer)
returns void language plpgsql security invoker set search_path='' as $$
declare b public.breeding_records; old public.breeding_tracking; t public.breeding_tracking;
begin
 select * into b from public.breeding_records where id=p_id for update;
 if b.id is null then raise exception 'Breeding access denied'; end if;
 select * into old from public.breeding_tracking where breeding_id=p_id;
 if coalesce(old.revision,0)<>p_revision then raise exception 'This litter changed. Refresh and try again.'; end if;
 if p_data ? 'actual_breeding_date' then
  b.breeding_date:=nullif(p_data->>'actual_breeding_date','')::date;
  if b.breeding_date<date '1800-01-01' then raise exception 'Invalid breeding date';end if;
 end if;
 t=jsonb_populate_record(null::public.breeding_tracking,coalesce(to_jsonb(old),'{}')||p_data);
 if (p_data ? 'weaned_males' or p_data ? 'weaned_females') and not (old.import_record is not null and t.weaned_males is null and t.weaned_females is null) then
  if t.wean_date is not null and (t.weaned_males is null or t.weaned_females is null) then raise exception 'Enter both sex counts (use 0 when none)'; end if;
  t.weaned=t.weaned_males+t.weaned_females;
 end if;
 if (b.breeding_date>current_date and t.breeding_occurred is distinct from false) then raise exception 'Actual breeding date cannot be in the future';end if;
 if t.due_date<b.breeding_date or t.check_date<b.breeding_date or t.birth_date<b.breeding_date
 or t.birth_date>current_date or t.check_date>current_date or t.wean_date>current_date then raise exception 'Check the event dates'; end if;
 if exists(select 1 from public.breeding_offspring where breeding_id=p_id) and
 ((old.birth_date is not null and t.birth_date is distinct from old.birth_date) or
 (old.weaned is not null and t.weaned is distinct from old.weaned) or
 (old.wean_date is not null and t.wean_date is distinct from old.wean_date) or
 (old.import_record is null and (t.birth_date is distinct from old.birth_date or t.weaned is distinct from old.weaned or t.wean_date is distinct from old.wean_date)))
 then raise exception 'Offspring already created. Birth and weaning totals are locked.'; end if;
 if exists(select 1 from public.breeding_offspring o join public.animals a on a.id=o.animal_id where o.breeding_id=p_id and t.birth_date is not null and a.dob is not null and a.dob<>t.birth_date)
 or t.weaned<(select count(*) from public.breeding_offspring where breeding_id=p_id) then raise exception 'Tracking conflicts with linked offspring';end if;
 if t.split_date<t.paired_date or t.paired_date>current_date or t.split_date>current_date then raise exception 'Check pairing and separation dates';end if;
 if (t.weaned is not null and coalesce(t.born_alive,t.born_total) is not null and t.weaned>coalesce(t.born_alive,t.born_total)+coalesce(t.added,0)) then raise exception 'Weaned total exceeds born plus added';end if;
 insert into public.breeding_tracking(breeding_id,due_date,check_date,check_result,birth_date,born_alive,born_dead,wean_date,weaned,weaned_males,weaned_females,status,notes,born_total,recorded_deaths,paired_date,split_date,scheduled_breeding_date,breeding_occurred,nest_installed,nest_removed,rebreeding_enabled,rebreeding_overridden,cage,breed_label,palpation_source,added,raised,bucks,does,kept,sold,show_quality,custom_fields,revision,import_record)
 values(p_id,t.due_date,t.check_date,coalesce(t.check_result,'Not checked'),t.birth_date,t.born_alive,t.born_dead,t.wean_date,t.weaned,t.weaned_males,t.weaned_females,t.status,coalesce(t.notes,''),t.born_total,t.recorded_deaths,t.paired_date,t.split_date,t.scheduled_breeding_date,t.breeding_occurred,t.nest_installed,t.nest_removed,t.rebreeding_enabled,t.rebreeding_overridden,coalesce(t.cage,''),coalesce(t.breed_label,''),t.palpation_source,t.added,t.raised,t.bucks,t.does,t.kept,t.sold,t.show_quality,coalesce(t.custom_fields,'{}'),p_revision+1,old.import_record)
 on conflict(breeding_id) do update set due_date=excluded.due_date,check_date=excluded.check_date,check_result=excluded.check_result,birth_date=excluded.birth_date,born_alive=excluded.born_alive,born_dead=excluded.born_dead,wean_date=excluded.wean_date,weaned=excluded.weaned,weaned_males=excluded.weaned_males,weaned_females=excluded.weaned_females,status=excluded.status,notes=excluded.notes,born_total=excluded.born_total,recorded_deaths=excluded.recorded_deaths,paired_date=excluded.paired_date,split_date=excluded.split_date,scheduled_breeding_date=excluded.scheduled_breeding_date,breeding_occurred=excluded.breeding_occurred,nest_installed=excluded.nest_installed,nest_removed=excluded.nest_removed,rebreeding_enabled=excluded.rebreeding_enabled,rebreeding_overridden=excluded.rebreeding_overridden,cage=excluded.cage,breed_label=excluded.breed_label,palpation_source=excluded.palpation_source,added=excluded.added,raised=excluded.raised,bucks=excluded.bucks,does=excluded.does,kept=excluded.kept,sold=excluded.sold,show_quality=excluded.show_quality,custom_fields=excluded.custom_fields,revision=excluded.revision;
 update public.breeding_records set status=t.status,breeding_date=b.breeding_date where id=p_id;
end $$;

create or replace function breeder_private.sales_audit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 insert into public.animal_sale_history(sale_id,event,details,created_by)
 values(new.id,case when tg_op='INSERT' and new.import_source is not null then 'imported' when tg_op='INSERT' then 'listed' else 'updated' end,
   jsonb_build_object('before',case when tg_op='UPDATE' then to_jsonb(old) else null end,'after',to_jsonb(new)),auth.uid());
 if new.import_source is null and new.status='sold' and (tg_op='INSERT' or old.status<>'sold') then
  update public.animals set status='sold' where id=new.animal_id;
 end if;
 if new.status='sold' then
  insert into public.animal_management(animal_id,sale_date,buyer_contact_id) values(new.animal_id,new.sale_date,new.buyer_contact_id)
  on conflict(animal_id) do update set sale_date=excluded.sale_date,buyer_contact_id=coalesce(excluded.buyer_contact_id,public.animal_management.buyer_contact_id),revision=public.animal_management.revision+1;
 end if;
 return new;
end $$;

revoke all on function public.rabbit_register_flag(text),public.rabbit_register_count(text) from public,anon;
grant execute on function public.rabbit_register_flag(text),public.rabbit_register_count(text) to authenticated;

-- A feed entry can only refer to the same animal's body-weight chart reading.
create function breeder_private.feed_weight_identity() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if new.native_weight_id is not null and not exists(select 1 from public.animal_weights w where w.id=new.native_weight_id and w.animal_id=new.animal_id and w.weight=new.weight and (w.recorded_at at time zone 'UTC')::date=new.recorded_date)
 then raise exception 'Body-weight link does not match this reading';end if;
 return new;
end $$;
revoke all on function breeder_private.feed_weight_identity() from public,anon,authenticated;
create trigger animal_feed_weight_identity before insert or update on public.animal_feed_weights
 for each row execute function breeder_private.feed_weight_identity();
create index animal_feed_native_weight on public.animal_feed_weights(native_weight_id) where native_weight_id is not null;
create index rabbit_register_files_source on public.rabbit_register_files(ring_id,source,imported_at);
create index breeding_tracking_rebreeding_date on public.breeding_tracking(scheduled_breeding_date) where scheduled_breeding_date is not null;

-- Wool calculation preferences are not exported by Rabbit Register. Store the
-- breeder's reviewed choices separately from immutable source measurements.
create table public.wool_settings (
 ring_id uuid primary key references public.farms(id) on delete cascade,
 unit text not null default 'g' check(unit in ('g','kg','oz','lb','lb_oz')),
 metric text not null default 'gross' check(metric in ('gross','adjusted','prime')),
 period text not null default 'month' check(period in ('day','week','month','year','last12','lifetime')),
 update_body_weight boolean not null default false, show_on_pedigree boolean not null default false,
 factors jsonb not null default '{"PRIME":100,"GRADE2":75,"COMBINGS":25,"FELTEDSTAINED":25}' check(jsonb_typeof(factors)='object' and octet_length(factors::text)<=2000),
 revision integer not null default 1
);
alter table public.wool_settings enable row level security;
revoke all on public.wool_settings from public,anon,authenticated;
grant select,insert,update on public.wool_settings to authenticated;
grant all on public.wool_settings to service_role;
create policy wool_settings_access on public.wool_settings for all to authenticated
 using(exists(select 1 from public.farms f where f.id=ring_id and not coalesce(f.is_demo,false) and breeder_private.has_access(f.owner_id)))
 with check(exists(select 1 from public.farms f where f.id=ring_id and not coalesce(f.is_demo,false) and breeder_private.has_access(f.owner_id)));
create function public.save_wool_settings(p_animal uuid,p_data jsonb,p_revision integer) returns void
language plpgsql security invoker set search_path='' as $$
declare herd uuid; old public.wool_settings; factors jsonb; k text; n numeric;
begin
 select a.ring_id into herd from public.animals a join public.farms f on f.id=a.ring_id where a.id=p_animal and not coalesce(f.is_demo,false) and breeder_private.has_access(f.owner_id);
 if herd is null then raise exception 'Animal access denied';end if;
 perform 1 from public.farms where id=herd for update;
 select * into old from public.wool_settings where ring_id=herd for update;
 factors:=p_data->'factors';
 if jsonb_typeof(factors) is distinct from 'object' then raise exception 'Enter wool scale factors';end if;
 foreach k in array array['PRIME','GRADE2','COMBINGS','FELTEDSTAINED'] loop
  n:=(factors->>k)::numeric;
  if n is null or not (n>=0 and n<=100 and n<>'NaN'::numeric) then raise exception 'Scale factors must be from 0 to 100';end if;
 end loop;
 if coalesce(old.revision,0)<>p_revision then
  if old.unit=p_data->>'unit' and old.metric=p_data->>'metric' and old.period=p_data->>'period' and old.factors=factors and old.update_body_weight=coalesce((p_data->>'update_body_weight')::boolean,false) and old.show_on_pedigree=coalesce((p_data->>'show_on_pedigree')::boolean,false) then return;end if;
  raise exception 'Wool settings changed. Refresh before saving.';
 end if;
 insert into public.wool_settings(ring_id,unit,metric,period,factors,update_body_weight,show_on_pedigree) values(herd,p_data->>'unit',p_data->>'metric',p_data->>'period',factors,coalesce((p_data->>'update_body_weight')::boolean,false),coalesce((p_data->>'show_on_pedigree')::boolean,false))
 on conflict(ring_id) do update set unit=excluded.unit,metric=excluded.metric,period=excluded.period,factors=excluded.factors,update_body_weight=excluded.update_body_weight,show_on_pedigree=excluded.show_on_pedigree,revision=public.wool_settings.revision+1;
end $$;
revoke all on function public.save_wool_settings(uuid,jsonb,integer) from public,anon;
grant execute on function public.save_wool_settings(uuid,jsonb,integer) to authenticated;

-- Direct writes use the same factor bounds and cannot move herd identities.
create function breeder_private.wool_settings_guard() returns trigger language plpgsql set search_path='' as $$
declare k text; n numeric;
begin
 if TG_OP='UPDATE' and new.ring_id<>old.ring_id then raise exception 'Wool settings identity cannot change';end if;
 foreach k in array array['PRIME','GRADE2','COMBINGS','FELTEDSTAINED'] loop
  n:=(new.factors->>k)::numeric;
  if n is null or not(n>=0 and n<=100 and n<>'NaN'::numeric) then raise exception 'Scale factors must be from 0 to 100';end if;
 end loop;
 return new;
end $$;
revoke all on function breeder_private.wool_settings_guard() from public,anon,authenticated;
create trigger wool_settings_guard before insert or update on public.wool_settings for each row execute function breeder_private.wool_settings_guard();
create index animal_wool_native_weight on public.animal_wool_records(native_weight_id) where native_weight_id is not null;
create function breeder_private.wool_weight_identity() returns trigger language plpgsql set search_path='' as $$
begin
 if new.native_weight_id is not null and not exists(select 1 from public.animal_weights w where w.id=new.native_weight_id and w.animal_id=new.animal_id and (w.recorded_at at time zone 'UTC')::date=new.recorded_date and abs(w.weight-public.rabbit_register_number(new.measurements->>'BODYWT')/453.592)<=0.00000001) then raise exception 'Invalid linked body weight';end if;
 return new;
end $$;
revoke all on function breeder_private.wool_weight_identity() from public,anon,authenticated;
create trigger wool_weight_identity before insert or update on public.animal_wool_records for each row execute function breeder_private.wool_weight_identity();

-- An unresolved/negative source CID is reviewed explicitly, never guessed from
-- its absolute value. The exported record remains unchanged.
create function public.link_rabbit_register_wool(p_ring uuid,p_source text,p_source_id text,p_animal uuid) returns uuid
language plpgsql security invoker set search_path='' as $$
declare r public.rabbit_register_records; linked public.animal_wool_records; raw jsonb; grams numeric; dt date; result uuid;
begin
 select * into r from public.rabbit_register_records where ring_id=p_ring and source=p_source and source_id=p_source_id and kind='wool' for update;
 if not found then raise exception 'Source wool record access denied';end if;
 if not exists(select 1 from public.animals a where a.id=p_animal and a.ring_id=p_ring and breeder_private.animal_access(a.id)) then raise exception 'Choose a rabbit in this herd';end if;
 if r.animal_id is not null and r.animal_id<>p_animal then raise exception 'Source record already identifies another rabbit';end if;
 if r.native_wool_id is not null then
  select * into linked from public.animal_wool_records where id=r.native_wool_id;
  if linked.animal_id<>p_animal then raise exception 'Wool record is already linked';end if;
  return linked.id;
 end if;
 raw:=r.record->'raw';grams:=public.rabbit_register_number(raw->>'FLEECEWT');dt:=public.rabbit_register_date(raw->>'SHEARDATE');
 insert into public.animal_wool_records(animal_id,recorded_date,fleece_grams,measurements,notes,import_source,import_source_id)
 values(p_animal,case when dt<=current_date then dt end,case when grams>0 and grams<1000000 then grams end,raw,coalesce(raw->>'COMMENTS',''),p_source,p_source_id)
 on conflict(animal_id,import_source,import_source_id) do nothing;
 select id into result from public.animal_wool_records where animal_id=p_animal and import_source=p_source and import_source_id=p_source_id;
 update public.rabbit_register_records set native_wool_id=result where ring_id=p_ring and source=p_source and kind='wool' and source_id=p_source_id;
 return result;
end $$;
revoke all on function public.link_rabbit_register_wool(uuid,text,text,uuid) from public,anon;
grant execute on function public.link_rabbit_register_wool(uuid,text,text,uuid) to authenticated;
create function breeder_private.wool_source_link_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if old.native_wool_id is not null and new.native_wool_id is not null and new.native_wool_id is distinct from old.native_wool_id then raise exception 'Wool source identity cannot change';end if;
 if new.native_wool_id is not null and not exists(select 1 from public.animal_wool_records w join public.animals a on a.id=w.animal_id where w.id=new.native_wool_id and a.ring_id=new.ring_id and w.import_source=new.source and w.import_source_id=new.source_id and new.kind='wool' and (new.animal_id is null or new.animal_id=w.animal_id)) then raise exception 'Invalid wool source link';end if;
 return new;
end $$;
revoke all on function breeder_private.wool_source_link_guard() from public,anon,authenticated;
create trigger wool_source_link_guard before update of native_wool_id on public.rabbit_register_records for each row execute function breeder_private.wool_source_link_guard();

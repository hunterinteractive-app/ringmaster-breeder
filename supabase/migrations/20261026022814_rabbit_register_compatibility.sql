-- Accept documented field spellings and observed XML variants without changing
-- immutable source snapshots or existing ownership/matching checks.
create function public.rabbit_register_field_key(value text) returns text
language sql immutable strict security invoker set search_path='' as $$
 select case regexp_replace(lower(value),'[^a-z0-9]','','g')
  when 'earnumber' then 'earnum'
  when 'winnings' then 'wins'
  when 'forsalepprice' then 'forsaleprice'
  else regexp_replace(lower(value),'[^a-z0-9]','','g') end
$$;

create function public.rabbit_register_field(p_raw jsonb,p_key text) returns text
language plpgsql immutable security invoker set search_path='' as $$
declare candidates text[];
begin
 select array_agg(distinct trimmed) into candidates from (
  select nullif(regexp_replace(value,'^[[:space:]]+|[[:space:]]+$','','g'),'') trimmed
  from jsonb_each_text(coalesce(p_raw,'{}'))
  where public.rabbit_register_field_key(key)=public.rabbit_register_field_key(p_key)
 ) fields where trimmed is not null;
 if cardinality(candidates)>1 then raise exception 'Conflicting values for % in Rabbit Register record.',p_key; end if;
 return candidates[1];
end $$;
revoke all on function public.rabbit_register_field_key(text),public.rabbit_register_field(jsonb,text) from public,anon;
grant execute on function public.rabbit_register_field_key(text),public.rabbit_register_field(jsonb,text) to authenticated,service_role;

create or replace function public.link_rabbit_register_history(p_ring uuid,p_source text,p_commit boolean default false,p_updates jsonb default '[]')
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
  values(p_ring,p_source,r.source_id,btrim(concat_ws(' ',public.rabbit_register_field(raw,'FirstName'),public.rabbit_register_field(raw,'LastName'))),coalesce(public.rabbit_register_field(raw,'Rabbitry'),''),coalesce(public.rabbit_register_field(raw,'Email'),''),coalesce(public.rabbit_register_field(raw,'Phone0'),''),concat_ws(E'\n',nullif(public.rabbit_register_field(raw,'Address0'),''),nullif(public.rabbit_register_field(raw,'Address1'),'')),coalesce(public.rabbit_register_field(raw,'City'),''),coalesce(public.rabbit_register_field(raw,'State'),''),coalesce(public.rabbit_register_field(raw,'Zip'),public.rabbit_register_field(raw,'ZIP'),''),coalesce(public.rabbit_register_field(raw,'Country'),''),raw) on conflict do nothing;
 end loop;
 for a in select * from public.rabbit_register_animals where ring_id=p_ring and source=p_source loop
  raw:=a.raw;
  -- Supplemental export fields can fill gaps without replacing the first snapshot.
  for x in select value from jsonb_array_elements(p_updates) where value->>'source_id'=a.source_id loop
   if coalesce(public.rabbit_register_field(x->'raw','Name'),'')=coalesce(public.rabbit_register_field(a.raw,'Name'),'') and coalesce(public.rabbit_register_field(x->'raw','Breed'),'')=coalesce(public.rabbit_register_field(a.raw,'Breed'),'') and coalesce(public.rabbit_register_field(x->'raw','Ear_Num'),'')=coalesce(public.rabbit_register_field(a.raw,'Ear_Num'),'') then
    -- A newer spelling replaces its equivalent key in this working view only.
    -- The retained source snapshot and existing management values stay intact.
    select coalesce(jsonb_object_agg(kept.key,kept.value),'{}'::jsonb) into raw
    from jsonb_each(raw) kept where not exists(
     select 1 from jsonb_each(x->'raw') incoming
     where public.rabbit_register_field_key(kept.key)=public.rabbit_register_field_key(incoming.key));
    raw:=raw||(x->'raw');
   end if;
  end loop;
  buyer:=null;seller:=null;
  select id into buyer from public.herd_contacts where ring_id=p_ring and source=p_source and source_id=public.rabbit_register_field(raw,'BuyerKey');
  select id into seller from public.herd_contacts where ring_id=p_ring and source=p_source and source_id=public.rabbit_register_field(raw,'SellerKey');
  if public.rabbit_register_field(raw,'BuyerKey') is not null and public.rabbit_register_field(raw,'BuyerKey')<>'0' and buyer is null then notices:=notices||jsonb_build_array('Rabbit '||a.source_id||': buyer contact is missing.'); end if;
  if public.rabbit_register_field(raw,'SellerKey') is not null and public.rabbit_register_field(raw,'SellerKey')<>'0' and seller is null then notices:=notices||jsonb_build_array('Rabbit '||a.source_id||': seller contact is missing.'); end if;
  select coalesce(jsonb_object_agg(key,value),'{}') into custom from jsonb_each(raw)
   where public.rabbit_register_field_key(key) not in ('cid','breed','storagearea','earnum','earnum','name','sex','variety','reg','legs','grandchnum','grandchnum','sirekey','damkey','weight','dob','dobtag','dod','dodtag','datesold','datebought','dateweaned','comments','cage','buyerkey','sellerkey','amountpaid','forsaleprice','forsaleprice','soldfor');
  amount:=public.rabbit_register_number(public.rabbit_register_field(raw,'AmountPaid'))*100;
  insert into public.animal_management(animal_id,cage,custom_fields,death_date,sale_date,purchase_date,purchase_cents,buyer_contact_id,seller_contact_id)
  values(a.animal_id,coalesce(public.rabbit_register_field(raw,'Cage'),''),custom,public.rabbit_register_date(public.rabbit_register_field(raw,'DOD')),public.rabbit_register_date(public.rabbit_register_field(raw,'DateSold')),public.rabbit_register_date(public.rabbit_register_field(raw,'DateBought')),case when amount between 0 and 99999999999 then round(amount)::bigint end,buyer,seller)
  on conflict(animal_id) do update set cage=coalesce(nullif(public.animal_management.cage,''),excluded.cage),
  custom_fields=excluded.custom_fields||public.animal_management.custom_fields,
  death_date=coalesce(public.animal_management.death_date,excluded.death_date),sale_date=coalesce(public.animal_management.sale_date,excluded.sale_date),
  purchase_date=coalesce(public.animal_management.purchase_date,excluded.purchase_date),purchase_cents=coalesce(public.animal_management.purchase_cents,excluded.purchase_cents),
  buyer_contact_id=coalesce(public.animal_management.buyer_contact_id,excluded.buyer_contact_id),seller_contact_id=coalesce(public.animal_management.seller_contact_id,excluded.seller_contact_id),revision=public.animal_management.revision+1;
  if public.rabbit_register_number(public.rabbit_register_field(raw,'ForSalePrice'))*100 between 0 and 99999999999 then
   update public.animal_management set asking_cents=round(public.rabbit_register_number(public.rabbit_register_field(raw,'ForSalePrice'))*100)::bigint where animal_id=a.animal_id and asking_cents is null;
  end if;
  dt:=public.rabbit_register_date(public.rabbit_register_field(raw,'DateSold'));amount:=public.rabbit_register_number(public.rabbit_register_field(raw,'SoldFor'))*100;
  if dt is not null or buyer is not null or amount is not null then
   insert into public.animal_sales(animal_id,ring_id,animal_name,status,asking_cents,sale_cents,sale_date,buyer_contact_id,buyer_name,buyer_email,buyer_phone,buyer_address,notes,import_source,import_source_account,import_source_id,import_record,payment_history_complete)
   select a.animal_id,p_ring,'','sold',case when public.rabbit_register_number(public.rabbit_register_field(raw,'ForSalePrice'))*100 between 0 and 99999999999 then round(public.rabbit_register_number(public.rabbit_register_field(raw,'ForSalePrice'))*100)::bigint end,
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
  values(aid,r.animal_id,public.rabbit_register_date(public.rabbit_register_field(raw,'DATEBRED')),left(coalesce(public.rabbit_register_field(raw,'COMMENTS'),''),4000),case when public.rabbit_register_flag(public.rabbit_register_field(raw,'REMOVELITTERCOMPLETE')) is true then 'completed' else 'active' end,p_source,p_ring,r.source_id,raw) on conflict do nothing;
  select id into bid from public.breeding_records where import_ring_id=p_ring and import_source=p_source and import_source_id=r.source_id;
  select coalesce(jsonb_object_agg(key,value),'{}') into custom from jsonb_each(raw)
   where public.rabbit_register_field_key(key) not in ('id','datebred','dateborn','dateweaned','sireidkey','damidkey','numberborn','numberweaned','died','comments','datepaired','datesplit','scheduledbreedingdate','breedingoccurred','palpateresults','installnestboxcomplete','removenestboxcomplete','removelittercomplete','rebreedingenabled','rebreedingoverridden','breednamedecoded','cage','bucks','does','added','raised','kept','sold','showquality');
  insert into public.breeding_tracking(breeding_id,birth_date,born_total,recorded_deaths,wean_date,weaned,status,notes,import_record,
   paired_date,split_date,scheduled_breeding_date,breeding_occurred,nest_installed,nest_removed,rebreeding_enabled,rebreeding_overridden,
   cage,breed_label,palpation_source,added,raised,bucks,does,kept,sold,show_quality,custom_fields)
  values(bid,public.rabbit_register_date(public.rabbit_register_field(raw,'DATEBORN')),public.rabbit_register_count(public.rabbit_register_field(raw,'NUMBERBORN')),public.rabbit_register_count(public.rabbit_register_field(raw,'DIED')),
   public.rabbit_register_date(public.rabbit_register_field(raw,'DATEWEANED')),public.rabbit_register_count(public.rabbit_register_field(raw,'NUMBERWEANED')),
   case when public.rabbit_register_flag(public.rabbit_register_field(raw,'REMOVELITTERCOMPLETE')) is true then 'completed' else 'active' end,left(coalesce(public.rabbit_register_field(raw,'COMMENTS'),''),4000),raw,
   public.rabbit_register_date(public.rabbit_register_field(raw,'DATEPAIRED')),public.rabbit_register_date(public.rabbit_register_field(raw,'DATESPLIT')),public.rabbit_register_date(public.rabbit_register_field(raw,'SCHEDULEDBREEDINGDATE')),
   public.rabbit_register_flag(public.rabbit_register_field(raw,'BREEDINGOCCURRED')),public.rabbit_register_flag(public.rabbit_register_field(raw,'INSTALLNESTBOXCOMPLETE')),public.rabbit_register_flag(public.rabbit_register_field(raw,'REMOVENESTBOXCOMPLETE')),
   public.rabbit_register_flag(public.rabbit_register_field(raw,'REBREEDINGENABLED')),public.rabbit_register_flag(public.rabbit_register_field(raw,'REBREEDINGOVERRIDDEN')),
   left(coalesce(public.rabbit_register_field(raw,'CAGE'),''),100),left(coalesce(public.rabbit_register_field(raw,'BREEDNAMEDECODED'),''),100),public.rabbit_register_field(raw,'PALPATERESULTS'),
   public.rabbit_register_count(public.rabbit_register_field(raw,'ADDED')),public.rabbit_register_count(public.rabbit_register_field(raw,'RAISED')),public.rabbit_register_count(public.rabbit_register_field(raw,'BUCKS')),public.rabbit_register_count(public.rabbit_register_field(raw,'DOES')),
   public.rabbit_register_count(public.rabbit_register_field(raw,'KEPT')),public.rabbit_register_count(public.rabbit_register_field(raw,'SOLD')),public.rabbit_register_count(public.rabbit_register_field(raw,'SHOWQUALITY')),custom) on conflict do nothing;
  -- DIED includes later deaths, so it must not be relabelled as stillborn.
 end loop;
 for r in select * from public.rabbit_register_records where ring_id=p_ring and source=p_source loop
  raw:=r.record->'raw';
  if r.kind='show' then
   select * into a from public.animals where id=r.animal_id;
   insert into public.breeder_show_history(owner_id,source_app,source_entry_id,animal_id,exhibitor_source_id,record)
   values(owner,'rabbit_register',md5(jsonb_build_array(p_ring,p_source,'show',r.source_id)::text)::uuid,r.animal_id,md5(owner)::uuid,
   jsonb_build_object('animal_name',coalesce(a.name,''),'tattoo',coalesce(a.tattoo,''),'breed',coalesce(a.breed,''),'variety',coalesce(a.variety,''),'sex',coalesce(a.sex,''),
   'shows',jsonb_build_object('name',public.rabbit_register_field(raw,'ShowName'),'start_date',public.rabbit_register_date(public.rabbit_register_field(raw,'ShowDate')),'location',public.rabbit_register_field(raw,'Location')),
   'placement',public.rabbit_register_field(raw,'RankInClass'),'special_awards',coalesce(public.rabbit_register_field(raw,'WINS'),''),'judge',public.rabbit_register_field(raw,'Judge'),'is_leg',public.rabbit_register_flag(public.rabbit_register_field(raw,'IsALeg')) is true,'is_youth',public.rabbit_register_flag(public.rabbit_register_field(raw,'IsAYouthShow')) is true,
   'number_in_class',public.rabbit_register_field(raw,'NumberInClass'),'number_of_exhibitors',public.rabbit_register_field(raw,'NumberOfExhibitors'),'total_shown',public.rabbit_register_field(raw,'TotalShown'),'comments',public.rabbit_register_field(raw,'Comments'),'other_winnings',public.rabbit_register_field(raw,'OtherWinnings'),'date_qualifier',public.rabbit_register_field(raw,'ShowDateTag'),'pedigree_rank',public.rabbit_register_field(raw,'Rank'),'source','Rabbit Register','raw',raw)) on conflict do nothing;
  elsif r.kind='weight' and r.animal_id is not null then
   dt:=(r.record->>'recorded_date')::date;wt:=(r.record->>'weight')::numeric;fw:=public.rabbit_register_number(public.rabbit_register_field(raw,'FEEDWT'))/453.592;aid:=r.native_weight_id;
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
   dt:=public.rabbit_register_date(public.rabbit_register_field(raw,'WEIGHINGDATE'));wt:=public.rabbit_register_number(public.rabbit_register_field(raw,'LITTERWT'))/453.592;fw:=public.rabbit_register_number(public.rabbit_register_field(raw,'FEEDWT'))/453.592;bid:=null;
   select id into bid from public.breeding_records where import_ring_id=p_ring and import_source=p_source and import_source_id=public.rabbit_register_field(raw,'LITTERKEY');
   if bid is not null and dt is not null and (wt>0 and wt<1000 or fw>=0 and fw<1000000) then
    insert into public.litter_weights(breeding_id,weight,feed_weight,recorded_date,import_source,import_source_id) values(bid,case when wt>0 and wt<1000 then wt end,case when fw>=0 and fw<1000000 then fw end,dt,p_source,r.source_id) on conflict do nothing;
   else notices:=notices||jsonb_build_array('Litter weight '||r.source_id||': missing litter, date or usable measurement; retained in source history.');end if;
  elsif r.kind='wool' and r.animal_id is not null and r.native_wool_id is null then
   wt:=public.rabbit_register_number(public.rabbit_register_field(raw,'FLEECEWT'));
   insert into public.animal_wool_records(animal_id,recorded_date,fleece_grams,measurements,notes,import_source,import_source_id)
   values(r.animal_id,case when public.rabbit_register_date(public.rabbit_register_field(raw,'SHEARDATE'))<=current_date then public.rabbit_register_date(public.rabbit_register_field(raw,'SHEARDATE')) end,case when wt>0 and wt<1000000 then wt end,raw,coalesce(public.rabbit_register_field(raw,'COMMENTS'),''),p_source,r.source_id) on conflict do nothing;
   select id into aid from public.animal_wool_records where animal_id=r.animal_id and import_source=p_source and import_source_id=r.source_id;
   update public.rabbit_register_records set native_wool_id=aid where ring_id=p_ring and source=p_source and kind='wool' and source_id=r.source_id;
  elsif r.kind='wool' and r.native_wool_id is null then
   notices:=notices||jsonb_build_array('Wool record '||r.source_id||': rabbit reference needs review. Link it from source history.');
  end if;
 end loop;
 return jsonb_build_object('status','linked','warnings',notices);
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
 if public.rabbit_register_field(p_data->'header','Species') is not null and lower(public.rabbit_register_field(p_data->'header','Species'))<>'rabbit' then raise exception 'Select a Rabbit Register rabbit export'; end if;
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
   if lower(coalesce(public.rabbit_register_field(prior.raw,'Name'),'')) is distinct from lower(coalesce(public.rabbit_register_field(n->'raw','Name'),''))
    or lower(coalesce(public.rabbit_register_field(prior.raw,'Ear_Num'),'')) is distinct from lower(coalesce(public.rabbit_register_field(n->'raw','Ear_Num'),''))
    or lower(coalesce(public.rabbit_register_field(prior.raw,'Breed'),'')) is distinct from lower(coalesce(public.rabbit_register_field(n->'raw','Breed'),'')) then
    issues:=issues||jsonb_build_array('Source ID '||sid||' has changed identity. Check that this is the same Rabbit Register database.');
   elsif prior.raw is distinct from n->'raw' then warnings:=warnings||jsonb_build_array('Rabbit '||sid||' was imported before; its existing details and first source snapshot will be preserved.'); end if;
   if chosen is not null and chosen<>aid::text then issues:=issues||jsonb_build_array('Rabbit '||sid||' already has an import identity.'); end if;
  else
   -- Ear number alone is never sufficient. Require an explicit decision for
   -- every exact candidate; otherwise retain distinct source IDs as distinct rabbits.
   select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'tattoo',a.tattoo,'status',a.status) order by a.id),'[]') into candidates
    from public.animals a where a.ring_id=p_ring and a.species='rabbit'
    and nullif(btrim(n->>'tattoo'),'') is not null and nullif(btrim(public.rabbit_register_field(n->'raw','Name')),'') is not null
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
    values(p_ring,jsonb_build_array(p_source,sid)::text,n->>'name',nullif(n->>'tattoo',''),'rabbit',nullif(n->>'breed',''),nullif(n->>'variety',''),n->>'sex',nullif(n->>'dob','')::date,case when n->>'status'='active' then 'active' else 'archived' end,nullif(n->>'registration_number',''),nullif(n->>'grand_champion_number',''),nullif(n->>'legs','')::integer,nullif(n->>'notes','')) returning id into aid;
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

create or replace function public.link_rabbit_register_wool(p_ring uuid,p_source text,p_source_id text,p_animal uuid) returns uuid
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
 raw:=r.record->'raw';grams:=public.rabbit_register_number(public.rabbit_register_field(raw,'FLEECEWT'));dt:=public.rabbit_register_date(public.rabbit_register_field(raw,'SHEARDATE'));
 insert into public.animal_wool_records(animal_id,recorded_date,fleece_grams,measurements,notes,import_source,import_source_id)
 values(p_animal,case when dt<=current_date then dt end,case when grams>0 and grams<1000000 then grams end,raw,coalesce(public.rabbit_register_field(raw,'COMMENTS'),''),p_source,p_source_id)
 on conflict(animal_id,import_source,import_source_id) do nothing;
 select id into result from public.animal_wool_records where animal_id=p_animal and import_source=p_source and import_source_id=p_source_id;
 update public.rabbit_register_records set native_wool_id=result where ring_id=p_ring and source=p_source and kind='wool' and source_id=p_source_id;
 return result;
end $$;

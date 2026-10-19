-- Kintraks identities are independent of filenames and export targets.
-- Import previews never write. The final RPC writes animals and source history
-- together under the caller's RLS policies, serialized per destination herd.
alter table public.animals add column kintraks_identity text;
create unique index animals_kintraks_identity_unique
 on public.animals(ring_id,kintraks_identity) where kintraks_identity is not null;
drop index public.animals_herd_tattoo_unique;
create unique index animals_herd_tattoo_unique on public.animals(ring_id,lower(btrim(tattoo)))
 where nullif(btrim(tattoo),'') is not null and global_pedigree_identity is null and rabbit_register_identity is null and kintraks_identity is null;

create table public.kintraks_sources (
 ring_id uuid not null references public.farms(id) on delete cascade,
 source text not null check(length(source) between 1 and 120),
 imported_at timestamptz not null default now(),
 primary key(ring_id,source)
);
create table public.kintraks_animals (
 ring_id uuid not null,
 source text not null,
 source_id text not null check(length(source_id) between 1 and 100),
 animal_id uuid not null references public.animals(id) on delete cascade,
 raw jsonb not null check(jsonb_typeof(raw)='object'),
 profile_weight numeric,
 decisions jsonb not null default '{}' check(jsonb_typeof(decisions)='object'),
 imported_at timestamptz not null default now(),
 primary key(ring_id,source,source_id),
 foreign key(ring_id,source) references public.kintraks_sources on delete cascade
);
create index kintraks_animals_animal on public.kintraks_animals(animal_id);
alter table public.kintraks_sources enable row level security;
alter table public.kintraks_animals enable row level security;
create policy own_kintraks_sources on public.kintraks_sources for all to authenticated
 using(exists(select 1 from public.farms f where f.id=ring_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false)))
 with check(exists(select 1 from public.farms f where f.id=ring_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false)));
create policy own_kintraks_animals on public.kintraks_animals for all to authenticated
 using(exists(select 1 from public.farms f where f.id=ring_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false)))
 with check(exists(select 1 from public.farms f join public.animals a on a.ring_id=f.id
  where f.id=kintraks_animals.ring_id and a.id=kintraks_animals.animal_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false)));
revoke all on public.kintraks_sources,public.kintraks_animals from public,anon,authenticated;
grant select,insert on public.kintraks_sources,public.kintraks_animals to authenticated;

create function public.import_kintraks(p_ring uuid,p_source text,p_data jsonb,p_commit boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
#variable_conflict use_variable
declare
 animals jsonb:=p_data->'animals';
 nodes jsonb:='{}'; ids jsonb:='{}'; fresh jsonb:='{}'; rows jsonb:='[]';
 issues jsonb:='[]'; warnings jsonb:='[]'; candidates jsonb; prior public.kintraks_animals;
 n jsonb; corrections jsonb; effective jsonb; sid text; parent text; side text; weight_text text; pounds numeric; ounces integer; expected_weight numeric;
 aid uuid; dt date; chosen text; added int:=0; existing int:=0; history_added int:=0;
 done text[]:='{}'; visiting text[]:='{}'; frames jsonb; frame jsonb; current_key text;
begin
 if auth.uid() is null then raise exception 'Sign in to import'; end if;
 perform 1 from public.farms f where f.id=p_ring and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false) for update;
 if not found then raise exception 'Select a herd you own'; end if;
 p_source:=lower(btrim(p_source));
 if p_source is null or length(p_source) not between 1 and 120 then raise exception 'Name the source Kintraks database'; end if;
 if jsonb_typeof(animals) is distinct from 'array' then raise exception 'Invalid import data'; end if;
 if jsonb_array_length(animals) not between 1 and 2000 or octet_length(p_data::text)>15000000 then raise exception 'Import is too large'; end if;

 for n in select value from jsonb_array_elements(animals) loop
  sid:=n->>'source_id';
  if jsonb_typeof(n) is distinct from 'object' or sid is null or sid !~ '^[1-9][0-9]{0,9}$' or jsonb_typeof(n->'raw') is distinct from 'object' then raise exception 'Invalid rabbit record'; end if;
  if nodes ? sid then raise exception 'Duplicate source animal ID'; end if;
  corrections:=coalesce(n->'corrections','{}'::jsonb);
  if jsonb_typeof(corrections) is distinct from 'object' then raise exception 'Invalid corrections'; end if;
  if exists(select 1 from jsonb_each(corrections) e where e.key in ('Id','_csv_headers') or not (n->'raw' ? e.key) or jsonb_typeof(e.value)<>'string') then raise exception 'Corrections must edit existing CSV fields, never source IDs'; end if;
  effective:=(n->'raw')||corrections;
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
  if jsonb_typeof(n->'pedigree_only') is distinct from 'boolean'
   or (n->>'status'='archived' and n->>'pedigree_only'<>'true')
   or (n->>'status'<>'archived' and n->>'pedigree_only'<>'false') then
   issues:=issues||jsonb_build_array('Rabbit '||sid||' has an invalid herd/pedigree choice.');
  end if;
  if lower(coalesce(effective->>'Deceased','')) not in ('true','false','') or lower(coalesce(effective->>'Sold','')) not in ('true','false','') then
   issues:=issues||jsonb_build_array('Rabbit '||sid||' has invalid source status flags.');
  elsif lower(effective->>'Deceased')='true' and n->>'status'<>'deceased' then
   issues:=issues||jsonb_build_array('Rabbit '||sid||' must retain its deceased status.');
  elsif lower(coalesce(effective->>'Deceased',''))<>'true' and lower(effective->>'Sold')='true' and n->>'status'<>'sold' then
   issues:=issues||jsonb_build_array('Rabbit '||sid||' must retain its sold status.');
  end if;
  if jsonb_typeof(n->'raw'->'_csv_headers') is distinct from 'array' then raise exception 'Missing original CSV headers'; end if;
  begin
   weight_text:=nullif(btrim(effective->>'Weight'),''); expected_weight:=null;
   if weight_text is not null then
    if weight_text !~ '^[0-9]+([.][0-9]{1,2})?$' then raise exception 'Invalid source weight'; end if;
    pounds:=split_part(weight_text,'.',1)::numeric;
    ounces:=coalesce(nullif(split_part(weight_text,'.',2),''),'0')::integer;
    if ounces>15 or pounds>=1000 then raise exception 'Invalid source weight'; end if;
    expected_weight:=nullif(pounds+ounces/16.0,0);
   end if;
   if expected_weight is distinct from nullif(n->>'profile_weight','')::numeric then raise exception 'Weight conversion mismatch'; end if;
  exception when others then issues:=issues||jsonb_build_array('Rabbit '||sid||' has an invalid pounds-and-ounces weight conversion.'); end;
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
    if nodes ? parent and nullif(n->>'dob','') is not null and nullif(nodes->parent->>'dob','') is not null
     and nodes->parent->>'dob'>=n->>'dob' then
     warnings:=warnings||jsonb_build_array('Rabbit '||sid||' has a birth date on or before parent '||parent||'. Dates are preserved as exported.');
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
  select * into prior from public.kintraks_animals g where g.ring_id=p_ring and g.source=p_source and g.source_id=sid;
  if found then
   aid:=prior.animal_id;
   -- A reused label must never silently map another breeder's numeric IDs.
   if lower(coalesce(prior.raw->>'Prefix','')) is distinct from lower(coalesce(n->'raw'->>'Prefix',''))
    or lower(coalesce(prior.raw->>'Suffix','')) is distinct from lower(coalesce(n->'raw'->>'Suffix',''))
    or lower(coalesce(prior.raw->>'Name','')) is distinct from lower(coalesce(n->'raw'->>'Name',''))
    or lower(coalesce(prior.raw->>'Ear #','')) is distinct from lower(coalesce(n->'raw'->>'Ear #',''))
    or lower(coalesce(prior.raw->>'Breed','')) is distinct from lower(coalesce(n->'raw'->>'Breed','')) then
    issues:=issues||jsonb_build_array('Source ID '||sid||' has changed identity. Check that this is the same Kintraks database.');
   elsif prior.raw is distinct from n->'raw' then warnings:=warnings||jsonb_build_array('Rabbit '||sid||' was imported before; its existing details and first source snapshot will be preserved.'); end if;
   if coalesce(prior.decisions->'corrections','{}'::jsonb) is distinct from coalesce(n->'corrections','{}'::jsonb) then warnings:=warnings||jsonb_build_array('Rabbit '||sid||' already exists; new corrections will not overwrite its details or original review.'); end if;
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
 -- All source warnings need explicit review, including ownership and lb.oz.
 if not coalesce((p_data->>'warnings_acknowledged')::boolean,false) then
  issues:=issues||jsonb_build_array('Review and acknowledge the source warnings before importing.');
 end if;
 if not coalesce(p_commit,false) or jsonb_array_length(issues)>0 then
  return jsonb_build_object('status','preview','animals_added',added,'animals_existing',existing,'history_count',jsonb_array_length(animals),'issues',issues,'warnings',warnings,'rows',rows);
 end if;
 insert into public.kintraks_sources(ring_id,source) values(p_ring,p_source) on conflict do nothing;
 for sid,n in select key,value from jsonb_each(nodes) loop
  if not ids ? sid then
   insert into public.animals(ring_id,kintraks_identity,name,tattoo,species,breed,variety,sex,dob,status,registration_number,grand_champion_number,legs,notes,pedigree_only)
    values(p_ring,jsonb_build_array(p_source,sid)::text,n->>'name',nullif(n->>'tattoo',''),'rabbit',nullif(n->>'breed',''),nullif(n->>'variety',''),n->>'sex',nullif(n->>'dob','')::date,'active',nullif(n->>'registration_number',''),nullif(n->>'grand_champion_number',''),nullif(n->>'legs','')::integer,nullif(n->>'notes',''),coalesce((n->>'pedigree_only')::boolean,false)) returning id into aid;
   ids:=ids||jsonb_build_object(sid,aid);fresh:=fresh||jsonb_build_object(sid,true);
  end if;
  insert into public.kintraks_animals(ring_id,source,source_id,animal_id,raw,profile_weight,decisions)
   values(p_ring,p_source,sid,(ids->>sid)::uuid,n->'raw',nullif(n->>'profile_weight','')::numeric,jsonb_build_object('sex',n->>'sex','sire_id',n->>'sire_id','dam_id',n->>'dam_id','existing_id',n->>'existing_id','status',n->>'status','pedigree_only',n->'pedigree_only','corrections',coalesce(n->'corrections','{}'::jsonb))) on conflict do nothing;
  if found then history_added:=history_added+1; end if;
 end loop;
 -- Set links before final status, respecting normal historical-animal locks.
 for sid,n in select key,value from jsonb_each(nodes) loop
  if fresh ? sid then
   update public.animals set sire_id=(ids->>(n->>'sire_id'))::uuid,dam_id=(ids->>(n->>'dam_id'))::uuid,status=n->>'status' where id=(ids->>sid)::uuid;
  end if;
 end loop;
 return jsonb_build_object('status','imported','animals_added',added,'animals_existing',existing,'history_added',history_added,'issues','[]'::jsonb,'warnings',warnings);
end $$;
revoke all on function public.import_kintraks(uuid,text,jsonb,boolean) from public,anon;
grant execute on function public.import_kintraks(uuid,text,jsonb,boolean) to authenticated;

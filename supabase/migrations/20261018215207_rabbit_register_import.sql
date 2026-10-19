-- Rabbit Register identities are independent of filenames and export targets.
-- Import previews never write. The final RPC writes animals and source history
-- together under the caller's RLS policies, serialized per destination herd.
alter table public.animals add column rabbit_register_identity text;
create unique index animals_rabbit_register_identity_unique
 on public.animals(ring_id,rabbit_register_identity) where rabbit_register_identity is not null;
drop index public.animals_herd_tattoo_unique;
create unique index animals_herd_tattoo_unique on public.animals(ring_id,lower(btrim(tattoo)))
 where nullif(btrim(tattoo),'') is not null and global_pedigree_identity is null and rabbit_register_identity is null;

create table public.rabbit_register_sources (
 ring_id uuid not null references public.farms(id) on delete cascade,
 source text not null check(length(source) between 1 and 120),
 imported_at timestamptz not null default now(),
 primary key(ring_id,source)
);
create table public.rabbit_register_animals (
 ring_id uuid not null,
 source text not null,
 source_id text not null check(length(source_id) between 1 and 100),
 animal_id uuid not null references public.animals(id) on delete cascade,
 raw jsonb not null check(jsonb_typeof(raw)='object'),
 profile_weight numeric,
 decisions jsonb not null default '{}' check(jsonb_typeof(decisions)='object'),
 imported_at timestamptz not null default now(),
 primary key(ring_id,source,source_id),
 foreign key(ring_id,source) references public.rabbit_register_sources on delete cascade
);
create index rabbit_register_animals_animal on public.rabbit_register_animals(animal_id);
create table public.rabbit_register_records (
 ring_id uuid not null,
 source text not null,
 kind text not null check(kind in ('contact','litter','show','weight')),
 source_id text not null check(length(source_id) between 1 and 100),
 animal_id uuid references public.animals(id) on delete set null,
 sire_id uuid references public.animals(id) on delete set null,
 record jsonb not null check(jsonb_typeof(record)='object'),
 imported_at timestamptz not null default now(),
 primary key(ring_id,source,kind,source_id),
 foreign key(ring_id,source) references public.rabbit_register_sources on delete cascade
);
create index rabbit_register_records_animal on public.rabbit_register_records(animal_id);
create index rabbit_register_records_sire on public.rabbit_register_records(sire_id);

alter table public.rabbit_register_sources enable row level security;
alter table public.rabbit_register_animals enable row level security;
alter table public.rabbit_register_records enable row level security;
create policy own_rabbit_register_sources on public.rabbit_register_sources for all to authenticated
 using(exists(select 1 from public.farms f where f.id=ring_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false)))
 with check(exists(select 1 from public.farms f where f.id=ring_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false)));
create policy own_rabbit_register_animals on public.rabbit_register_animals for all to authenticated
 using(exists(select 1 from public.farms f where f.id=ring_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false)))
 with check(exists(select 1 from public.farms f join public.animals a on a.ring_id=f.id
  where f.id=rabbit_register_animals.ring_id and a.id=rabbit_register_animals.animal_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false)));
create policy own_rabbit_register_records on public.rabbit_register_records for all to authenticated
 using(exists(select 1 from public.farms f where f.id=ring_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false)))
 with check(exists(select 1 from public.farms f where f.id=ring_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false))
  and (animal_id is null or exists(select 1 from public.animals a where a.id=rabbit_register_records.animal_id and a.ring_id=rabbit_register_records.ring_id))
  and (sire_id is null or exists(select 1 from public.animals a where a.id=rabbit_register_records.sire_id and a.ring_id=rabbit_register_records.ring_id)));
revoke all on public.rabbit_register_sources,public.rabbit_register_animals,public.rabbit_register_records from public,anon,authenticated;
grant select,insert on public.rabbit_register_sources,public.rabbit_register_animals,public.rabbit_register_records to authenticated;

create function public.import_rabbit_register(p_ring uuid,p_source text,p_data jsonb,p_commit boolean default false)
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
 if jsonb_array_length(animals) not between 1 and 2000 or jsonb_array_length(records)>20000 or octet_length(p_data::text)>15000000 then raise exception 'Import is too large'; end if;
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
  if jsonb_typeof(r) is distinct from 'object' or kind is null or kind not in ('contact','show','litter','weight') or sid is null or sid !~ '^[1-9][0-9]{0,9}$' or jsonb_typeof(r->'raw') is distinct from 'object' or octet_length(r::text)>100000 then raise exception 'Invalid source history record'; end if;
  if k=any(seen) then raise exception 'Duplicate history source ID'; end if;seen:=array_append(seen,k);
  foreach side in array array['animal_source_id','sire_source_id'] loop
   parent:=nullif(r->>side,'');
   if parent is not null and not nodes ? parent then warnings:=warnings||jsonb_build_array(kind||' '||sid||' references absent rabbit '||parent||'; source history will remain unlinked.'); end if;
  end loop;
  if kind='weight' then
   begin
    dt:=(r->>'recorded_date')::date;
    if dt is null or dt>current_date or dt<date '1800-01-01' or not (coalesce((r->>'weight')::numeric,0)>0 and (r->>'weight')::numeric<1000) then raise exception 'Invalid measurement'; end if;
   exception when others then issues:=issues||jsonb_build_array('Weight '||sid||' needs a valid measurement and date.'); end;
  end if;
 end loop;
 if jsonb_array_length(warnings)>0 and not coalesce((p_data->>'warnings_acknowledged')::boolean,false) then issues:=issues||jsonb_build_array('Acknowledge the source warnings before importing.');end if;
 if not coalesce(p_commit,false) or jsonb_array_length(issues)>0 then
  return jsonb_build_object('status','preview','animals_added',added,'animals_existing',existing,'history_count',jsonb_array_length(records),'issues',issues,'warnings',warnings,'rows',rows);
 end if;
 insert into public.rabbit_register_sources(ring_id,source) values(p_ring,p_source) on conflict do nothing;
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
  if r->>'kind'='weight' and aid is not null and fresh ? (r->>'animal_source_id') then
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
 return jsonb_build_object('status','imported','animals_added',added,'animals_existing',existing,'history_added',history_added,'issues','[]'::jsonb,'warnings',warnings);
end $$;
revoke all on function public.import_rabbit_register(uuid,text,jsonb,boolean) from public,anon;
grant execute on function public.import_rabbit_register(uuid,text,jsonb,boolean) to authenticated;

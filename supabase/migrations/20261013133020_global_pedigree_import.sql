-- Source identities are scoped to a destination herd and Global Pedigree account.
-- Ordinary RLS applies to both the preview and the atomic commit.
create table public.global_pedigree_animals (
 ring_id uuid not null references public.farms(id) on delete cascade,
 source_account text not null,
 source_id text not null,
 animal_id uuid not null references public.animals(id) on delete cascade,
 imported_at timestamptz not null default now(),
 primary key(ring_id,source_account,source_id)
);
alter table public.global_pedigree_animals enable row level security;
create policy own_global_pedigree_animals on public.global_pedigree_animals
 for all to authenticated
 using(exists(select 1 from public.farms f where f.id=global_pedigree_animals.ring_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false)))
 with check(exists(select 1 from public.farms f join public.animals a on a.ring_id=f.id
 where f.id=global_pedigree_animals.ring_id and a.id=global_pedigree_animals.animal_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false)));
revoke all on public.global_pedigree_animals from anon,authenticated;
grant select,insert on public.global_pedigree_animals to authenticated;

create function public.import_global_pedigree(p_ring uuid,p_account text,p_animals jsonb,p_commit boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
#variable_conflict use_variable
declare
 r jsonb; n jsonb; nodes jsonb:='{}'; ids jsonb:='{}'; actions jsonb:='{}';
 issues jsonb:='[]'; rows jsonb:='[]'; aid uuid; matched public.animals;
 source_id text; side text; parent text; sex text; tattoo text; dt date;
 added int:=0; existing int:=0; seen text[]:='{}'; stack text[]; current_key text;
 done text[]:='{}'; visiting text[]:='{}'; frames jsonb; frame jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in to import'; end if;
 -- Serializes simultaneous imports into this herd before resolving duplicates.
 perform 1 from public.farms f where f.id=p_ring and breeder_private.owns(f.owner_id)
 and not coalesce(f.is_demo,false) for update;
 if not found then raise exception 'Select a herd you own'; end if;
 if nullif(btrim(p_account),'') is null or length(p_account)>200 then raise exception 'Missing source account'; end if;
 if jsonb_typeof(p_animals) is distinct from 'array' then raise exception 'Invalid records'; end if;
 if jsonb_array_length(p_animals)=0 or jsonb_array_length(p_animals)>2000 then raise exception 'Import must contain 1 to 2000 records'; end if;
 for r in select value from jsonb_array_elements(p_animals) loop
  source_id:=nullif(btrim(r->>'source_id'),'');
  if source_id is null or length(source_id)>100 then raise exception 'Missing source animal ID'; end if;
  if nodes ? source_id then raise exception 'Duplicate source animal ID'; end if;
  if jsonb_typeof(r) is distinct from 'object' then raise exception 'Invalid animal record'; end if;
  if coalesce(nullif(btrim(r->>'name'),''),nullif(btrim(r->>'tattoo'),'')) is null then
   issues:=issues||jsonb_build_array('Record '||source_id||' needs a name or ear number.');
  end if;
  sex:=case lower(btrim(r->>'sex')) when 'm' then 'Buck' when 'male' then 'Buck' when 'buck' then 'Buck' when 'f' then 'Doe' when 'female' then 'Doe' when 'doe' then 'Doe' else null end;
  if sex is null then issues:=issues||jsonb_build_array('Record '||source_id||' needs a valid sex.'); end if;
  if coalesce(r->>'status','active') not in ('active','sold','retired','deceased') then
   issues:=issues||jsonb_build_array('Record '||source_id||' has an unsupported status.');
  end if;
  begin
   dt:=nullif(r->>'dob','')::date;
   if dt>current_date then raise exception 'Future date'; end if;
  exception when others then
   issues:=issues||jsonb_build_array('Record '||source_id||' has an invalid birth date.');
  end;
  begin
   if nullif(r->>'weight','') is not null and ((r->>'weight')::numeric<=0 or (r->>'weight')::numeric>=1000) then raise exception 'Invalid weight'; end if;
   if nullif(r->>'legs','') is not null and (r->>'legs')::integer<0 then raise exception 'Invalid legs'; end if;
  exception when others then
   issues:=issues||jsonb_build_array('Record '||source_id||' has an invalid weight or leg count.');
  end;
  nodes:=nodes||jsonb_build_object(source_id,r||jsonb_build_object('sex',sex));
 end loop;
 -- Validate all edges and parent sexes before creating any records.
 for source_id,n in select key,value from jsonb_each(nodes) loop
  foreach side in array array['sire_id','dam_id'] loop
   parent:=nullif(n->>side,'');
   if parent is not null then
    if not nodes ? parent then
     issues:=issues||jsonb_build_array('Record '||source_id||' is missing its '||split_part(side,'_',1)||' record '||parent||'.');
    elsif nodes->parent->>'sex' is distinct from (case side when 'sire_id' then 'Buck' else 'Doe' end) then
     issues:=issues||jsonb_build_array('Record '||source_id||' has a parent with the wrong sex.');
    end if;
   end if;
  end loop;
 end loop;
 -- Iterative depth-first walk avoids unbounded recursion and exponential paths.
 for source_id in select key from jsonb_each(nodes) loop
  frames:=jsonb_build_array(jsonb_build_object('id',source_id,'exit',false));
  while jsonb_array_length(frames)>0 loop
   frame:=frames->(jsonb_array_length(frames)-1);
   frames:=frames-(jsonb_array_length(frames)-1);
   current_key:=frame->>'id';
   if (frame->>'exit')::boolean then
    visiting:=array_remove(visiting,current_key); done:=array_append(done,current_key);
   elsif current_key=any(visiting) then
    issues:=issues||jsonb_build_array('Pedigree cycle at record '||current_key||'.');
    frames:='[]';
   elsif not current_key=any(done) and nodes ? current_key then
    visiting:=array_append(visiting,current_key);
    frames:=frames||jsonb_build_array(jsonb_build_object('id',current_key,'exit',true));
    foreach side in array array['sire_id','dam_id'] loop
     parent:=nullif(nodes->current_key->>side,'');
     if parent is not null then frames:=frames||jsonb_build_array(jsonb_build_object('id',parent,'exit',false)); end if;
    end loop;
   end if;
  end loop;
 end loop;
 for source_id,n in select key,value from jsonb_each(nodes) loop
  aid:=null; matched:=null;
  select a.* into matched from public.global_pedigree_animals g join public.animals a on a.id=g.animal_id
   where g.ring_id=p_ring and g.source_account=p_account and g.source_id=source_id and a.ring_id=p_ring;
  if found then
   aid:=matched.id;
   actions:=actions||jsonb_build_object(source_id,'Already imported');
  else
   tattoo:=nullif(btrim(n->>'tattoo'),'');
   if tattoo is not null then
    if lower(tattoo)=any(seen) then
     issues:=issues||jsonb_build_array('Multiple source records use ear number '||tattoo||'.');
    end if;
    seen:=array_append(seen,lower(tattoo));
    select a.* into matched from public.animals a where a.ring_id=p_ring and lower(btrim(a.tattoo))=lower(tattoo);
    if found then
     if matched.species<>'rabbit' or matched.sex is distinct from n->>'sex'
      or (nullif(btrim(matched.breed),'') is not null and nullif(btrim(n->>'breed'),'') is not null and public.catalog_key(matched.breed)<>public.catalog_key(n->>'breed')) then
      issues:=issues||jsonb_build_array('Ear number '||tattoo||' conflicts with an existing animal.');
     else aid:=matched.id; end if;
    end if;
   end if;
   actions:=actions||jsonb_build_object(source_id,case when aid is null then 'New record' else 'Existing animal preserved' end);
  end if;
  if aid is not null then
   existing:=existing+1; ids:=ids||jsonb_build_object(source_id,aid);
  else added:=added+1; end if;
  rows:=rows||jsonb_build_array(jsonb_build_object('source_id',source_id,'name',n->>'name','tattoo',n->>'tattoo','sex',n->>'sex','breed',n->>'breed','pedigree_only',coalesce((n->>'pedigree_only')::boolean,false),'action',actions->>source_id));
 end loop;
 if not p_commit or jsonb_array_length(issues)>0 then
  return jsonb_build_object('status','preview','animals_added',added,'animals_existing',existing,'issues',issues,'rows',rows);
 end if;
 -- Two passes allow shared ancestors and any input ordering. One transaction means no partial import.
 for source_id,n in select key,value from jsonb_each(nodes) loop
  if ids->>source_id is null then
   insert into public.animals(ring_id,name,tattoo,species,breed,variety,sex,dob,status,registration_number,grand_champion_number,legs,pedigree_only,notes)
   values(p_ring,nullif(btrim(n->>'name'),''),nullif(btrim(n->>'tattoo'),''),'rabbit',nullif(n->>'breed',''),nullif(n->>'variety',''),n->>'sex',nullif(n->>'dob','')::date,'active',nullif(n->>'registration_number',''),nullif(n->>'grand_champion_number',''),nullif(n->>'legs','')::integer,coalesce((n->>'pedigree_only')::boolean,false),nullif(n->>'notes','')) returning id into aid;
   ids:=ids||jsonb_build_object(source_id,aid);
   if nullif(n->>'weight','') is not null then
    insert into public.animal_weights(animal_id,weight) values(aid,(n->>'weight')::numeric);
   end if;
  end if;
  insert into public.global_pedigree_animals(ring_id,source_account,source_id,animal_id)
   values(p_ring,p_account,source_id,(ids->>source_id)::uuid) on conflict do nothing;
 end loop;
 for source_id,n in select key,value from jsonb_each(nodes) loop
  if actions->>source_id='New record' then
   update public.animals set sire_id=(ids->>(n->>'sire_id'))::uuid,dam_id=(ids->>(n->>'dam_id'))::uuid,
    status=coalesce(n->>'status','active') where id=(ids->>source_id)::uuid;
  end if;
 end loop;
 return jsonb_build_object('status','imported','animals_added',added,'animals_existing',existing,'issues','[]'::jsonb);
end $$;
revoke all on function public.import_global_pedigree(uuid,text,jsonb,boolean) from public,anon;
grant execute on function public.import_global_pedigree(uuid,text,jsonb,boolean) to authenticated;

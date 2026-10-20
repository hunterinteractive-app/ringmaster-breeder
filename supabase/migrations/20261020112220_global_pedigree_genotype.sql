-- Prepared only; depends on the animal_genotype_record migration.
-- Preserve source evidence separately when an existing animal or merge wins.
alter table public.global_pedigree_animals add column source_known_genotype text
 check (source_known_genotype is null or length(source_known_genotype) <= 500);
comment on column public.global_pedigree_animals.source_known_genotype is
 'Global Pedigree Known Genotype text; source reference only, not laboratory verification.';
-- Existing owner/animal RLS applies. Only this provenance column becomes updateable.
grant update(source_known_genotype) on public.global_pedigree_animals to authenticated;

create or replace function public.import_global_pedigree(p_ring uuid,p_account text,p_animals jsonb,p_commit boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
#variable_conflict use_variable
declare
 r jsonb; n jsonb; nodes jsonb:='{}'; ids jsonb:='{}'; actions jsonb:='{}';
 issues jsonb:='[]'; rows jsonb:='[]'; aid uuid; matched public.animals;
 source_id text; side text; parent text; sex text; tattoo text; dt date;
 added int:=0; existing int:=0; seen text[]:='{}'; stack text[]; current_key text;
 original_nodes jsonb; aliases jsonb:='{}'; groups jsonb:='[]'; group_row record; candidate jsonb; canonical text; other jsonb; prior uuid;
 done text[]:='{}'; visiting text[]:='{}'; frames jsonb; frame jsonb;
begin
 p_commit:=coalesce(p_commit,false);
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
  if coalesce(r->>'status','active') not in ('active','sold','retired','deceased','archived') then
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
  if r ? 'known_genotype' and r->'known_genotype'<>'null'::jsonb
     and (jsonb_typeof(r->'known_genotype')<>'string' or length(r->>'known_genotype')>500) then
   issues:=issues||jsonb_build_array('Record '||source_id||' has invalid source genotype information. Contact support@ringmasterone.com for help.');
  end if;
  nodes:=nodes||jsonb_build_object(source_id,r||jsonb_build_object('sex',sex));
 end loop;
 original_nodes:=nodes;
 -- Suggestions use name + ear number + breed + sex, never ear number alone.
 for group_row in
  select jsonb_agg(value order by key) as members from jsonb_each(nodes)
  where nullif(btrim(value->>'name'),'') is not null and nullif(btrim(value->>'tattoo'),'') is not null
   and lower(btrim(value->>'name')) not like 'enter your rabbit%'
  group by lower(btrim(value->>'name')),lower(btrim(value->>'tattoo')),public.catalog_key(value->>'breed'),value->>'sex'
  having count(*)>1
 loop
  groups:=groups||jsonb_build_array(group_row.members);
  for candidate in select value from jsonb_array_elements(group_row.members) loop
   if nullif((candidate->>'same_as'),'') is null and not coalesce(((candidate->>'keep_separate'))::boolean,false) then
    issues:=issues||jsonb_build_array('Review possible duplicate '||(candidate->>'name')||' (source '||(candidate->>'source_id')||').');
   end if;
  end loop;
 end loop;
 -- Explicit alias decisions retain every source ID and rewire all incoming edges.
 for source_id,n in select key,value from jsonb_each(original_nodes) loop
  canonical:=nullif((n->>'same_as'),'');
  if canonical is not null then
   other:=original_nodes->canonical;
   if canonical=source_id or other is null or nullif(other->>'same_as','') is not null then
    issues:=issues||jsonb_build_array('Invalid duplicate choice for source '||source_id||'.'); continue;
   end if;
   if nullif(btrim((n->>'name')),'') is null or nullif(btrim((n->>'tattoo')),'') is null
     or lower(btrim((n->>'name'))) is distinct from lower(btrim(other->>'name'))
     or lower(btrim((n->>'tattoo'))) is distinct from lower(btrim(other->>'tattoo'))
     or public.catalog_key((n->>'breed')) is distinct from public.catalog_key(other->>'breed')
     or (n->>'sex') is distinct from other->>'sex'
     or (nullif((n->>'dob'),'') is not null and nullif(other->>'dob','') is not null and (n->>'dob')<>other->>'dob') then
    issues:=issues||jsonb_build_array('Duplicate choice conflicts with identity or birth date for '||(n->>'name')||'.'); continue;
   end if;
   select g.animal_id into prior from public.global_pedigree_animals g where g.ring_id=p_ring and g.source_account=p_account and g.source_id=source_id;
   if prior is not null and prior is distinct from (select g.animal_id from public.global_pedigree_animals g where g.ring_id=p_ring and g.source_account=p_account and g.source_id=canonical) then
    issues:=issues||jsonb_build_array('These source records were previously imported separately and cannot be merged by an import.'); continue;
   end if;
   aliases:=aliases||jsonb_build_object(source_id,canonical);
   if not coalesce(((n->>'pedigree_only'))::boolean,false) then
    nodes:=jsonb_set(nodes,array[canonical,'pedigree_only'],'false');
    if n->>'source_live'='true' then nodes:=jsonb_set(nodes,array[canonical,'status'],'"active"'); end if;
   end if;
  end if;
 end loop;
 for source_id in select key from jsonb_each(aliases) loop nodes:=nodes-source_id; end loop;
 for source_id,n in select key,value from jsonb_each(nodes) loop
  foreach side in array array['sire_id','dam_id'] loop
   parent:=aliases->>(n->>side);
   if parent is not null then n:=jsonb_set(n,array[side],to_jsonb(parent)); end if;
  end loop;
  nodes:=jsonb_set(nodes,array[source_id],n);
 end loop;
 -- Validate all edges and parent sexes before creating any records.
 for source_id,n in select key,value from jsonb_each(nodes) loop
  foreach side in array array['sire_id','dam_id'] loop
   parent:=nullif(n->>side,'');
   if parent is not null then
    if not nodes ? parent then
     issues:=issues||jsonb_build_array('Record '||source_id||' is missing its '||split_part(side,'_',1)||' record '||parent||'.');
    elsif nodes->parent->>'sex' is not null and nodes->parent->>'sex' is distinct from (case side when 'sire_id' then 'Buck' else 'Doe' end) then
     issues:=issues||jsonb_build_array(coalesce((n->>'name'),source_id)||' has '||coalesce(nodes->parent->>'name',parent)||' in the '||split_part(side,'_',1)||' position with the wrong sex.');
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
   tattoo:=nullif(btrim((n->>'tattoo')),'');
   if tattoo is not null and not coalesce(((n->>'keep_separate'))::boolean,false) and lower(btrim(n->>'name')) not like 'enter your rabbit%' then
    -- Matching requires a full compatible identity. Reused ear numbers stay separate.
    select a.* into matched from public.animals a
    where a.ring_id=p_ring and lower(btrim(a.tattoo))=lower(tattoo) and a.species='rabbit'
     and lower(btrim(a.name))=lower(btrim((n->>'name'))) and a.sex=(n->>'sex')
     and public.catalog_key(a.breed) is not distinct from public.catalog_key((n->>'breed'))
     and a.dob::text is not distinct from nullif((n->>'dob'),'')
     and (select count(*) from public.animals x where x.ring_id=p_ring
       and lower(btrim(x.tattoo))=lower(tattoo) and x.species='rabbit'
       and lower(btrim(x.name))=lower(btrim((n->>'name'))) and x.sex=(n->>'sex')
       and public.catalog_key(x.breed) is not distinct from public.catalog_key((n->>'breed'))
       and x.dob::text is not distinct from nullif((n->>'dob'),''))=1;
    if found then aid:=matched.id; end if;
   end if;
   actions:=actions||jsonb_build_object(source_id,case when aid is null then 'New record' else 'Existing animal preserved' end);
  end if;
  if aid is not null then
   existing:=existing+1; ids:=ids||jsonb_build_object(source_id,aid);
  else added:=added+1; end if;
  rows:=rows||jsonb_build_array(jsonb_build_object('source_id',source_id,'name',(n->>'name'),'tattoo',(n->>'tattoo'),'sex',(n->>'sex'),'breed',(n->>'breed'),'pedigree_only',coalesce(((n->>'pedigree_only'))::boolean,false),'action',actions->>source_id,
   'known_genotype',nullif(btrim(n->>'known_genotype'),''),
   'genotype_action',case when nullif(btrim(n->>'known_genotype'),'') is null then null
    when aid is null then 'Genotype saved as imported reference'
    else 'Existing genotype preserved; incoming value retained with source record' end));
 end loop;
 if not p_commit then
  insert into public.global_pedigree_import_drafts(auth_user_id,ring_id,account,animals,expires_at)
   values(auth.uid(),p_ring,p_account,p_animals,now()+interval '24 hours')
   on conflict(auth_user_id) do update set ring_id=excluded.ring_id,account=excluded.account,animals=excluded.animals,expires_at=excluded.expires_at;
 end if;
 if not p_commit or jsonb_array_length(issues)>0 then
  return jsonb_build_object('status','preview','animals_added',added,'animals_existing',existing,'issues',issues,'rows',rows,'duplicate_groups',groups,'source_records',jsonb_array_length(p_animals),'aliases',aliases);
 end if;
 -- Two passes allow shared ancestors and any input ordering. One transaction means no partial import.
 for source_id,n in select key,value from jsonb_each(nodes) loop
  if ids->>source_id is null then
   insert into public.animals(global_pedigree_identity,ring_id,name,tattoo,species,breed,variety,sex,dob,status,registration_number,grand_champion_number,legs,pedigree_only,notes,genotype)
   values(jsonb_build_array(p_account,source_id)::text,p_ring,nullif(btrim((n->>'name')),''),nullif(btrim((n->>'tattoo')),''),'rabbit',nullif((n->>'breed'),''),nullif((n->>'variety'),''),(n->>'sex'),nullif((n->>'dob'),'')::date,'active',nullif((n->>'registration_number'),''),nullif((n->>'grand_champion_number'),''),nullif((n->>'legs'),'')::integer,coalesce(((n->>'pedigree_only'))::boolean,false),nullif((n->>'notes'),''),
    case when nullif(btrim(n->>'known_genotype'),'') is null then '{}'::jsonb
     else jsonb_build_object('notation',btrim(n->>'known_genotype'),'basis','imported',
       'source','Global Pedigree: Known Genotype (rabbit '||source_id||'). Method not verified.') end) returning id into aid;
   ids:=ids||jsonb_build_object(source_id,aid);
   if nullif((n->>'weight'),'') is not null then
    insert into public.animal_weights(animal_id,weight) values(aid,((n->>'weight'))::numeric);
   end if;
  end if;
  insert into public.global_pedigree_animals(ring_id,source_account,source_id,animal_id,source_known_genotype)
   values(p_ring,p_account,source_id,(ids->>source_id)::uuid,nullif(btrim(n->>'known_genotype'),''))
   on conflict on constraint global_pedigree_animals_pkey do update
    set source_known_genotype=coalesce(excluded.source_known_genotype,public.global_pedigree_animals.source_known_genotype);
 end loop;
 for source_id,canonical in select key,value #>> '{}' from jsonb_each(aliases) loop
  insert into public.global_pedigree_animals(ring_id,source_account,source_id,animal_id,source_known_genotype)
   values(p_ring,p_account,source_id,(ids->>canonical)::uuid,nullif(btrim(original_nodes->source_id->>'known_genotype'),''))
   on conflict on constraint global_pedigree_animals_pkey do update
    set source_known_genotype=coalesce(excluded.source_known_genotype,public.global_pedigree_animals.source_known_genotype);
 end loop;
 for source_id,n in select key,value from jsonb_each(nodes) loop
  if actions->>source_id='New record' then
   update public.animals set sire_id=(ids->>((n->>'sire_id')))::uuid,dam_id=(ids->>((n->>'dam_id')))::uuid,
    status=coalesce((n->>'status'),'active') where id=(ids->>source_id)::uuid;
  end if;
 end loop;
 delete from public.global_pedigree_import_drafts where auth_user_id=auth.uid();
 return jsonb_build_object('status','imported','animals_added',added,'animals_existing',existing,'issues','[]'::jsonb);
end $$;
revoke all on function public.import_global_pedigree(uuid,text,jsonb,boolean) from public,anon;
grant execute on function public.import_global_pedigree(uuid,text,jsonb,boolean) to authenticated;

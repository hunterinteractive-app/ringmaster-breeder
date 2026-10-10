alter table public.animals drop constraint animals_sex_check;
alter table public.animals disable trigger breeder_validate_animal;
update public.animals set sex=case species when 'cavy' then case sex when 'M' then 'Boar' when 'F' then 'Sow' else sex end else case sex when 'M' then 'Buck' when 'F' then 'Doe' else sex end end;
alter table public.animals enable trigger breeder_validate_animal;
alter table public.animals add constraint animals_sex_check check ((species='rabbit' and sex in ('Buck','Doe')) or (species='cavy' and sex in ('Boar','Sow')));
create or replace function breeder_private.validate_animal() returns trigger
language plpgsql set search_path='' as $$
begin
 new.sex := case when lower(btrim(coalesce(new.sex,''))) in ('m','male','buck','boar') then case new.species when 'cavy' then 'Boar' else 'Buck' end when lower(btrim(coalesce(new.sex,''))) in ('f','female','doe','sow') then case new.species when 'cavy' then 'Sow' else 'Doe' end else new.sex end;
 if tg_op='UPDATE' and old.status in ('sold','deceased') then raise exception 'Historical animal is locked'; end if;
 if new.sire_id is not null and not exists(select 1 from public.animals where id=new.sire_id and ring_id=new.ring_id and species=new.species and sex=case new.species when 'cavy' then 'Boar' else 'Buck' end) then raise exception 'Invalid sire'; end if;
 if new.dam_id is not null and not exists(select 1 from public.animals where id=new.dam_id and ring_id=new.ring_id and species=new.species and sex=case new.species when 'cavy' then 'Sow' else 'Doe' end) then raise exception 'Invalid dam'; end if;
 if new.dob>current_date then raise exception 'Birth date cannot be in the future'; end if;
 return new;
end; $$;
create or replace function breeder_private.apply_cross_app_import(p_actor uuid,p_source text,p_profiles jsonb,p_animals jsonb default '[]',p_entries jsonb default '[]',p_ring uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_owner text; r jsonb; v_animal uuid; v_existing uuid[]; v_added int:=0; v_history int:=0; v_unmatched int:=0;
begin
 if auth.role() is distinct from 'service_role' or (auth.uid() is not null and auth.uid()<>p_actor) then raise exception 'Server import required'; end if;
 if p_source not in ('ringmaster_show','ringmaster_club') then raise exception 'Invalid source'; end if;
 select u.id into v_owner from public.users u join auth.users a on a.id=u.auth_user_id
 where u.auth_user_id=p_actor and u.is_active and a.email_confirmed_at is not null for update of u;
 if v_owner is null then raise exception 'Verified Breeder identity required'; end if;
 if jsonb_array_length(p_profiles)=0 then raise exception 'Select a profile'; end if;
 if jsonb_array_length(p_animals)>0 and not exists(select 1 from public.farms where id=p_ring and owner_id=v_owner) then raise exception 'Select your own Ring'; end if;
 for r in select value from jsonb_array_elements(p_profiles) loop
  insert into public.breeder_exhibitor_profiles(owner_id,source_app,source_id,profile)
  values(v_owner,
   case when r->>'imported_from' in ('ringmaster_show','ringmaster_club') and nullif(r->>'imported_source_id','') is not null then r->>'imported_from' else p_source end,
   case when r->>'imported_from' in ('ringmaster_show','ringmaster_club') and nullif(r->>'imported_source_id','') is not null then (r->>'imported_source_id')::uuid else (r->>'id')::uuid end,r) on conflict do nothing;
 end loop;
 for r in select value from jsonb_array_elements(p_animals) loop
  -- Store species-specific sex names; accept legacy import codes. Normalize before matching or inserting.
  r:=jsonb_set(r,'{sex}',to_jsonb(case when lower(btrim(coalesce(r->>'sex',''))) in ('m','male','buck','boar') then case lower(r->>'species') when 'cavy' then 'Boar' else 'Buck' end when lower(btrim(coalesce(r->>'sex',''))) in ('f','female','doe','sow') then case lower(r->>'species') when 'cavy' then 'Sow' else 'Doe' end else r->>'sex' end));
  v_animal:=null;
  select animal_id into v_animal from public.breeder_imported_animals where owner_id=v_owner and source_app=p_source and source_id=(r->>'id')::uuid;
  if v_animal is null then
   select array_agg(a.id) into v_existing from public.animals a join public.farms f on f.id=a.ring_id
   where f.owner_id=v_owner and nullif(btrim(r->>'tattoo'),'') is not null
    and lower(btrim(a.tattoo))=lower(btrim(r->>'tattoo')) and lower(a.species)=lower(r->>'species')
    and lower(coalesce(a.breed,''))=lower(coalesce(r->>'breed','')) and upper(coalesce(a.sex,''))=upper(coalesce(r->>'sex',''));
   if cardinality(v_existing)>1 then raise exception 'Multiple matching animals; resolve duplicates before import'; end if;
   v_animal:=v_existing[1];
   if v_animal is not null and exists(select 1 from public.animals a where a.id=v_animal and
    ((nullif(r->>'birth_date','') is not null and a.dob is not null and a.dob<>(r->>'birth_date')::date)
     or (nullif(r->>'variety','') is not null and nullif(a.variety,'') is not null and lower(a.variety)<>lower(r->>'variety')))) then
    raise exception 'Animal identifier conflict; review existing animal before import';
   end if;
   if v_animal is null then
    insert into public.animals(ring_id,name,tattoo,species,breed,variety,sex,dob,status)
    values(p_ring,r->>'name',r->>'tattoo',lower(r->>'species'),r->>'breed',r->>'variety',upper(r->>'sex'),nullif(r->>'birth_date','')::date,'active') returning id into v_animal;
    v_added:=v_added+1;
   end if;
   insert into public.breeder_imported_animals values(v_owner,p_source,(r->>'id')::uuid,v_animal);
  end if;
 end loop;
 for r in select value from jsonb_array_elements(p_entries) loop
  -- Store species-specific sex names; accept legacy import codes. Normalize before matching or inserting.
  r:=jsonb_set(r,'{sex}',to_jsonb(case when lower(btrim(coalesce(r->>'sex',''))) in ('m','male','buck','boar') then case lower(r->>'species') when 'cavy' then 'Boar' else 'Buck' end when lower(btrim(coalesce(r->>'sex',''))) in ('f','female','doe','sow') then case lower(r->>'species') when 'cavy' then 'Sow' else 'Doe' end else r->>'sex' end));
  v_animal:=null;
  select animal_id into v_animal from public.breeder_imported_animals where owner_id=v_owner and source_app=p_source and source_id=nullif(r->>'animal_id','')::uuid;
  -- Results-only imports can link an existing animal, but never insert/update it.
  -- Ambiguous matches remain unlinked for later review instead of guessing.
  if v_animal is null and nullif(btrim(r->>'tattoo'),'') is not null then
   select array_agg(a.id) into v_existing from public.animals a join public.farms f on f.id=a.ring_id
   where f.owner_id=v_owner and lower(btrim(a.tattoo))=lower(btrim(r->>'tattoo'))
    and lower(a.species)=lower(r->>'species')
    and lower(coalesce(a.breed,''))=lower(coalesce(r->>'breed',''))
    and upper(coalesce(a.sex,''))=upper(coalesce(r->>'sex',''))
    and lower(coalesce(a.variety,''))=lower(coalesce(r->>'variety',''));
   if cardinality(v_existing)=1 then v_animal:=v_existing[1]; end if;
  end if;
  if v_animal is null then v_unmatched:=v_unmatched+1; end if;
  insert into public.breeder_show_history(owner_id,source_app,source_entry_id,animal_id,exhibitor_source_id,record)
  values(v_owner,p_source,(r->>'id')::uuid,v_animal,(r->>'exhibitor_id')::uuid,r) on conflict(owner_id,source_app,source_entry_id) do update
   set animal_id=coalesce(public.breeder_show_history.animal_id,excluded.animal_id)
   where public.breeder_show_history.animal_id is null and excluded.animal_id is not null;
  if found then v_history:=v_history+1; end if;
 end loop;
 update public.users set display_name=coalesce(nullif(display_name,''),p_profiles->0->>'display_name'),
 phone=coalesce(nullif(phone,''),p_profiles->0->>'phone'),address=coalesce(nullif(address,''),p_profiles->0->>'address_line1'),
 city=coalesce(nullif(city,''),p_profiles->0->>'city'),state=coalesce(nullif(state,''),p_profiles->0->>'state'),
 zip=coalesce(nullif(zip,''),p_profiles->0->>'zip'),arba_number=coalesce(nullif(arba_number,''),p_profiles->0->>'arba_number') where id=v_owner;
 return jsonb_build_object('status','imported','animals_added',v_added,'entries_added',v_history,'profiles_selected',jsonb_array_length(p_profiles),'results_unmatched',v_unmatched);
end;
$$;

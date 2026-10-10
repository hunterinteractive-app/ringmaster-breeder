alter policy family_breeding_insert on public.breeding_records to authenticated
with check (status='active' and breeder_private.animal_access(sire_id) and breeder_private.animal_access(dam_id)
 and exists(select 1 from public.animals s join public.animals d on d.id=breeding_records.dam_id
 where s.id=breeding_records.sire_id and s.ring_id=d.ring_id and s.species=d.species
 and lower(s.sex) in ('m','male','buck','boar') and lower(d.sex) in ('f','female','doe','sow')));
create function public.record_breeding_with_parents(p_ring uuid,p_parents jsonb,p_records jsonb)
returns integer language plpgsql security invoker set search_path='' as $$
declare p jsonb; r jsonb; ids jsonb='{}'; aid uuid; n integer=0;
begin
 if auth.uid() is null or not exists(select 1 from public.farms f where f.id=p_ring
  and breeder_private.has_access(f.owner_id) and not coalesce(f.is_demo,false))
 then raise exception 'Ring access denied'; end if;
 if jsonb_typeof(p_parents)<>'array' or jsonb_typeof(p_records)<>'array'
  or jsonb_array_length(p_records) not between 1 and 100 or jsonb_array_length(p_parents)>101
 then raise exception 'Invalid breeding request'; end if;
 for p in select value from jsonb_array_elements(p_parents) loop
  if nullif(trim(p->>'name'),'') is null and nullif(trim(p->>'tattoo'),'') is null then
   raise exception 'Enter a name or ear number'; end if;
  if exists(select 1 from public.animals a where a.ring_id=p_ring and a.species=p->>'species'
    and lower(trim(a.tattoo))=lower(trim(p->>'tattoo')) and nullif(trim(p->>'tattoo'),'') is not null
    and a.sex=p->>'sex') then raise exception 'This parent already exists. Select the existing record.'; end if;
  insert into public.animals(ring_id,name,tattoo,species,breed,variety,sex,dob,status,pedigree_only,
    registration_number,grand_champion_number,color_details)
  values(p_ring,p->>'name',p->>'tattoo',p->>'species',p->>'breed',p->>'variety',p->>'sex',
    nullif(p->>'dob','')::date,'active',true,p->>'registration_number',p->>'grand_champion_number',
    coalesce(p->'color_details','{}')) returning id into aid;
  if nullif(p->>'weight','') is not null then
   insert into public.animal_weights(animal_id,weight) values(aid,(p->>'weight')::numeric);
  end if;
  ids=ids || jsonb_build_object(p->>'id',aid);
 end loop;
 for r in select value from jsonb_array_elements(p_records) loop
  if not exists(select 1 from public.animals a where a.id=coalesce(ids->>(r->>'sire_id'),r->>'sire_id')::uuid and a.ring_id=p_ring)
   or not exists(select 1 from public.animals a where a.id=coalesce(ids->>(r->>'dam_id'),r->>'dam_id')::uuid and a.ring_id=p_ring)
  then raise exception 'Parents must belong to this Ring'; end if;
  insert into public.breeding_records(sire_id,dam_id,breeding_date,notes)
  values(coalesce(ids->>(r->>'sire_id'),r->>'sire_id')::uuid,
   coalesce(ids->>(r->>'dam_id'),r->>'dam_id')::uuid,(r->>'breeding_date')::date,coalesce(r->>'notes',''));
  n=n+1;
 end loop;
 return n;
end $$;
revoke all on function public.record_breeding_with_parents(uuid,jsonb,jsonb) from public;
grant execute on function public.record_breeding_with_parents(uuid,jsonb,jsonb) to authenticated;

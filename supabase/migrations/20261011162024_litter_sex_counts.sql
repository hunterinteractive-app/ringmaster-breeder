alter table public.breeding_tracking add column weaned_males integer, add column weaned_females integer;
alter table public.breeding_tracking add constraint litter_sex_counts check(
 (weaned_males is null and weaned_females is null) or
 (weaned_males is not null and weaned_females is not null and weaned_males between 0 and 100 and weaned_females between 0 and 100 and weaned is not null and weaned=weaned_males+weaned_females));
create or replace function public.save_breeding_tracking(p_id uuid,p_data jsonb,p_revision integer)
returns void language plpgsql security invoker set search_path='' as $$
declare b public.breeding_records; old public.breeding_tracking; t public.breeding_tracking;
begin
 select * into b from public.breeding_records where id=p_id for update;
 if b.id is null then raise exception 'Breeding access denied'; end if;
 select * into old from public.breeding_tracking where breeding_id=p_id;
 if coalesce(old.revision,0)<>p_revision then raise exception 'This litter changed. Refresh and try again.'; end if;
 t=jsonb_populate_record(null::public.breeding_tracking,p_data);
 if p_data ? 'weaned_males' or p_data ? 'weaned_females' then
  if t.wean_date is not null and (t.weaned_males is null or t.weaned_females is null) then raise exception 'Enter both sex counts (use 0 when none)'; end if;
  t.weaned=t.weaned_males+t.weaned_females;
 end if;
 if t.due_date<b.breeding_date or t.check_date<b.breeding_date or t.birth_date<b.breeding_date
 or t.birth_date>current_date or t.check_date>current_date or t.wean_date>current_date then raise exception 'Check the event dates'; end if;
 if exists(select 1 from public.breeding_offspring where breeding_id=p_id) and
 (t.birth_date is distinct from old.birth_date or t.weaned is distinct from old.weaned or t.wean_date is distinct from old.wean_date)
 then raise exception 'Offspring already created. Birth and weaning totals are locked.'; end if;
 insert into public.breeding_tracking(breeding_id,due_date,check_date,check_result,birth_date,born_alive,born_dead,wean_date,weaned,weaned_males,weaned_females,status,notes,revision)
 values(p_id,t.due_date,t.check_date,t.check_result,t.birth_date,t.born_alive,t.born_dead,t.wean_date,t.weaned,t.weaned_males,t.weaned_females,t.status,coalesce(t.notes,''),p_revision+1)
 on conflict(breeding_id) do update set due_date=excluded.due_date,check_date=excluded.check_date,check_result=excluded.check_result,
 birth_date=excluded.birth_date,born_alive=excluded.born_alive,born_dead=excluded.born_dead,wean_date=excluded.wean_date,weaned=excluded.weaned,
 weaned_males=excluded.weaned_males,weaned_females=excluded.weaned_females,
 status=excluded.status,notes=excluded.notes,revision=excluded.revision;
 update public.breeding_records set status=t.status where id=p_id;
end $$;
create or replace function public.create_litter_animals(p_id uuid,p_young jsonb)
returns integer language plpgsql security invoker set search_path='' as $$
declare b public.breeding_records; t public.breeding_tracking; dam public.animals; y jsonb; aid uuid; n integer=0;
begin
 select * into b from public.breeding_records where id=p_id for update;
 if b.id is null then raise exception 'Breeding access denied'; end if;
 select * into t from public.breeding_tracking where breeding_id=p_id;
 if t.weaned is null or t.weaned=0 or t.status='cancelled' then raise exception 'Record weaning first'; end if;
 if exists(select 1 from public.breeding_offspring where breeding_id=p_id) then raise exception 'Offspring records already created'; end if;
 if jsonb_typeof(p_young) is distinct from 'array' or jsonb_array_length(p_young)<>t.weaned then raise exception 'Enter one row for each weaned animal'; end if;
 if t.weaned_males is not null and ((select count(*) from jsonb_array_elements(p_young) y where y->>'sex'='M')<>t.weaned_males or (select count(*) from jsonb_array_elements(p_young) y where y->>'sex'='F')<>t.weaned_females) then raise exception 'Offspring sexes must match the recorded weaning counts'; end if;
 select * into dam from public.animals where id=b.dam_id;
 for y in select value from jsonb_array_elements(p_young) loop
  if nullif(trim(y->>'tattoo'),'') is null or coalesce(y->>'sex','') not in ('M','F') then raise exception 'Enter an ear number and sex for each animal'; end if;
  if exists(select 1 from public.animals a where a.ring_id=dam.ring_id and a.species=dam.species and lower(trim(a.tattoo))=lower(trim(y->>'tattoo'))) then raise exception 'An ear number already exists in this Ring'; end if;
  insert into public.animals(ring_id,name,tattoo,species,breed,variety,sex,dob,sire_id,dam_id,status,pedigree_only)
  values(dam.ring_id,nullif(trim(y->>'name'),''),trim(y->>'tattoo'),dam.species,nullif(trim(y->>'breed'),''),nullif(trim(y->>'variety'),''),case when dam.species='cavy' then case when y->>'sex'='M' then 'Boar' else 'Sow' end else case when y->>'sex'='M' then 'Buck' else 'Doe' end end,t.birth_date,b.sire_id,b.dam_id,'active',false) returning id into aid;
  insert into public.breeding_offspring(animal_id,breeding_id) values(aid,p_id);
  n=n+1;
 end loop;
 return n;
end $$;

-- Database enforcement also protects simultaneous saves and manual edits.
create unique index animals_herd_tattoo_unique on public.animals(ring_id,lower(btrim(tattoo))) where nullif(btrim(tattoo),'') is not null;
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
 if t.weaned_males is not null and ((select count(*) from jsonb_array_elements(p_young) as item(value) where item.value->>'sex'='M')<>t.weaned_males or (select count(*) from jsonb_array_elements(p_young) as item(value) where item.value->>'sex'='F')<>t.weaned_females) then raise exception 'Offspring sexes must match the recorded weaning counts'; end if;
 select * into dam from public.animals where id=b.dam_id;
 for y in select value from jsonb_array_elements(p_young) loop
  if nullif(trim(y->>'tattoo'),'') is null or coalesce(y->>'sex','') not in ('M','F') then raise exception 'Enter an ear number and sex for each animal'; end if;
  if exists(select 1 from public.animals a where a.ring_id=dam.ring_id and lower(trim(a.tattoo))=lower(trim(y->>'tattoo'))) then raise exception 'An ear number already exists in this herd'; end if;
  insert into public.animals(ring_id,name,tattoo,species,breed,variety,sex,dob,sire_id,dam_id,status,pedigree_only)
  values(dam.ring_id,nullif(trim(y->>'name'),''),trim(y->>'tattoo'),dam.species,nullif(trim(y->>'breed'),''),nullif(trim(y->>'variety'),''),case when dam.species='cavy' then case when y->>'sex'='M' then 'Boar' else 'Sow' end else case when y->>'sex'='M' then 'Buck' else 'Doe' end end,t.birth_date,b.sire_id,b.dam_id,'active',false) returning id into aid;
  insert into public.breeding_offspring(animal_id,breeding_id) values(aid,p_id);
  n=n+1;
 end loop;
 update public.breeding_tracking set status='completed',revision=revision+1 where breeding_id=p_id;
 update public.breeding_records set status='completed' where id=p_id;
 return n;
end $$;

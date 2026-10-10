create table public.breeding_tracking (
 breeding_id uuid primary key references public.breeding_records(id) on delete restrict,
 due_date date,
 check_date date,
 check_result text not null default 'Not checked' check(check_result in ('Not checked','Positive','Negative','Uncertain')),
 birth_date date,
 born_alive integer check(born_alive between 0 and 100),
 born_dead integer check(born_dead between 0 and 100),
 wean_date date,
 weaned integer check(weaned between 0 and 100),
 status text not null default 'active' check(status in ('active','completed','cancelled')),
 notes text not null default '' check(length(notes)<=4000),
 revision integer not null default 1,
 check ((birth_date is null and born_alive is null and born_dead is null) or (birth_date is not null and born_alive is not null and born_dead is not null)),
 check ((wean_date is null and weaned is null) or (wean_date is not null and weaned is not null and birth_date is not null and wean_date>=birth_date and weaned<=born_alive)),
 check(check_result='Not checked' or check_date is not null)
);
create table public.breeding_offspring (
 animal_id uuid primary key references public.animals(id) on delete restrict,
 breeding_id uuid not null references public.breeding_records(id) on delete restrict
);
create index breeding_offspring_breeding on public.breeding_offspring(breeding_id);
alter table public.breeding_tracking enable row level security;
alter table public.breeding_offspring enable row level security;
revoke all on public.breeding_tracking,public.breeding_offspring from anon,authenticated;
grant select,insert,update on public.breeding_tracking to authenticated;
grant select,insert on public.breeding_offspring to authenticated;
create policy tracking_access on public.breeding_tracking for all to authenticated
 using(exists(select 1 from public.breeding_records b where b.id=breeding_id))
 with check(exists(select 1 from public.breeding_records b where b.id=breeding_id));
create policy offspring_read on public.breeding_offspring for select to authenticated
 using(exists(select 1 from public.breeding_records b where b.id=breeding_id) and breeder_private.animal_access(animal_id));
create policy offspring_insert on public.breeding_offspring for insert to authenticated
 with check(exists(select 1 from public.breeding_records b join public.animals a on a.id=animal_id where b.id=breeding_id and a.sire_id=b.sire_id and a.dam_id=b.dam_id) and breeder_private.animal_access(animal_id));
grant update(status) on public.breeding_records to authenticated;
create policy family_breeding_update on public.breeding_records for update to authenticated
 using(breeder_private.animal_access(sire_id) and breeder_private.animal_access(dam_id))
 with check(breeder_private.animal_access(sire_id) and breeder_private.animal_access(dam_id));
create function public.save_breeding_tracking(p_id uuid,p_data jsonb,p_revision integer)
returns void language plpgsql security invoker set search_path='' as $$
declare b public.breeding_records; old public.breeding_tracking; t public.breeding_tracking;
begin
 select * into b from public.breeding_records where id=p_id for update;
 if b.id is null then raise exception 'Breeding access denied'; end if;
 select * into old from public.breeding_tracking where breeding_id=p_id;
 if coalesce(old.revision,0)<>p_revision then raise exception 'This litter changed. Refresh and try again.'; end if;
 t=jsonb_populate_record(null::public.breeding_tracking,p_data);
 if t.due_date<b.breeding_date or t.check_date<b.breeding_date or t.birth_date<b.breeding_date
 or t.birth_date>current_date or t.check_date>current_date or t.wean_date>current_date then raise exception 'Check the event dates'; end if;
 if exists(select 1 from public.breeding_offspring where breeding_id=p_id) and
 (t.birth_date is distinct from old.birth_date or t.weaned is distinct from old.weaned or t.wean_date is distinct from old.wean_date)
 then raise exception 'Offspring already created. Birth and weaning totals are locked.'; end if;
 insert into public.breeding_tracking(breeding_id,due_date,check_date,check_result,birth_date,born_alive,born_dead,wean_date,weaned,status,notes,revision)
 values(p_id,t.due_date,t.check_date,t.check_result,t.birth_date,t.born_alive,t.born_dead,t.wean_date,t.weaned,t.status,coalesce(t.notes,''),p_revision+1)
 on conflict(breeding_id) do update set due_date=excluded.due_date,check_date=excluded.check_date,check_result=excluded.check_result,
 birth_date=excluded.birth_date,born_alive=excluded.born_alive,born_dead=excluded.born_dead,wean_date=excluded.wean_date,weaned=excluded.weaned,
 status=excluded.status,notes=excluded.notes,revision=excluded.revision;
 update public.breeding_records set status=t.status where id=p_id;
end $$;
create function public.create_litter_animals(p_id uuid,p_young jsonb)
returns integer language plpgsql security invoker set search_path='' as $$
declare b public.breeding_records; t public.breeding_tracking; dam public.animals; y jsonb; aid uuid; n integer=0;
begin
 select * into b from public.breeding_records where id=p_id for update;
 if b.id is null then raise exception 'Breeding access denied'; end if;
 select * into t from public.breeding_tracking where breeding_id=p_id;
 if t.weaned is null or t.weaned=0 or t.status='cancelled' then raise exception 'Record weaning first'; end if;
 if exists(select 1 from public.breeding_offspring where breeding_id=p_id) then raise exception 'Offspring records already created'; end if;
 if jsonb_typeof(p_young) is distinct from 'array' or jsonb_array_length(p_young)<>t.weaned then raise exception 'Enter one row for each weaned animal'; end if;
 select * into dam from public.animals where id=b.dam_id;
 for y in select value from jsonb_array_elements(p_young) loop
  if nullif(trim(y->>'tattoo'),'') is null or coalesce(y->>'sex','') not in ('M','F','Unknown') then raise exception 'Enter an ear number and sex for each animal'; end if;
  if exists(select 1 from public.animals a where a.ring_id=dam.ring_id and a.species=dam.species and lower(trim(a.tattoo))=lower(trim(y->>'tattoo'))) then raise exception 'An ear number already exists in this Ring'; end if;
  insert into public.animals(ring_id,name,tattoo,species,breed,variety,sex,dob,sire_id,dam_id,status,pedigree_only)
  values(dam.ring_id,nullif(trim(y->>'name'),''),trim(y->>'tattoo'),dam.species,nullif(trim(y->>'breed'),''),nullif(trim(y->>'variety'),''),y->>'sex',t.birth_date,b.sire_id,b.dam_id,'active',false) returning id into aid;
  insert into public.breeding_offspring(animal_id,breeding_id) values(aid,p_id);
  n=n+1;
 end loop;
 return n;
end $$;
revoke all on function public.save_breeding_tracking(uuid,jsonb,integer),public.create_litter_animals(uuid,jsonb) from public;
grant execute on function public.save_breeding_tracking(uuid,jsonb,integer),public.create_litter_animals(uuid,jsonb) to authenticated;

-- Weaned youngsters can stay grouped until selected for individual herd records.
-- Existing litters retain the individual-record workflow.
alter table public.breeding_tracking
 add column weaning_destination text not null default 'individual'
 check(weaning_destination in ('individual','grow_out'));
alter table public.breeding_tracking add constraint grow_out_requires_weaning check(
 weaning_destination<>'grow_out' or (birth_date is not null and wean_date is not null and weaned is not null and weaned>0));

create or replace function public.save_breeding_tracking(p_id uuid,p_data jsonb,p_revision integer)
returns void language plpgsql security invoker set search_path='' as $$
declare b public.breeding_records; old public.breeding_tracking; t public.breeding_tracking;
begin
 select * into b from public.breeding_records where id=p_id for update;
 if b.id is null then raise exception 'Breeding access denied'; end if;
 select * into old from public.breeding_tracking where breeding_id=p_id;
 if coalesce(old.revision,0)<>p_revision then raise exception 'This litter changed. Refresh and try again.'; end if;
 if p_data ? 'actual_breeding_date' then
  b.breeding_date:=nullif(p_data->>'actual_breeding_date','')::date;
  if b.breeding_date<date '1800-01-01' then raise exception 'Invalid breeding date';end if;
 end if;
 t=jsonb_populate_record(null::public.breeding_tracking,coalesce(to_jsonb(old),'{}')||p_data);
 t.weaning_destination=coalesce(t.weaning_destination,'individual');
 if (p_data ? 'weaned_males' or p_data ? 'weaned_females') and not (old.import_record is not null and t.weaned_males is null and t.weaned_females is null) then
  if t.wean_date is not null and (t.weaned_males is null or t.weaned_females is null) then raise exception 'Enter both sex counts (use 0 when none)'; end if;
  t.weaned=t.weaned_males+t.weaned_females;
 end if;
 if (b.breeding_date>current_date and t.breeding_occurred is distinct from false) then raise exception 'Actual breeding date cannot be in the future';end if;
 if t.due_date<b.breeding_date or t.check_date<b.breeding_date or t.birth_date<b.breeding_date
 or t.birth_date>current_date or t.check_date>current_date or t.wean_date>current_date then raise exception 'Check the event dates'; end if;
 if exists(select 1 from public.breeding_offspring where breeding_id=p_id) and
 ((old.birth_date is not null and t.birth_date is distinct from old.birth_date) or
 (old.weaned is not null and t.weaned is distinct from old.weaned) or
 (old.wean_date is not null and t.wean_date is distinct from old.wean_date) or
 (old.import_record is null and (t.birth_date is distinct from old.birth_date or t.weaned is distinct from old.weaned or t.wean_date is distinct from old.wean_date)))
 then raise exception 'Offspring already created. Birth and weaning totals are locked.'; end if;
 if exists(select 1 from public.breeding_offspring o join public.animals a on a.id=o.animal_id where o.breeding_id=p_id and t.birth_date is not null and a.dob is not null and a.dob<>t.birth_date)
 or t.weaned<(select count(*) from public.breeding_offspring where breeding_id=p_id) then raise exception 'Tracking conflicts with linked offspring';end if;
 if t.split_date<t.paired_date or t.paired_date>current_date or t.split_date>current_date then raise exception 'Check pairing and separation dates';end if;
 if (t.weaned is not null and coalesce(t.born_alive,t.born_total) is not null and t.weaned>coalesce(t.born_alive,t.born_total)+coalesce(t.added,0)) then raise exception 'Weaned total exceeds born plus added';end if;
 if t.weaning_destination='grow_out' and (t.birth_date is null or t.wean_date is null or coalesce(t.weaned,0)<=0) then
  raise exception 'Record birth, weaning date and a positive count for grow out';
 end if;
 if t.weaned_males is not null and (
  t.weaned_males<(select count(*) from public.breeding_offspring o join public.animals a on a.id=o.animal_id where o.breeding_id=p_id and a.sex in ('Buck','Boar')) or
  t.weaned_females<(select count(*) from public.breeding_offspring o join public.animals a on a.id=o.animal_id where o.breeding_id=p_id and a.sex in ('Doe','Sow'))
 ) then raise exception 'Weaning sex counts conflict with linked offspring';end if;
 insert into public.breeding_tracking(breeding_id,weaning_destination,due_date,check_date,check_result,birth_date,born_alive,born_dead,wean_date,weaned,weaned_males,weaned_females,status,notes,born_total,recorded_deaths,paired_date,split_date,scheduled_breeding_date,breeding_occurred,nest_installed,nest_removed,rebreeding_enabled,rebreeding_overridden,cage,breed_label,palpation_source,added,raised,bucks,does,kept,sold,show_quality,custom_fields,revision,import_record)
 values(p_id,t.weaning_destination,t.due_date,t.check_date,coalesce(t.check_result,'Not checked'),t.birth_date,t.born_alive,t.born_dead,t.wean_date,t.weaned,t.weaned_males,t.weaned_females,t.status,coalesce(t.notes,''),t.born_total,t.recorded_deaths,t.paired_date,t.split_date,t.scheduled_breeding_date,t.breeding_occurred,t.nest_installed,t.nest_removed,t.rebreeding_enabled,t.rebreeding_overridden,coalesce(t.cage,''),coalesce(t.breed_label,''),t.palpation_source,t.added,t.raised,t.bucks,t.does,t.kept,t.sold,t.show_quality,coalesce(t.custom_fields,'{}'),p_revision+1,old.import_record)
 on conflict(breeding_id) do update set weaning_destination=excluded.weaning_destination,due_date=excluded.due_date,check_date=excluded.check_date,check_result=excluded.check_result,birth_date=excluded.birth_date,born_alive=excluded.born_alive,born_dead=excluded.born_dead,wean_date=excluded.wean_date,weaned=excluded.weaned,weaned_males=excluded.weaned_males,weaned_females=excluded.weaned_females,status=excluded.status,notes=excluded.notes,born_total=excluded.born_total,recorded_deaths=excluded.recorded_deaths,paired_date=excluded.paired_date,split_date=excluded.split_date,scheduled_breeding_date=excluded.scheduled_breeding_date,breeding_occurred=excluded.breeding_occurred,nest_installed=excluded.nest_installed,nest_removed=excluded.nest_removed,rebreeding_enabled=excluded.rebreeding_enabled,rebreeding_overridden=excluded.rebreeding_overridden,cage=excluded.cage,breed_label=excluded.breed_label,palpation_source=excluded.palpation_source,added=excluded.added,raised=excluded.raised,bucks=excluded.bucks,does=excluded.does,kept=excluded.kept,sold=excluded.sold,show_quality=excluded.show_quality,custom_fields=excluded.custom_fields,revision=excluded.revision;
 update public.breeding_records set status=t.status,breeding_date=b.breeding_date where id=p_id;
end $$;

create or replace function public.create_litter_animals(p_id uuid,p_young jsonb)
returns integer language plpgsql security invoker set search_path='' as $$
declare b public.breeding_records; t public.breeding_tracking; dam public.animals; y jsonb; aid uuid; n integer=0; linked integer; linked_males integer; linked_females integer; requested integer; requested_males integer; requested_females integer; next_status text;
begin
 select * into b from public.breeding_records where id=p_id for update;
 if b.id is null then raise exception 'Breeding access denied'; end if;
 select * into t from public.breeding_tracking where breeding_id=p_id;
 if t.weaned is null or t.weaned=0 or t.status='cancelled' then raise exception 'Record weaning first'; end if;
 if t.birth_date is null or t.wean_date is null or b.sire_id is null then raise exception 'Record the sire, birth date and weaning date before creating new offspring';end if;
 select count(*),count(*) filter(where a.sex in ('Buck','Boar')),count(*) filter(where a.sex in ('Doe','Sow')) into linked,linked_males,linked_females
 from public.breeding_offspring o join public.animals a on a.id=o.animal_id where o.breeding_id=p_id;
 if linked>=t.weaned then raise exception 'Offspring records already created';end if;
 if jsonb_typeof(p_young) is distinct from 'array' then raise exception 'Enter offspring records';end if;
 requested=jsonb_array_length(p_young);
 if requested=0 or requested>t.weaned-linked or (t.weaning_destination<>'grow_out' and requested<>t.weaned-linked)
 then raise exception 'Choose offspring within the remaining weaning count';end if;
 select count(*) filter(where value->>'sex'='M'),count(*) filter(where value->>'sex'='F')
 into requested_males,requested_females from jsonb_array_elements(p_young);
 if t.weaned_males is not null and (
  requested_males>t.weaned_males-linked_males or requested_females>t.weaned_females-linked_females or
  (t.weaning_destination<>'grow_out' and (requested_males<>t.weaned_males-linked_males or requested_females<>t.weaned_females-linked_females))
 ) then raise exception 'Offspring sexes must match the remaining weaning counts';end if;
 select * into dam from public.animals where id=b.dam_id;
 for y in select value from jsonb_array_elements(p_young) loop
  if nullif(trim(y->>'tattoo'),'') is null or coalesce(y->>'sex','') not in ('M','F') then raise exception 'Enter an ear number and sex for each animal'; end if;
  if exists(select 1 from public.animals a where a.ring_id=dam.ring_id and a.species=dam.species and lower(trim(a.tattoo))=lower(trim(y->>'tattoo'))) then raise exception 'An ear number already exists in this Ring'; end if;
  insert into public.animals(ring_id,name,tattoo,species,breed,variety,sex,dob,sire_id,dam_id,status,pedigree_only)
  values(dam.ring_id,nullif(trim(y->>'name'),''),trim(y->>'tattoo'),dam.species,nullif(trim(y->>'breed'),''),nullif(trim(y->>'variety'),''),case when dam.species='cavy' then case when y->>'sex'='M' then 'Boar' else 'Sow' end else case when y->>'sex'='M' then 'Buck' else 'Doe' end end,t.birth_date,b.sire_id,b.dam_id,'active',false) returning id into aid;
  insert into public.breeding_offspring(animal_id,breeding_id) values(aid,p_id);
  n=n+1;
 end loop;
 next_status=case when linked+n=t.weaned then 'completed' else t.status end;
 update public.breeding_tracking set status=next_status,
  weaning_destination=case when linked+n=t.weaned then 'individual' else weaning_destination end,
  revision=revision+1 where breeding_id=p_id;
 update public.breeding_records set status=next_status where id=p_id;
 return n;
end $$;

-- Run only against a disposable local database with an authenticated herd fixture.
begin;
select set_config('test.grow_out_ring',f.id::text,true),
 set_config('request.jwt.claim.sub',u.auth_user_id::text,true)
from public.farms f join public.users u on u.id=f.owner_id
where u.auth_user_id is not null order by f.id limit 1;
set local role authenticated;
do $$
declare
 ring uuid=current_setting('test.grow_out_ring')::uuid;
 sid uuid; did uuid; bid uuid; indiv uuid; measurement uuid; n integer; test_species text; prefix text;
begin
 if has_function_privilege('anon','public.save_breeding_tracking(uuid,jsonb,integer)','execute')
  or has_function_privilege('anon','public.create_litter_animals(uuid,jsonb)','execute')
 then raise exception 'Anonymous litter RPC access';end if;
 foreach test_species in array array['rabbit','cavy'] loop
  prefix='GROW-'||substr(gen_random_uuid()::text,1,8);
  insert into public.animals(ring_id,name,species,sex,pedigree_only)
  values(ring,'Grow-out test sire',test_species,case when test_species='cavy' then 'Boar' else 'Buck' end,true) returning id into sid;
  insert into public.animals(ring_id,name,species,sex,pedigree_only)
  values(ring,'Grow-out test dam',test_species,case when test_species='cavy' then 'Sow' else 'Doe' end,true) returning id into did;
  insert into public.breeding_records(sire_id,dam_id,breeding_date) values(sid,did,'2026-07-01') returning id into bid;
  begin
   perform public.save_breeding_tracking(bid,'{"status":"active","weaning_destination":"grow_out"}',0);
   raise exception 'Invalid grow out accepted';
  exception when raise_exception then
   if sqlerrm<>'Record birth, weaning date and a positive count for grow out' then raise;end if;
  end;
  perform public.save_breeding_tracking(bid,'{"birth_date":"2026-08-01","born_alive":3,"born_dead":0,"wean_date":"2026-09-15","weaned":3,"weaned_males":2,"weaned_females":1,"status":"active","weaning_destination":"grow_out"}',0);
  if exists(select 1 from public.breeding_offspring where breeding_id=bid) then raise exception 'Grow out created individual animals';end if;
  -- Old clients that omit the new field must preserve the chosen destination.
  perform public.save_breeding_tracking(bid,'{"notes":"Group notes"}',1);
  if (select weaning_destination from public.breeding_tracking where breeding_id=bid)<>'grow_out' then raise exception 'Destination lost on partial save';end if;
  measurement=gen_random_uuid();
  perform public.save_production_measurement('litter',measurement,bid,'{"recorded_date":"2026-10-01","weight":12,"feed_weight":30}',0);
  perform public.save_production_measurement('litter',measurement,bid,'{"recorded_date":"2026-10-01","weight":13,"feed_weight":35}',1);
  -- Retrying the same save confirms the existing reading instead of adding feed twice.
  perform public.save_production_measurement('litter',measurement,bid,'{"recorded_date":"2026-10-01","weight":13,"feed_weight":35}',1);
  if (select count(*) from public.litter_weights where breeding_id=bid)<>1 or not exists(
   select 1 from public.litter_weights where id=measurement and weight=13 and feed_weight=35 and voided=false
  ) then raise exception 'Grow-out measurement save or retry failed';end if;
  begin
   perform public.save_breeding_tracking(bid,'{"notes":"Stale"}',1);
   raise exception 'Stale save accepted';
  exception when raise_exception then
   if sqlerrm<>'This litter changed. Refresh and try again.' then raise;end if;
  end;
  begin
   perform public.create_litter_animals(bid,'[]');raise exception 'Empty selection accepted';
  exception when raise_exception then
   if sqlerrm<>'Choose offspring within the remaining weaning count' then raise;end if;
  end;
  begin
   perform public.create_litter_animals(bid,jsonb_build_array(jsonb_build_object('tattoo',prefix||'F1','sex','F'),jsonb_build_object('tattoo',prefix||'F2','sex','F')));
   raise exception 'Excess females accepted';
  exception when raise_exception then
   if sqlerrm<>'Offspring sexes must match the remaining weaning counts' then raise;end if;
  end;
  n=public.create_litter_animals(bid,jsonb_build_array(jsonb_build_object('tattoo',prefix||'F1','sex','F')));
  if n<>1 or (select count(*) from public.breeding_offspring where breeding_id=bid)<>1 then raise exception 'Partial conversion failed';end if;
  if not exists(select 1 from public.animals where sire_id=sid and dam_id=did and dob='2026-08-01' and ring_id=ring
   and sex=case when test_species='cavy' then 'Sow' else 'Doe' end and pedigree_only=false) then raise exception 'Parentage or sex lost';end if;
  if not exists(select 1 from public.breeding_tracking where breeding_id=bid and status='active' and weaning_destination='grow_out' and revision=3)
   or (select status from public.breeding_records where id=bid)<>'active' then raise exception 'Partial conversion closed grow out';end if;
  begin
   perform public.save_breeding_tracking(bid,'{"weaned_males":3,"weaned_females":0}',3);
   raise exception 'Conflicting sex totals accepted';
  exception when raise_exception then
   if sqlerrm<>'Weaning sex counts conflict with linked offspring' then raise;end if;
  end;
  begin
   perform public.create_litter_animals(bid,jsonb_build_array(jsonb_build_object('tattoo',prefix||'F2','sex','F')));
   raise exception 'Used female count accepted';
  exception when raise_exception then
   if sqlerrm<>'Offspring sexes must match the remaining weaning counts' then raise;end if;
  end;
  begin
   perform public.create_litter_animals(bid,jsonb_build_array(jsonb_build_object('tattoo',prefix||'DUP','sex','M'),jsonb_build_object('tattoo',prefix||'DUP','sex','M')));
   raise exception 'Duplicate tattoo accepted';
  exception when raise_exception then
   if sqlerrm<>'An ear number already exists in this Ring' then raise;end if;
  end;
  if (select count(*) from public.breeding_offspring where breeding_id=bid)<>1 then raise exception 'Failed save left partial offspring';end if;
  n=public.create_litter_animals(bid,jsonb_build_array(jsonb_build_object('tattoo',prefix||'M1','sex','M'),jsonb_build_object('tattoo',prefix||'M2','sex','M')));
  if n<>2 or not exists(select 1 from public.breeding_tracking where breeding_id=bid and status='completed' and weaning_destination='individual' and revision=4)
   or (select status from public.breeding_records where id=bid)<>'completed' then raise exception 'Final conversion did not complete litter';end if;
  insert into public.breeding_records(sire_id,dam_id,breeding_date) values(sid,did,'2026-07-02') returning id into indiv;
  perform public.save_breeding_tracking(indiv,'{"birth_date":"2026-08-01","born_alive":2,"born_dead":0,"wean_date":"2026-09-15","weaned":2,"weaned_males":1,"weaned_females":1,"status":"active"}',0);
  if (select weaning_destination from public.breeding_tracking where breeding_id=indiv)<>'individual' then raise exception 'Legacy default changed';end if;
  begin
   perform public.create_litter_animals(indiv,jsonb_build_array(jsonb_build_object('tattoo',prefix||'I1','sex','M')));
   raise exception 'Partial individual litter accepted';
  exception when raise_exception then
   if sqlerrm<>'Choose offspring within the remaining weaning count' then raise;end if;
  end;
  n=public.create_litter_animals(indiv,jsonb_build_array(jsonb_build_object('tattoo',prefix||'I1','sex','M'),jsonb_build_object('tattoo',prefix||'I2','sex','F')));
  if n<>2 or (select status from public.breeding_tracking where breeding_id=indiv)<>'completed'
   then raise exception 'Individual litter creation regressed';end if;
 end loop;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
 if exists(select 1 from public.breeding_tracking where breeding_id=bid) then raise exception 'Unauthorized read';end if;
 begin
  perform public.save_breeding_tracking(bid,'{}',4);raise exception 'Unauthorized save';
 exception when raise_exception then if sqlerrm<>'Breeding access denied' then raise;end if;end;
 begin
  perform public.create_litter_animals(bid,'[]');raise exception 'Unauthorized creation';
 exception when raise_exception then if sqlerrm<>'Breeding access denied' then raise;end if;end;
end $$;
rollback;

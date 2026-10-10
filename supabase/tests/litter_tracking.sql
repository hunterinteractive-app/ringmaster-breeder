begin;
select set_config('request.jwt.claim.sub',(select u.auth_user_id::text from public.users u join public.farms f on f.owner_id=u.id where f.id='a0f9e2f6-44aa-4319-a240-22649099f103'),true);
set local role authenticated;
do $$ declare sid uuid; did uuid; bid uuid; n integer; begin
 insert into public.animals(ring_id,name,species,sex,pedigree_only) values('a0f9e2f6-44aa-4319-a240-22649099f103','Litter test sire','rabbit','Buck',true) returning id into sid;
 insert into public.animals(ring_id,name,species,sex,pedigree_only) values('a0f9e2f6-44aa-4319-a240-22649099f103','Litter test dam','rabbit','Doe',true) returning id into did;
 insert into public.breeding_records(sire_id,dam_id,breeding_date) values(sid,did,'2026-07-01') returning id into bid;
 perform public.save_breeding_tracking(bid,'{"check_result":"Positive","check_date":"2026-07-15","birth_date":"2026-08-01","born_alive":2,"born_dead":0,"wean_date":"2026-09-15","weaned":2,"status":"completed"}',0);
 begin
  perform public.save_breeding_tracking(bid,'{"status":"active"}',0);
  raise exception 'Stale save guard failed';
 exception when raise_exception then if sqlerrm='Stale save guard failed' then raise; end if; end;
 begin
  perform public.create_litter_animals(bid,'[{"tattoo":"TEST-LITTER-A","sex":"M"},{"tattoo":"TEST-LITTER-A","sex":"F"}]');
  raise exception 'Duplicate ear guard failed';
 exception when raise_exception then if sqlerrm='Duplicate ear guard failed' then raise; end if; end;
 if exists(select 1 from public.animals where sire_id=sid) then raise exception 'Partial offspring save'; end if;
 n=public.create_litter_animals(bid,'[{"tattoo":"TEST-LITTER-A","sex":"M","breed":"Tan","variety":"Black"},{"tattoo":"TEST-LITTER-B","sex":"F","breed":"Tan","variety":"Chocolate"}]');
 if n<>2 or (select count(*) from public.animals where sire_id=sid and dam_id=did and dob='2026-08-01' and pedigree_only=false and sex in ('Buck','Doe'))<>2 then raise exception 'Offspring test failed'; end if;
 begin perform public.create_litter_animals(bid,'[]'); raise exception 'Duplicate guard failed'; exception when raise_exception then if sqlerrm='Duplicate guard failed' then raise; end if; end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
 if exists(select 1 from public.breeding_tracking where breeding_id=bid) then raise exception 'Unauthorized read'; end if;
 begin perform public.save_breeding_tracking(bid,'{}',1); raise exception 'Unauthorized save'; exception when raise_exception then if sqlerrm='Unauthorized save' then raise; end if; end;
end $$;
rollback;

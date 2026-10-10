-- Synthetic identities and records only; everything rolls back.
begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('11111111-1111-4111-8111-111111111111','owner@example.test',now()),
 ('22222222-2222-4222-8222-222222222222','member@example.test',now()),
 ('33333333-3333-4333-8333-333333333333','outsider@example.test',now());
insert into public.users(id,username,email) values('legacy-owner','fixture_owner','owner@example.test');
insert into public.license_tiers(code,name,max_rings) values('FIXTURE','Fixture',2);
insert into public.user_licenses(user_id,tier_code,status) values('legacy-owner','FIXTURE','active');
insert into public.farms(id,name,owner_id) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Original Ring','legacy-owner');
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select public.breeder_family_access();
do $$ begin
 if not exists(select 1 from public.farms where owner_id='legacy-owner') then raise exception 'Legacy owner lost access'; end if;
 if (select auth_user_id from public.users where id='legacy-owner')<>'11111111-1111-4111-8111-111111111111'::uuid then raise exception 'Verified email did not link legacy account'; end if;
end $$;

do $$ declare aid uuid; draft uuid; saved uuid; begin
 begin
  perform public.create_animal_with_color_details('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Color test','COL01','rabbit','Mini Rex','Tan','Buck','active',null,'','',null,null,null,'{}');
  raise exception 'Missing COD fields allowed';
 exception when raise_exception then
  if sqlerrm='Missing COD fields allowed' then raise; end if;
  if sqlerrm not like 'Enter both color%' then raise; end if;
 end;
 aid:=public.create_animal_with_color_details('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Color test','COL01','rabbit','Mini Rex','Tan (COD)','Buck','active',null,'','',null,null,4.5,'{"color":"Black","pattern":"Tan"}');
 if (select color_details->>'color' from public.animals where id=aid)<>'Black' then raise exception 'Details missing'; end if;
 if (select variety from public.animals where id=aid)<>'Tan (COD)' then raise exception 'Variety overwritten'; end if;
 if public.breeder_pedigree_snapshot(aid)->'animal'->'color_details'->>'pattern'<>'Tan' then raise exception 'Snapshot details missing'; end if;
 begin
  update public.animals set color_details='{}' where id=aid;
  raise exception 'Incomplete edit allowed';
 exception when raise_exception then
  if sqlerrm='Incomplete edit allowed' then raise; end if;
  if sqlerrm not like 'Enter both color%' then raise; end if;
 end;
 insert into public.pedigree_drafts(ring_id,data) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 '{"species":"rabbit","root":"a","nodes":{"a":{"name":"Pedigree color","tattoo":"COL02","breed":"Mini Rex","variety":"Tan (COD)","sex":"Doe","color_details":{"color":"Blue","pattern":"Tan"}}}}') returning id into draft;
 saved:=public.save_pedigree_draft(draft);
 if (select color_details->>'color' from public.animals where id=saved)<>'Blue' then raise exception 'Pedigree details missing'; end if;
 perform public.validate_animal_color_details('rabbit','English Angora','Broken','{}');
end $$;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
do $$ begin
 begin
 perform public.create_animal_with_color_details('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Foreign','COL03','rabbit','Mini Rex','Tan (COD)','Buck','active',null,'','',null,null,null,'{"color":"Black","pattern":"Tan"}');
 raise exception 'Foreign Ring insert allowed';
 exception when insufficient_privilege then null; end;
end $$;
rollback;

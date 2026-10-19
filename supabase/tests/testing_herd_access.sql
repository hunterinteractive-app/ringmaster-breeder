-- Exercise real verified onboarding and quotas; retain no synthetic records.
begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('e6101900-0000-4000-8000-000000000001','testing-grant@example.test',now()),
 ('e6101900-0000-4000-8000-000000000002','testing-disabled@example.test',now()),
 ('e6101900-0000-4000-8000-000000000003','testing-unverified@example.test',null);
update breeder_private.testing_access set enabled=true where singleton;
set local role authenticated;
select set_config('request.jwt.claim.sub','e6101900-0000-4000-8000-000000000001',true);
select public.breeder_family_access();
do $$ begin
 if (select count(*) from public.user_licenses where user_id='e6101900-0000-4000-8000-000000000001' and tier_code='HOBBY' and status='active')<>1 then
  raise exception 'New verified account did not receive one testing license';
 end if;
 perform public.create_breeder_ring('First testing herd','e6101900-0000-4000-8000-000000000001');
 begin
  perform public.create_breeder_ring('Second testing herd','e6101900-0000-4000-8000-000000000001');
  raise exception 'Second herd incorrectly allowed';
 exception when raise_exception then
  if sqlerrm<>'Ring limit reached' then raise; end if;
 end;
 begin
  update breeder_private.testing_access set enabled=false where singleton;
  raise exception 'Client can change testing enrollment';
 exception when insufficient_privilege then null;
 end;
end $$;
-- Repeat onboarding cannot issue another license or undo cancellation.
select public.breeder_family_access();
reset role;
update public.user_licenses set status='cancelled' where user_id='e6101900-0000-4000-8000-000000000001';
set local role authenticated;
select public.breeder_family_access();
select set_config('request.jwt.claim.sub','e6101900-0000-4000-8000-000000000003',true);
do $$ begin
 begin
  perform public.breeder_family_access();
  raise exception 'Unverified account allowed';
 exception when raise_exception then
  if sqlerrm<>'Verify your email first' then raise; end if;
 end;
end $$;
reset role;
update breeder_private.testing_access set enabled=false where singleton;
set local role authenticated;
select set_config('request.jwt.claim.sub','e6101900-0000-4000-8000-000000000002',true);
select public.breeder_family_access();
reset role;
do $$ begin
 if exists(select 1 from public.user_licenses where user_id in ('e6101900-0000-4000-8000-000000000002','e6101900-0000-4000-8000-000000000003')) then
  raise exception 'Disabled enrollment or unverified account received access';
 end if;
 if (select count(*) from public.user_licenses where user_id='e6101900-0000-4000-8000-000000000001')<>1
  or exists(select 1 from public.user_licenses where user_id='e6101900-0000-4000-8000-000000000001' and status<>'cancelled') then
  raise exception 'Repeat onboarding changed existing license';
 end if;
end $$;
rollback;

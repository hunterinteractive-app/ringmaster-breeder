-- Run on an isolated Breeder schema. Every synthetic row/change rolls back.
begin;
create function pg_temp.assert_true(value boolean,label text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception 'FAILED: %',label; end if; end $$;
update breeder_private.testing_access set enabled=false where singleton;
insert into auth.users(id,email,email_confirmed_at) values
 ('e6102100-0000-4000-8000-000000000001','quota-owner@example.test',now()),
 ('e6102100-0000-4000-8000-000000000002','quota-member@example.test',now()),
 ('e6102100-0000-4000-8000-000000000003','quota-outsider@example.test',now());
insert into public.users(id,username,email,auth_user_id) values
 ('quota-owner','quota_owner','quota-owner@example.test','e6102100-0000-4000-8000-000000000001'),
 ('quota-outsider','quota_outsider','quota-outsider@example.test','e6102100-0000-4000-8000-000000000003');
insert into public.user_licenses(user_id,tier_code,status) values('quota-owner','HOBBY','active');
insert into public.farms(id,name,owner_id,is_demo) values
 ('e6102100-0000-4000-8000-000000000010','Quota herd','quota-owner',false);
insert into breeder_private.invitations(owner_id,email,member_user_id,accepted_at) values
 ('quota-owner','quota-member@example.test','e6102100-0000-4000-8000-000000000002',now());
select pg_temp.assert_true((select annual_price_cents=4900 and max_active_animals=50 and max_rings=1 and not buyer_pedigree_email from license_tiers where code='HOBBY'),'Hobby catalogue');
select pg_temp.assert_true((select annual_price_cents=9900 and max_active_animals=250 and max_rings=1 and buyer_pedigree_email and custom_pedigree_branding and saved_pedigree_layouts from license_tiers where code='PRO'),'Pro catalogue');
select pg_temp.assert_true((select annual_price_cents=17900 and max_active_animals=1000 and max_rings=5 from license_tiers where code='TOP'),'Top catalogue');
set local role authenticated;
select set_config('request.jwt.claim.sub','e6102100-0000-4000-8000-000000000001',true);
insert into public.animals(ring_id,name,tattoo,species,sex,status)
 select 'e6102100-0000-4000-8000-000000000010','Quota '||i,'QUOTA-'||i,'rabbit','Doe','active' from generate_series(1,37) i;
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'warning_level')::int=0,'74% below warning');
insert into public.animals(ring_id,tattoo,species,status) values('e6102100-0000-4000-8000-000000000010','QUOTA-38','rabbit','active');
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'warning_level')::int=75,'75% boundary rounds upward by animal');
insert into public.animals(ring_id,tattoo,species,status)
 select 'e6102100-0000-4000-8000-000000000010','QUOTA-'||i,'rabbit','active' from generate_series(39,43) i;
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'warning_level')::int=85,'85% warning');
insert into public.animals(ring_id,tattoo,species,status)
 select 'e6102100-0000-4000-8000-000000000010','QUOTA-'||i,'rabbit','active' from generate_series(44,48) i;
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'warning_level')::int=95,'95% warning');
insert into public.animals(ring_id,tattoo,species,status)
 select 'e6102100-0000-4000-8000-000000000010','QUOTA-'||i,'rabbit','active' from generate_series(49,50) i;
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'warning_level')::int=100,'100% warning');
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'grace_ends_at')::timestamptz=now()+interval '30 days','Grace starts exactly at limit');
-- Grace allows births/imports beyond the limit.
insert into public.animals(ring_id,tattoo,species,status)
 select 'e6102100-0000-4000-8000-000000000010','QUOTA-'||i,'rabbit','active' from generate_series(51,52) i;
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'active_count')::int=52,'Grace growth counted');
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'grace_ends_at')::timestamptz=now()+interval '30 days','Growth does not extend deadline');
do $$ begin
 begin perform public.breeder_require_feature('quota-owner','buyer_pedigree_email'); raise exception 'Hobby email allowed';
 exception when insufficient_privilege then null; end;
 begin perform public.breeder_require_feature('quota-owner','custom_pedigree_branding'); raise exception 'Hobby branding allowed';
 exception when insufficient_privilege then null; end;
 begin update public.breeder_license_usage set limit_reached_at=null; raise exception 'Client altered grace';
 exception when insufficient_privilege then null; end;
 begin update public.license_tiers set max_active_animals=10000; raise exception 'Client altered tier';
 exception when insufficient_privilege then null; end;
end $$;
-- Shared members see the same owner's allowance, not their personal license.
select set_config('request.jwt.claim.sub','e6102100-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'active_count')::int=52,'Family shared usage');
select set_config('request.jwt.claim.sub','e6102100-0000-4000-8000-000000000003',true);
do $$ begin
 begin perform public.breeder_license_status('quota-owner'); raise exception 'Outsider read usage';
 exception when insufficient_privilege then null; end;
 begin perform public.breeder_require_feature('quota-owner','buyer_pedigree_email'); raise exception 'Outsider entitlement';
 exception when insufficient_privilege then null; end;
end $$;
select pg_temp.assert_true(not exists(select 1 from public.breeder_license_usage where owner_id='quota-owner'),'Usage RLS isolation');
reset role;
update public.breeder_license_usage set limit_reached_at=now()-interval '30 days' where owner_id='quota-owner';
set local role authenticated;
select set_config('request.jwt.claim.sub','e6102100-0000-4000-8000-000000000001',true);
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'growth_blocked')::boolean,'Blocked at exact deadline');
do $$ begin
 begin
  insert into public.animals(ring_id,tattoo,species,status) values('e6102100-0000-4000-8000-000000000010','DENIED','rabbit','active');
  raise exception 'Expired grace accepted animal';
 exception when raise_exception then if sqlerrm not like 'Your 30-day animal-limit%' then raise; end if; end;
 -- RPC path, used by the app and by offline replay, cannot bypass trigger.
 begin
  perform public.create_animal_with_color_details('e6102100-0000-4000-8000-000000000010','Denied RPC','DENIED-RPC','rabbit',null,null,'Doe','active',null,null,null,null,null,null,'{}');
  raise exception 'Expired grace accepted RPC';
 exception when raise_exception then if sqlerrm not like 'Your 30-day animal-limit%' then raise; end if; end;
end $$;
-- Exclusions and ordinary maintenance remain allowed after grace expires.
insert into public.animals(ring_id,tattoo,species,status,pedigree_only) values
 ('e6102100-0000-4000-8000-000000000010','SOLD','rabbit','sold',false),
 ('e6102100-0000-4000-8000-000000000010','DEAD','rabbit','deceased',false),
 ('e6102100-0000-4000-8000-000000000010','HISTORY','rabbit','archived',false),
 ('e6102100-0000-4000-8000-000000000010','ANCESTOR','rabbit','active',true);
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'active_count')::int=52,'All exclusions respected');
update public.animals set notes='Still editable after grace' where tattoo='QUOTA-1';
do $$ begin
 begin
  update public.animals set pedigree_only=false where tattoo='ANCESTOR'; raise exception 'Ancestor promotion bypass';
 exception when raise_exception then if sqlerrm not like 'Your 30-day animal-limit%' then raise; end if; end;
 begin
  update public.animals set status='active' where tattoo='HISTORY'; raise exception 'History promotion bypass';
 exception when raise_exception then if sqlerrm not like 'Your 30-day animal-limit%' then raise; end if; end;
end $$;
-- Capacity must actually fall below the limit; editing or deleting history is no reset.
update public.animals set status='sold' where tattoo in ('QUOTA-1','QUOTA-2');
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'growth_blocked')::boolean,'At limit remains blocked');
update public.animals set status='deceased' where tattoo='QUOTA-3';
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'active_count')::int=49 and public.breeder_license_status('quota-owner')->>'grace_ends_at' is null,'Dropping below clears grace');
reset role;
-- Upgrade, cancellation, expiry and future licenses.
update public.user_licenses set tier_code='PRO' where user_id='quota-owner';
set local role authenticated;
select pg_temp.assert_true(public.breeder_require_feature('quota-owner','buyer_pedigree_email'),'Pro email');
select pg_temp.assert_true(public.breeder_require_feature('quota-owner','custom_pedigree_branding'),'Pro branding entitlement');
select pg_temp.assert_true(public.breeder_require_feature('quota-owner','saved_pedigree_layouts'),'Pro layout entitlement');
reset role;
update public.user_licenses set expires_at=now() where user_id='quota-owner';
set local role authenticated;
select pg_temp.assert_true(not (public.breeder_license_status('quota-owner')->>'active')::boolean,'Expiry evaluated on server clock');
do $$ begin
 begin perform public.breeder_require_feature('quota-owner','buyer_pedigree_email'); raise exception 'Expired feature allowed'; exception when insufficient_privilege then null; end;
 begin insert into public.animals(ring_id,tattoo,species,status) values('e6102100-0000-4000-8000-000000000010','EXPIRED','rabbit','active'); raise exception 'Expired license growth';
 exception when raise_exception then if sqlerrm not like 'An active Breeder license%' then raise; end if; end;
end $$;
reset role;
update public.user_licenses set expires_at=null,started_at=now()+interval '1 day' where user_id='quota-owner';
set local role authenticated;
select pg_temp.assert_true(not (public.breeder_license_status('quota-owner')->>'active')::boolean,'Future license excluded');
reset role;
update public.user_licenses set tier_code='TOP',started_at=now() where user_id='quota-owner';
insert into public.user_licenses(user_id,tier_code,status) values('quota-owner','HOBBY','active');
set local role authenticated;
select pg_temp.assert_true(public.breeder_license_status('quota-owner')->>'code'='TOP','Highest plan consistently selected');
select public.create_breeder_ring('Second','quota-owner');
select public.create_breeder_ring('Third','quota-owner');
select public.create_breeder_ring('Fourth','quota-owner');
select public.create_breeder_ring('Fifth','quota-owner');
do $$ begin
 begin perform public.create_breeder_ring('Sixth','quota-owner'); raise exception 'Sixth herd allowed';
 exception when raise_exception then if sqlerrm<>'Ring limit reached' then raise; end if; end;
end $$;
insert into public.animals(ring_id,tattoo,species,status)
 select id,'SECOND-ACTIVE','rabbit','active' from public.farms where owner_id='quota-owner' and name='Second';
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'active_count')::int=50,'Account-wide count across herds');
select pg_temp.assert_true((public.breeder_license_status('quota-owner')->>'current_rings')::int=5,'Account-wide herd count');
reset role;
select pg_temp.assert_true((select active_count from public.breeder_license_usage where owner_id='quota-owner')=(select count(*) from public.animals a join public.farms f on f.id=a.ring_id where f.owner_id='quota-owner' and not coalesce(f.is_demo,false) and a.status='active' and not a.pedigree_only),'Counter reconciles with records');
rollback;

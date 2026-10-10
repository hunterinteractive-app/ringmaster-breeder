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
insert into animals(ring_id,species,sex,breed,variety) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','rabbit','Buck','  fixture   BREED','  custom   COLOR');
insert into animals(ring_id,species,sex,breed,variety) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','rabbit','Doe','Fixture Breed','Custom Color');
do $$ begin
if (select count(*) from breeds where catalog_key='fixture breed')<>1 then raise exception 'Duplicate breed'; end if;
if not exists(select 1 from animals where breed='Fixture Breed' and variety='Custom Color') then raise exception 'Normalization failed'; end if;
if exists(select 1 from breeds where catalog_key='fixture breed' and is_recognized) then raise exception 'Custom recognized'; end if;
end $$;
rollback;

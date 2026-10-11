begin;
-- Fictional accounts and records only; everything rolls back.
insert into auth.users(id,email,email_confirmed_at) values ('a0000000-0000-0000-0000-000000000001','deletion-test@example.invalid',now()),('a0000000-0000-0000-0000-000000000002','retained-test@example.invalid',now());
insert into public.users(id,username,email,auth_user_id) values ('delete-fixture','delete-fixture','deletion-test@example.invalid','a0000000-0000-0000-0000-000000000001'),('keep-fixture','keep-fixture','retained-test@example.invalid','a0000000-0000-0000-0000-000000000002');
insert into public.farms(id,name,owner_id) values ('a1000000-0000-0000-0000-000000000001','Delete fixture','delete-fixture'),('a1000000-0000-0000-0000-000000000002','Keep fixture','keep-fixture');
insert into public.animals(id,ring_id,tattoo,species,breed,sex) values ('a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','DELETE-S','rabbit','Tan','Buck'),('a2000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000001','DELETE-D','rabbit','Tan','Doe'),('a2000000-0000-0000-0000-000000000003','a1000000-0000-0000-0000-000000000002','KEEP','rabbit','Tan','Doe');
insert into public.animal_weights(animal_id,weight) values ('a2000000-0000-0000-0000-000000000001',4);
insert into public.breeding_records(id,sire_id,dam_id,breeding_date) values ('a3000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000002',current_date);
insert into public.breeding_tracking(breeding_id) values ('a3000000-0000-0000-0000-000000000001');
-- A parent referenced by another household must block deletion before locking.
alter table public.animals disable trigger breeder_validate_animal;
update public.animals set sire_id='a2000000-0000-0000-0000-000000000001' where tattoo='KEEP';
do $$ begin
 begin
  perform public.begin_account_deletion('a0000000-0000-0000-0000-000000000001');
  raise exception 'Expected shared-data refusal';
 exception when others then
  if sqlerrm not like '%ACCOUNT_SHARED_DATA_REVIEW%' then raise; end if;
 end;
 if exists(select 1 from public.account_deletions where owner_id='delete-fixture') then raise exception 'Deletion started despite shared data'; end if;
end $$;
update public.animals set sire_id=null where tattoo='KEEP';
alter table public.animals enable trigger breeder_validate_animal;
set local role service_role;
select public.begin_account_deletion('a0000000-0000-0000-0000-000000000001');
select public.begin_account_deletion('a0000000-0000-0000-0000-000000000001');
select public.purge_account_data('a0000000-0000-0000-0000-000000000001');
select public.purge_account_data('a0000000-0000-0000-0000-000000000001');
reset role;
do $$ begin
 if exists(select 1 from public.farms where owner_id='delete-fixture') or exists(select 1 from public.animals where tattoo in ('DELETE-S','DELETE-D')) then raise exception 'Owned data remains'; end if;
 if not exists(select 1 from public.animals where tattoo='KEEP') then raise exception 'Other household damaged'; end if;
 if exists(select 1 from public.users where id='delete-fixture' and is_active) then raise exception 'Profile not locked'; end if;
 if has_function_privilege('authenticated','public.purge_account_data(uuid)','execute') or has_function_privilege('anon','public.begin_account_deletion(uuid)','execute') then raise exception 'Unsafe function grants'; end if;
end $$;
-- Simulate Auth's final database deletion to validate all foreign keys.
delete from auth.users where id='a0000000-0000-0000-0000-000000000001';
do $$ begin
 if exists(select 1 from public.users where id='delete-fixture') or exists(select 1 from public.account_deletions where owner_id='delete-fixture') then raise exception 'Identity cleanup incomplete'; end if;
end $$;
rollback;

begin;
-- Fictional accounts and records only; everything rolls back.
insert into auth.users(id,email,email_confirmed_at) values ('a0000000-0000-0000-0000-000000000001','deletion-test@example.invalid',now()),('a0000000-0000-0000-0000-000000000002','retained-test@example.invalid',now());
insert into public.users(id,username,email,auth_user_id) values ('delete-fixture','delete-fixture','deletion-test@example.invalid','a0000000-0000-0000-0000-000000000001'),('keep-fixture','keep-fixture','retained-test@example.invalid','a0000000-0000-0000-0000-000000000002');
insert into public.farms(id,name,owner_id) values ('a1000000-0000-0000-0000-000000000001','Delete fixture','delete-fixture'),('a1000000-0000-0000-0000-000000000002','Keep fixture','keep-fixture');
insert into public.animals(id,ring_id,tattoo,species,breed,sex) values ('a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','DELETE-S','rabbit','Tan','Buck'),('a2000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000001','DELETE-D','rabbit','Tan','Doe'),('a2000000-0000-0000-0000-000000000003','a1000000-0000-0000-0000-000000000002','KEEP','rabbit','Tan','Doe');

do $$ begin
 begin
  insert into public.animals(ring_id,tattoo,species,breed,sex) values ('a1000000-0000-0000-0000-000000000001',' delete-s ','cavy','American','Boar');
  raise exception 'Duplicate tattoo was accepted';
 exception when unique_violation then null;
 end;
 begin
  update public.animals set tattoo='DELETE-S' where tattoo='DELETE-D';
  raise exception 'Duplicate edit was accepted';
 exception when unique_violation then null;
 end;
end $$;
-- The same tattoo is allowed in a different herd; blank ancestor tattoos remain valid.
insert into public.animals(ring_id,tattoo,species,breed,sex) values ('a1000000-0000-0000-0000-000000000002','DELETE-S','rabbit','Tan','Buck'),('a1000000-0000-0000-0000-000000000001','','rabbit','Tan','Buck'),('a1000000-0000-0000-0000-000000000001','','rabbit','Tan','Buck');
rollback;

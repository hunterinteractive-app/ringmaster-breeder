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
select public.create_breeder_ring('Second Ring','legacy-owner');
do $$ begin
 begin perform public.create_breeder_ring('Over quota','legacy-owner'); raise exception 'Quota bypass';
 exception when raise_exception then if sqlerrm='Quota bypass' then raise; end if; end;
end $$;
insert into public.animals(id,ring_id,name,species,sex) values
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Fixture rabbit','rabbit','M');
insert into public.animal_weights(animal_id,weight) values('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',4.25);
insert into public.animal_health_records(animal_id,title,record_type,administered_date) values('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Fixture vaccine','vaccine',current_date);
insert into storage.objects(bucket_id,name) values('health_attachments','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/test.pdf');
do $$ declare v_snapshot jsonb; begin
 v_snapshot:=public.breeder_pedigree_snapshot('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
 if v_snapshot->'animal'->>'name'<>'Fixture rabbit' or (v_snapshot->'animal'->>'weight')::numeric<>4.25 then raise exception 'Pedigree snapshot failed'; end if;
end $$;
select public.breeder_family_access('invite',null,'member@example.test');
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
select public.breeder_family_access();
do $$ begin
 if public.breeder_pedigree_snapshot('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')<>'{}'::jsonb then raise exception 'Outsider pedigree leaked'; end if;
 if exists(select 1 from public.animals) or exists(select 1 from public.animal_weights) or exists(select 1 from public.animal_health_records) or exists(select 1 from storage.objects) then raise exception 'Outsider read leaked'; end if;
 begin update public.user_licenses set tier_code='FIXTURE'; raise exception 'License escalation allowed'; exception when insufficient_privilege then null; end;
 begin insert into public.animals(ring_id,species) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','rabbit'); raise exception 'Outsider insert allowed'; exception when insufficient_privilege then null; end;
 begin perform public.create_breeder_ring('Foreign Ring','legacy-owner'); raise exception 'Outsider ring creation allowed'; exception when raise_exception then if sqlerrm='Outsider ring creation allowed' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
select public.breeder_family_access();
do $$ declare v_invite uuid; begin
 if exists(select 1 from public.animals) then raise exception 'Pending invitation granted access'; end if;
 select (i->>'id')::uuid into v_invite from jsonb_array_elements(public.breeder_family_access()->'invitations') i where i->>'email'='member@example.test';
 perform public.breeder_family_access('accept',v_invite);
 if (select count(*) from public.farms)<>2 then raise exception 'Member cannot see whole family'; end if;
 if not exists(select 1 from public.animals) or not exists(select 1 from public.animal_weights) or not exists(select 1 from public.animal_health_records) or not exists(select 1 from storage.objects) then raise exception 'Member records missing'; end if;
 update public.animals set name='Edited by family' where id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 insert into public.animal_weights(animal_id,weight) values('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',4.50);
 update public.animal_health_records set title='Edited health' where animal_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 begin perform public.breeder_family_access('revoke',v_invite); raise exception 'Member revoked owner invitation'; exception when raise_exception then if sqlerrm='Member revoked owner invitation' then raise; end if; end;
 begin update public.users set auth_user_id=auth.uid() where id='legacy-owner'; raise exception 'Identity escalation allowed'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
do $$ declare v_invite uuid; begin
 select (i->>'id')::uuid into v_invite from jsonb_array_elements(public.breeder_family_access()->'invitations') i where i->>'email'='member@example.test';
 perform public.breeder_family_access('revoke',v_invite);
end $$;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
do $$ begin
 if exists(select 1 from public.farms where owner_id='legacy-owner') or exists(select 1 from public.animals) or exists(select 1 from storage.objects) then raise exception 'Revoked access survived'; end if;
end $$;
reset role;
rollback;

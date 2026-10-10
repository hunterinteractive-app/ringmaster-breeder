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
insert into storage.objects(bucket_id,name) values('animal_photos','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/photo.png');
update public.animals set photo_path='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/photo.png' where id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
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
set local role service_role;
select set_config('request.jwt.claim.role','service_role',true);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select public.apply_breeder_cross_app_import(
 '11111111-1111-4111-8111-111111111111','ringmaster_show',
 '[{"id":"99999999-9999-4999-8999-999999999999","display_name":"Fixture profile","first_name":"Fixture","last_name":"Owner"}]',
 '[{"id":"88888888-8888-4888-8888-888888888888","name":"Imported fixture","tattoo":"IMPORT-FIXTURE","species":"rabbit","breed":"Fixture","sex":"Buck"}]',
 '[{"id":"77777777-7777-4777-8777-777777777777","animal_id":"88888888-8888-4888-8888-888888888888","exhibitor_id":"99999999-9999-4999-8999-999999999999","placement":"1"}]',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select public.apply_breeder_cross_app_import(
 '11111111-1111-4111-8111-111111111111','ringmaster_show',
 '[{"id":"99999999-9999-4999-8999-999999999999","display_name":"Fixture profile"}]',
 '[{"id":"88888888-8888-4888-8888-888888888888","name":"Changed source name","tattoo":"IMPORT-FIXTURE","species":"rabbit","breed":"Fixture","sex":"Buck"}]',
 '[{"id":"77777777-7777-4777-8777-777777777777","animal_id":"88888888-8888-4888-8888-888888888888","exhibitor_id":"99999999-9999-4999-8999-999999999999","placement":"1"}]',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
do $$ declare v_before int; v_result jsonb; v_data jsonb; begin
 select count(*) into v_before from public.animals;
 v_data:='[{"id":"66666666-6666-4666-8666-666666666666","animal_id":"55555555-5555-4555-8555-555555555555","exhibitor_id":"99999999-9999-4999-8999-999999999999","tattoo":"IMPORT-FIXTURE","species":"rabbit","breed":"Fixture","sex":"Buck","placement":"2"},{"id":"44444444-4444-4444-8444-444444444444","exhibitor_id":"99999999-9999-4999-8999-999999999999","tattoo":"UNMATCHED-FIXTURE","species":"rabbit","breed":"Fixture","sex":"Buck"}]';
 v_result:=public.apply_breeder_cross_app_import('11111111-1111-4111-8111-111111111111','ringmaster_show','[{"id":"99999999-9999-4999-8999-999999999999"}]','[]',v_data,null);
 if (select count(*) from public.animals)<>v_before or (v_result->>'animals_added')::int<>0 then raise exception 'Results-only import created animals'; end if;
 if not exists(select 1 from public.breeder_show_history where source_entry_id='66666666-6666-4666-8666-666666666666' and animal_id is not null) then raise exception 'Existing animal did not link'; end if;
 if not exists(select 1 from public.breeder_show_history where source_entry_id='44444444-4444-4444-8444-444444444444' and animal_id is null) then raise exception 'Unmatched result guessed an animal'; end if;
 v_result:=public.apply_breeder_cross_app_import('11111111-1111-4111-8111-111111111111','ringmaster_show','[{"id":"99999999-9999-4999-8999-999999999999"}]','[]',v_data,null);
 if (v_result->>'entries_added')::int<>0 then raise exception 'Repeat results duplicated history'; end if;
end $$;
do $$ begin
 if (select count(*) from public.breeder_exhibitor_profiles where owner_id='legacy-owner')<>1 then raise exception 'Duplicate profiles'; end if;
 if (select count(*) from public.breeder_imported_animals where owner_id='legacy-owner')<>1 then raise exception 'Duplicate animals'; end if;
 if (select count(*) from public.breeder_show_history where owner_id='legacy-owner')<>3 then raise exception 'Duplicate history'; end if;
 if not exists(select 1 from public.animals where name='Imported fixture' and sex='Buck') then raise exception 'Existing animal overwritten'; end if;
 if (public.find_exhibitors_for_breeder_export('owner@example.test')->0->'profile'->>'display_name')<>'Fixture profile' then raise exception 'Breeder export failed'; end if;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
do $$ begin
 if exists(select 1 from public.breeder_show_history) or exists(select 1 from public.breeder_exhibitor_profiles) then raise exception 'Outsider import leak'; end if;
 begin perform public.find_exhibitors_for_breeder_export('owner@example.test'); raise exception 'Client exporter allowed'; exception when insufficient_privilege then null; end;
 begin perform public.apply_breeder_cross_app_import('11111111-1111-4111-8111-111111111111','ringmaster_show','[]'); raise exception 'Client import writer allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
-- Verify all species names and legacy writes during the deployment transition.
insert into public.animals(id,ring_id,name,species,sex) values
 ('10101010-1010-4010-8010-101010101010','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Fixture doe','rabbit','F'),
 ('20202020-2020-4020-8020-202020202020','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Fixture boar','cavy','M'),
 ('30303030-3030-4030-8030-303030303030','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Fixture sow','cavy','Sow');
insert into public.animals(ring_id,name,species,sex,sire_id,dam_id) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Fixture offspring','rabbit','Doe','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','10101010-1010-4010-8010-101010101010'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Fixture cavy offspring','cavy','Boar','20202020-2020-4020-8020-202020202020','30303030-3030-4030-8030-303030303030');
do $$ begin
 if exists(select 1 from public.animals where sex in ('M','F')) then raise exception 'Legacy sex code persisted'; end if;
 if not exists(select 1 from public.animals where name='Fixture doe' and sex='Doe') then raise exception 'Doe conversion failed'; end if;
 if not exists(select 1 from public.animals where name='Fixture boar' and sex='Boar') then raise exception 'Boar conversion failed'; end if;
 if not exists(select 1 from public.animals where name='Fixture sow' and sex='Sow') then raise exception 'Sow failed'; end if;
 begin
 insert into public.animals(ring_id,species,sex,sire_id) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','rabbit','Buck','10101010-1010-4010-8010-101010101010');
 raise exception 'Female sire accepted';
 exception when raise_exception then if sqlerrm='Female sire accepted' then raise; end if; end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claim.role','authenticated',true);
do $$ declare draft uuid; animal uuid; again uuid; snapshot jsonb; before_count integer; begin
 insert into public.pedigree_drafts(ring_id,data) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 '{"species":"rabbit","root":"r","nodes":{"r":{"name":"Pedigree test root","tattoo":"PEDROOT","sex":"Doe","sire":"s","dam":"d"},"s":{"name":"Repeated sire","tattoo":"PEDSIRE","sex":"Buck","legs":"3","weight":"4.5"},"d":{"name":"Dam","tattoo":"PEDDAM","sex":"Doe","sire":"s"}}}') returning id into draft;
 animal:=public.save_pedigree_draft(draft);
 again:=public.save_pedigree_draft(draft);
 if animal<>again then raise exception 'Retry created duplicate'; end if;
 snapshot:=public.breeder_pedigree_snapshot(animal);
 if snapshot->'sire'->>'id' is distinct from snapshot->'dam_sire'->>'id' then raise exception 'Repeated ancestor duplicated'; end if;
 if (select count(*) from public.animals where tattoo in ('PEDROOT','PEDSIRE','PEDDAM'))<>3 then raise exception 'Wrong animal count'; end if;
 if (select count(*) from public.animals where tattoo in ('PEDSIRE','PEDDAM') and pedigree_only)<>2 then raise exception 'Ancestors not separated'; end if;
 if (snapshot->'sire'->>'weight')::numeric<>4.5 then raise exception 'Weight missing'; end if;
 select count(*) into before_count from public.animals;
 insert into public.pedigree_drafts(ring_id,data) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','{"species":"rabbit","root":"r","nodes":{"r":{"name":"Cycle root","sex":"Buck","sire":"r"}}}') returning id into draft;
 begin perform public.save_pedigree_draft(draft); raise exception 'Cycle accepted'; exception when raise_exception then if sqlerrm='Cycle accepted' then raise; end if; end;
 if (select count(*) from public.animals)<>before_count then raise exception 'Failed save left records'; end if;
end $$;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
do $$ begin if exists(select 1 from public.pedigree_drafts) then raise exception 'Draft leaked'; end if; end $$;
reset role;

rollback;

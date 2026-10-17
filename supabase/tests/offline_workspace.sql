-- Isolated-schema test only. The runner supplies fixture.offline_operation from
-- tool/offline_workspace_test.cjs. Every synthetic identity/record rolls back.
begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('11111111-1111-4111-8111-111111111111','owner@example.test',now()),
 ('33333333-3333-4333-8333-333333333333','outsider@example.test',now());
insert into public.users(id,username,email) values('legacy-owner','fixture_owner','owner@example.test'),('other-owner','fixture_other','outsider@example.test');
insert into public.license_tiers(code,name,max_rings) values('OFFLINE_TEST','Fixture',10);
insert into public.user_licenses(user_id,tier_code,status) values('legacy-owner','OFFLINE_TEST','active');
insert into public.farms(id,name,owner_id) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Fixture herd','legacy-owner'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Private other herd','other-owner');
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select public.breeder_family_access();
do $$ declare op jsonb=current_setting('fixture.offline_operation')::jsonb; first jsonb; again jsonb; snapshot jsonb; aid uuid; begin
 snapshot=public.breeder_offline_snapshot();
 if jsonb_array_length(snapshot->'tables'->'farms')<>1 then raise exception 'Snapshot leaked another herd';end if;
 if not(snapshot->'tables' ? 'animal_health_records') then raise exception 'Snapshot omitted a required table';end if;
 first=public.breeder_offline_apply(op-'expected_id');
 again=public.breeder_offline_apply(op-'expected_id');
 if first<>again or first->>'state'<>'applied' then raise exception 'Lost-ACK retry changed its receipt';end if;
 aid=(first->>'result')::uuid;
 if aid<>(op->>'expected_id')::uuid then raise exception 'Client/server generated different IDs: % <> %',aid,op->>'expected_id';end if;
 if (select count(*) from public.animals where tattoo='RECEIPT')<>1 or (select count(*) from public.animal_weights where animal_id=aid)<>1 then raise exception 'Retry duplicated related records';end if;
 begin
  perform public.breeder_offline_apply(jsonb_set(op-'expected_id','{request,body,p_name}','"Different"'));
  raise exception 'Changed receipt payload accepted';
 exception when raise_exception then if sqlerrm='Changed receipt payload accepted' then raise;end if;end;
 if public.breeder_offline_snapshot(snapshot->'versions')->'tables' ? 'users' then raise exception 'Unchanged table re-downloaded';end if;
 if not(public.breeder_offline_snapshot(snapshot->'versions')->'tables' ? 'animals') then raise exception 'New records missing from next download';end if;
end $$;
do $$ declare a public.animals; op jsonb; result jsonb; begin
 select * into a from public.animals where tattoo='RECEIPT';
 op=jsonb_build_object('id',gen_random_uuid(),'request',jsonb_build_object('type','table','target','animals','method','PATCH','body',jsonb_build_object('name','Offline name')),
 'expects',jsonb_build_array(jsonb_build_object('table','animals','key',jsonb_build_object('id',a.id),'before',jsonb_build_object('name',a.name))),
 'mutations',jsonb_build_array(jsonb_build_object('table','animals','action','update','row',jsonb_build_object('id',a.id,'name','Offline name'))));
 update public.animals set registration_number='Independent change' where id=a.id;
 result=public.breeder_offline_apply(op);
 if result->>'state'<>'applied' or (select registration_number from public.animals where id=a.id)<>'Independent change' then raise exception 'Independent fields did not merge';end if;
 op=jsonb_set(op,'{id}',to_jsonb(gen_random_uuid()));
 op=jsonb_set(op,'{request,body,name}','"Conflicting local"');
 op=jsonb_set(op,'{mutations,0,row,name}','"Conflicting local"');
 result=public.breeder_offline_apply(op);
 if result->>'state'<>'conflict' or (select name from public.animals where id=a.id)<>'Offline name' then raise exception 'Competing fields overwrote server data';end if;
end $$;
do $$ declare aid uuid; op jsonb; begin
 select id into aid from public.animals where tattoo='RECEIPT';
 op=jsonb_build_object('id',gen_random_uuid(),'request',jsonb_build_object('type','table','target','animal_health_records','method','POST','body',jsonb_build_array(
  jsonb_build_object('id','dddddddd-dddd-4ddd-8ddd-dddddddddddd','animal_id',aid,'title','Valid first','record_type','health','administered_date','2026-10-17'),
  jsonb_build_object('id','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','animal_id',aid,'title',null,'record_type','health','administered_date','2026-10-17'))),
  'expects','[]'::jsonb,'mutations',jsonb_build_array(
   jsonb_build_object('table','animal_health_records','action','insert','row',jsonb_build_object('id','dddddddd-dddd-4ddd-8ddd-dddddddddddd')),
   jsonb_build_object('table','animal_health_records','action','insert','row',jsonb_build_object('id','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'))));
 begin perform public.breeder_offline_apply(op);raise exception 'Invalid batch accepted';exception when not_null_violation then null;end;
 if exists(select 1 from public.animal_health_records where id='dddddddd-dddd-4ddd-8ddd-dddddddddddd') then raise exception 'Partial batch was saved';end if;
 if exists(select 1 from public.breeder_offline_receipts where operation_id=(op->>'id')::uuid) then raise exception 'Failed operation received a receipt';end if;
end $$;
-- Exercise the actual existing RPCs/triggers with client-generated projections.
do $$ declare x jsonb; op jsonb; first jsonb; again jsonb; m jsonb; exists_row boolean; begin
 for x in select value from jsonb_array_elements(current_setting('fixture.offline_workflows')::jsonb) loop
  op=x->'operation';
  begin
   first=public.breeder_offline_apply(op);again=public.breeder_offline_apply(op);
   if first<>again or first->>'state'<>'applied' then raise exception 'Expected replayable application: %',first;end if;
   if op->'request'->>'type'='rpc' and first->'result' is distinct from x->'expected' then raise exception 'RPC result/IDs differ: % <> %',first->'result',x->'expected';end if;
   for m in select value from jsonb_array_elements(op->'mutations') loop
    if m->>'action'='insert' and not coalesce((m->>'derived')::boolean,false) and m->'row' ? 'id' then
     execute format('select exists(select 1 from public.%I where id=$1)',m->>'table') into exists_row using (m->'row'->>'id')::uuid;
     if not exists_row then raise exception 'Server generated a different % ID',m->>'table';end if;
    end if;
   end loop;
  exception when others then raise exception 'Workflow %: %',x->>'label',sqlerrm;end;
 end loop;
 if not exists(select 1 from public.animals where tattoo='FLOWDOE' and status='sold') then raise exception 'Sale payment did not complete its animal status';end if;
 if (select count(*) from public.breeding_offspring)<>2 then raise exception 'Lost-ACK offspring retry duplicated/omitted animals';end if;
 if exists(select 1 from public.farms where name='Renamed workflow herd') then raise exception 'Empty herd deletion failed';end if;
 begin perform public.delete_empty_breeder_ring('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');raise exception 'Nonempty herd deleted';
 exception when raise_exception then if sqlerrm='Nonempty herd deleted' then raise;end if;end;
 begin update public.users set is_active=false where id='legacy-owner';raise exception 'Protected profile column changed';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
-- Apply the real existing storage policies to synthetic file manifests.
insert into storage.objects(bucket_id,name,metadata) select 'animal_photos',id::text||'/fixture.jpg','{"size":100}'::jsonb from public.animals where tattoo='RECEIPT';
insert into storage.objects(bucket_id,name,metadata) values('animal_photos','ffffffff-ffff-4fff-8fff-ffffffffffff/private.jpg','{"size":100}');
insert into public.breeder_offline_jobs(id,actor,target,payload,state,payload_hash) values('12121212-1212-4212-8212-121212121212','11111111-1111-4111-8111-111111111111','import-ringmaster-records','{"action":"lookup"}','complete',repeat('0',64));
set local role authenticated;
do $$begin
 if jsonb_array_length(public.breeder_offline_snapshot()->'files')<>1 then raise exception 'Storage manifest leaked an inaccessible file';end if;
 if (select count(*) from public.breeder_offline_jobs)<>1 then raise exception 'Own job not visible';end if;
end $$;
-- The service-only import transaction returns the original result on retries.
reset role;
set local role service_role;
select set_config('request.jwt.claim.role','service_role',true);
do $$declare first jsonb; again jsonb; selection jsonb='{"action":"import","source":"ringmaster_club","profile_ids":["56565656-5656-4656-8656-565656565656"]}';begin
 first=public.breeder_offline_import_once('11111111-1111-4111-8111-111111111111','34343434-3434-4434-8434-343434343434',selection,'ringmaster_club','[{"id":"56565656-5656-4656-8656-565656565656","display_name":"Imported"}]','[]','[]',null);
 again=public.breeder_offline_import_once('11111111-1111-4111-8111-111111111111','34343434-3434-4434-8434-343434343434',selection,'ringmaster_club','[]','[]','[]',null);
 if first<>again then raise exception 'Import retry did not retain its first result';end if;
 begin perform public.breeder_offline_import_once('11111111-1111-4111-8111-111111111111','34343434-3434-4434-8434-343434343434','{}','ringmaster_club','[]','[]','[]',null);raise exception 'Changed import accepted';exception when raise_exception then if sqlerrm='Changed import accepted' then raise;end if;end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
select public.breeder_family_access();
do $$ declare op jsonb=current_setting('fixture.offline_operation')::jsonb; result jsonb; begin
 if exists(select 1 from public.breeder_offline_jobs) then raise exception 'Another account read jobs';end if;
 if jsonb_array_length(public.breeder_offline_snapshot()->'files')<>0 then raise exception 'Another account downloaded files';end if;
 if exists(select 1 from public.breeder_offline_receipts) then raise exception 'Another account read receipts';end if;
 if jsonb_array_length(public.breeder_offline_snapshot()->'tables'->'animals')<>0 then raise exception 'Another account downloaded animals';end if;
 begin perform public.breeder_offline_apply(op-'expected_id');raise exception 'Another account applied the operation';
 exception when insufficient_privilege then null;end;
end $$;
rollback;

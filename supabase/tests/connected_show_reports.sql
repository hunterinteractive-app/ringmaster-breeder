begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('11111111-1111-4111-8111-111111111111','reports-owner@example.test',now()),
 ('22222222-2222-4222-8222-222222222222','reports-outsider@example.test',now());
insert into public.users(id,username,email,auth_user_id) values
 ('reports-owner','reports_fixture','reports-owner@example.test','11111111-1111-4111-8111-111111111111');
insert into public.show_connections(id,user_id,show_user_id,reports_enabled,reports_changed_at) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222',true,'2026-01-01');
set local role service_role;
do $$
declare c uuid:='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; p jsonb; r jsonb; answer jsonb;
begin
 p:='[{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","show_name":"Test report","storage_path":"private/file.pdf","storage_bucket":"private"}]';
 r:='[{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","exhibitor_id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","placement":"1","tattoo":"UNMATCHED"}]';
 perform public.apply_connected_show_reports(c,'2026-01-01','2026-01-02',p,r);
 perform public.apply_connected_show_reports(c,'2026-01-01','2026-01-03',p,replace(r::text,'"1"','"2"')::jsonb);
 if (select count(*) from public.breeder_show_history where owner_id='reports-owner')<>1 then raise exception 'Duplicate results'; end if;
 if not exists(select 1 from public.breeder_show_history where owner_id='reports-owner' and record->>'placement'='2' and animal_id is null) then raise exception 'Correction or unmatched handling failed'; end if;
 if exists(select 1 from public.connected_show_reports where connection_id=c and record ? 'storage_path') then raise exception 'Storage path exposed'; end if;
 answer:=public.apply_connected_show_reports(c,'2026-01-01','2026-01-02','[]','[]');
 if answer->>'stale'<>'true' then raise exception 'Stale snapshot applied'; end if;
 perform public.apply_connected_show_reports(c,'2026-01-01','2026-01-04','[]','[]');
 if not exists(select 1 from public.connected_show_reports where connection_id=c and not source_available) then raise exception 'Withdrawn report not preserved'; end if;
 update public.show_connections set reports_enabled=false where id=c;
 begin
  perform public.apply_connected_show_reports(c,'2026-01-01','2026-01-05',p,r);
  raise exception 'Disabled receiving allowed';
 exception when raise_exception then if sqlerrm='Disabled receiving allowed' then raise; end if; end;
 if has_function_privilege('authenticated','public.apply_connected_show_reports(uuid,timestamptz,timestamptz,jsonb,jsonb)','execute') then raise exception 'Client allowed server import'; end if;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
do $$ begin
 if not exists(select 1 from public.connected_show_reports where owner_id='reports-owner') then raise exception 'Owner report unavailable'; end if;
end $$;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
do $$ begin
 if exists(select 1 from public.connected_show_reports where owner_id='reports-owner') then raise exception 'Other account report leaked'; end if;
end $$;
rollback;

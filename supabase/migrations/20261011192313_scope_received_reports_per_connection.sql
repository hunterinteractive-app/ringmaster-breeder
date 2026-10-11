alter table public.connected_show_reports drop constraint connected_show_reports_pkey;
alter table public.connected_show_reports add primary key(connection_id,id);
create or replace function public.apply_connected_show_reports(p_connection uuid,p_version timestamptz,p_started timestamptz,p_reports jsonb,p_results jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.show_connections; v_owner text; r jsonb; v_animal uuid; v_count int:=0;
begin
 select * into c from public.show_connections where id=p_connection for update;
 if c.id is null or not c.reports_enabled or c.reports_changed_at<>p_version then raise exception 'Report receiving settings changed'; end if;
 if c.last_reports_synced_at is not null and c.last_reports_synced_at>p_started then return jsonb_build_object('stale',true); end if;
 select id into v_owner from public.users where auth_user_id=c.user_id and is_active;
 if v_owner is null then raise exception 'Account unavailable'; end if;
 if jsonb_typeof(p_reports)<>'array' or jsonb_typeof(p_results)<>'array' or jsonb_array_length(p_reports)>10000 or jsonb_array_length(p_results)>10000 then raise exception 'Invalid report snapshot'; end if;
 update public.connected_show_reports set source_available=false where connection_id=c.id;
 update public.breeder_show_history set source_available=false where report_connection_id=c.id;
 for r in select value from jsonb_array_elements(p_reports) loop
  insert into public.connected_show_reports(id,connection_id,owner_id,record)
  values((r->>'id')::uuid,c.id,v_owner,r-'storage_bucket'-'storage_path')
  on conflict(connection_id,id) do update set record=excluded.record,source_available=true,received_at=now()
   where public.connected_show_reports.connection_id=c.id;
 end loop;
 for r in select value from jsonb_array_elements(p_results) loop
  v_animal:=null;
  select a.id into v_animal from public.animals a join public.farms f on f.id=a.ring_id
   where a.id=nullif(r->>'breeder_animal_id','')::uuid and f.owner_id=v_owner;
  if v_animal is null then
   select a.id into v_animal from public.breeder_imported_animals i join public.animals a on a.id=i.animal_id
    join public.farms f on f.id=a.ring_id where i.owner_id=v_owner and f.owner_id=v_owner
    and i.source_app='ringmaster_show' and i.source_id=nullif(r->>'animal_id','')::uuid;
  end if;
  insert into public.breeder_show_history(owner_id,source_app,source_entry_id,animal_id,exhibitor_source_id,record,report_connection_id,source_available)
  values(v_owner,'ringmaster_show',(r->>'id')::uuid,v_animal,(r->>'exhibitor_id')::uuid,r-'breeder_animal_id',c.id,true)
  on conflict(owner_id,source_app,source_entry_id) do update
   set record=excluded.record,animal_id=coalesce(excluded.animal_id,public.breeder_show_history.animal_id),
    report_connection_id=c.id,source_available=true;
  v_count:=v_count+1;
 end loop;
 update public.show_connections set last_reports_synced_at=p_started,last_reports_error=null where id=c.id;
 return jsonb_build_object('reports',jsonb_array_length(p_reports),'results',v_count);
end $$;
revoke all on function public.apply_connected_show_reports(uuid,timestamptz,timestamptz,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.apply_connected_show_reports(uuid,timestamptz,timestamptz,jsonb,jsonb) to service_role;

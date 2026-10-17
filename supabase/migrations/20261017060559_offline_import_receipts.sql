-- Cross-app selections and their result are committed together. Only the
-- verified import Edge Function may supply records from another application.
create function public.breeder_offline_import_once(p_actor uuid,p_id uuid,p_selection jsonb,
 p_source text,p_profiles jsonb,p_animals jsonb,p_entries jsonb,p_ring uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare saved public.breeder_offline_receipts; fingerprint text; result jsonb;
begin
 if p_actor is null or p_id is null then raise exception 'Missing import identity';end if;
 fingerprint=encode(extensions.digest(p_selection::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text||':'||p_id::text,0));
 select * into saved from public.breeder_offline_receipts where actor=p_actor and operation_id=p_id;
 if found then
  if saved.payload_hash<>fingerprint then raise exception 'A different selection already uses this ID';end if;
  return saved.result;
 end if;
 if exists(select 1 from public.account_deletions where user_id=p_actor) then raise exception 'Account deletion is pending';end if;
 result=public.apply_breeder_cross_app_import(p_actor,p_source,p_profiles,p_animals,p_entries,p_ring);
 insert into public.breeder_offline_receipts(actor,operation_id,payload_hash,result) values(p_actor,p_id,fingerprint,result);
 return result;
end $$;
revoke all on function public.breeder_offline_import_once(uuid,uuid,jsonb,text,jsonb,jsonb,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.breeder_offline_import_once(uuid,uuid,jsonb,text,jsonb,jsonb,jsonb,uuid) to service_role;
grant select,insert on public.breeder_offline_receipts to service_role;

-- Deleting a herd must never cascade away animal/history/draft records.
-- The owner may remove an empty herd after explicit confirmation in the UI.
create function breeder_private.delete_empty_ring(p_ring uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare farm public.farms;begin
 select * into farm from public.farms where id=p_ring for update;
 if farm.id is null or not breeder_private.owns(farm.owner_id) or coalesce(farm.is_demo,false) then
  raise insufficient_privilege using message='Only the herd owner can delete an empty herd';end if;
 if exists(select 1 from public.animals where ring_id=p_ring)
 or exists(select 1 from public.pedigree_drafts where ring_id=p_ring)
 or exists(select 1 from public.global_pedigree_import_drafts where ring_id=p_ring)
 or exists(select 1 from public.global_pedigree_animals where ring_id=p_ring)
 or exists(select 1 from public.global_pedigree_history where ring_id=p_ring)
 or exists(select 1 from public.animal_sales where ring_id=p_ring) then
  raise exception 'This herd contains records. Move or retain those records before deleting the herd.';end if;
 delete from public.breeding_settings where ring_id=p_ring;
 delete from public.farms where id=p_ring;
 return p_ring;
end $$;
revoke all on function breeder_private.delete_empty_ring(uuid) from public,anon;
grant execute on function breeder_private.delete_empty_ring(uuid) to authenticated;
create function public.delete_empty_breeder_ring(p_ring uuid) returns uuid
language sql security invoker set search_path='' as $$select breeder_private.delete_empty_ring(p_ring)$$;
revoke all on function public.delete_empty_breeder_ring(uuid) from public,anon;
grant execute on function public.delete_empty_breeder_ring(uuid) to authenticated;
do $$declare definition text;begin
 definition=pg_get_functiondef('public.breeder_offline_apply(jsonb)'::regprocedure);
 definition=replace(definition,'''create_breeder_ring'',''record_breeding_with_parents''','''create_breeder_ring'',''delete_empty_breeder_ring'',''record_breeding_with_parents''');
 execute definition;
end $$;

create or replace function public.purge_account_data(p_user uuid) returns void
language plpgsql security invoker set search_path='' as $$
declare own text; ids uuid[]; breedings uuid[];
begin
 perform pg_advisory_xact_lock(hashtextextended(p_user::text,0));
 select owner_id into strict own from public.account_deletions where user_id=p_user;
 select coalesce(array_agg(a.id),'{}') into ids from public.animals a join public.farms f on f.id=a.ring_id where f.owner_id=own;
 select coalesce(array_agg(id),'{}') into breedings from public.breeding_records where sire_id=any(ids) and dam_id=any(ids);
 delete from public.breeding_offspring where breeding_id=any(breedings) or animal_id=any(ids);
 delete from public.breeding_tracking where breeding_id=any(breedings);
 delete from public.breeding_records where id=any(breedings);
 delete from public.pedigree_drafts where user_id=p_user or ring_id in(select id from public.farms where owner_id=own);
 delete from public.breeding_settings where ring_id in(select id from public.farms where owner_id=own);
 delete from public.connected_show_reports where owner_id=own;
 delete from public.breeder_show_history where owner_id=own;
 delete from public.breeder_imported_animals where owner_id=own;
 delete from public.breeder_exhibitor_profiles where owner_id=own;
 delete from public.show_connections where user_id=p_user;
 delete from public.animals where id=any(ids);
 delete from public.farms where owner_id=own;
 delete from public.user_licenses where user_id=own;
 delete from breeder_private.invitations where owner_id=own or member_user_id=p_user or email=(select lower(trim(email)) from public.users where auth_user_id=p_user);
 -- Keep the inactive profile until Auth deletes it through its foreign key.
 -- This prevents an interrupted deletion from recreating an empty profile.
end $$;

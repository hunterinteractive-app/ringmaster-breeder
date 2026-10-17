-- Resolve the caller's small family scope once per statement rather than
-- repeating an identity/invitation lookup for every historical record.
create function breeder_private.accessible_rings() returns setof uuid
language sql stable security definer set search_path='' as $$
 select f.id from public.farms f
 where (select auth.uid()) is not null and not coalesce(f.is_demo,false)
 and f.owner_id in (
  select u.id from public.users u
  where u.auth_user_id=(select auth.uid()) and u.is_active=true
  union
  select i.owner_id from breeder_private.invitations i
  join public.users u on u.id=i.owner_id and u.is_active=true
  where i.member_user_id=(select auth.uid())
   and i.accepted_at is not null and i.revoked_at is null
 );
$$;
revoke all on function breeder_private.accessible_rings() from public,anon;
grant execute on function breeder_private.accessible_rings() to authenticated;

alter policy family_animals on public.animals
 using (ring_id = any(array(select breeder_private.accessible_rings())))
 with check (ring_id = any(array(select breeder_private.accessible_rings())));

-- Subqueries are uncorrelated: Postgres can hash accessible animal IDs once.
-- The animals policy still enforces active owners, accepted members and no demos.
alter policy family_weights_read on public.animal_weights
 using (animal_id in (select id from public.animals));
alter policy family_health on public.animal_health_records
 using (animal_id in (select id from public.animals))
 with check (animal_id in (select id from public.animals));
alter policy family_breeding_read on public.breeding_records
 using (sire_id in (select id from public.animals)
    and dam_id in (select id from public.animals));

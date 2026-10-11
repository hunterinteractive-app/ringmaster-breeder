create table breeder_private.super_admins (
 user_id uuid primary key references auth.users(id) on delete cascade,
 granted_at timestamptz not null default now()
);
create table breeder_private.support_audit (
 id bigint generated always as identity primary key,
 actor_id uuid not null,
 target_owner_id text not null,
 action text not null,
 viewed_at timestamptz not null default now()
);
alter table breeder_private.super_admins enable row level security;
alter table breeder_private.support_audit enable row level security;
revoke all on breeder_private.super_admins,breeder_private.support_audit from public,anon,authenticated;
grant all on breeder_private.super_admins,breeder_private.support_audit to service_role;

create function public.breeder_is_super_admin() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
 select 1 from breeder_private.super_admins sa join auth.users au on au.id=sa.user_id
 join public.users u on u.auth_user_id=sa.user_id
 where sa.user_id=auth.uid() and u.is_active and au.email_confirmed_at is not null
 and au.deleted_at is null and (au.banned_until is null or au.banned_until<now()));
$$;
revoke all on function public.breeder_is_super_admin() from public,anon;
grant execute on function public.breeder_is_super_admin() to authenticated;

-- Deliberately read-only actions. Existing household RLS is not broadened.
create function public.breeder_support_view(p_action text,p_owner text default null,p_id uuid default null,p_query text default '',p_offset integer default 0) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; herd uuid;
begin
 if not public.breeder_is_super_admin() then raise exception 'Super-admin access required' using errcode='42501'; end if;
 if p_offset<0 or p_offset>100000 then raise exception 'Invalid page'; end if;
 if p_action='search' then
  select coalesce(jsonb_agg(to_jsonb(r)),'[]') into result from (
   select u.id,u.display_name,u.email,u.is_active,u.created_at,(select count(*) from public.farms f where f.owner_id=u.id) herd_count
   from public.users u where u.auth_user_id is not null and
   (p_query='' or position(lower(trim(p_query)) in lower(coalesce(u.email,'')||' '||coalesce(u.display_name,'')))>0)
   order by lower(coalesce(u.display_name,'')),u.id limit 50 offset p_offset
  ) r;
  return result;
 end if;
 if p_action not in ('account','animals','animal') then raise exception 'Unknown support action'; end if;
 if not exists(select 1 from public.users where id=p_owner) then raise exception 'Account not found'; end if;
 if p_action='account' then
  select jsonb_build_object('profile',jsonb_build_object('name',u.display_name,'email',u.email,'phone',u.phone,'address',u.address,'city',u.city,'state',u.state,'zip',u.zip,'active',u.is_active),
   'herds',(select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'name',f.name,'animals',(select count(*) from public.animals a where a.ring_id=f.id)) order by f.name),'[]') from public.farms f where f.owner_id=u.id),
   'subscriptions',(select coalesce(jsonb_agg(jsonb_build_object('plan',l.tier_code,'status',l.status,'expires',l.expires_at)),'[]') from public.user_licenses l where l.user_id=u.id),
   'connection',(select jsonb_build_object('herd_sync',c.enabled,'show_reports',c.reports_enabled,'last_sync',c.last_synced_at,'last_reports',c.last_reports_synced_at) from public.show_connections c where c.user_id=u.auth_user_id)) into result from public.users u where id=p_owner;
 elsif p_action='animals' then
  if not exists(select 1 from public.farms where id=p_id and owner_id=p_owner) then raise exception 'Herd does not belong to this account'; end if;
  select coalesce(jsonb_agg(to_jsonb(r)),'[]') into result from (
   select a.id,a.name,a.tattoo,a.species,a.breed,a.variety,a.sex,a.status,a.pedigree_only from public.animals a
   where a.ring_id=p_id and (p_query='' or position(lower(trim(p_query)) in lower(coalesce(a.name,'')||' '||coalesce(a.tattoo,'')||' '||coalesce(a.breed,'')))>0)
   order by lower(coalesce(a.name,a.tattoo,'')),a.id limit 50 offset p_offset
  ) r;
 else
  if not exists(select 1 from public.animals a join public.farms f on f.id=a.ring_id where a.id=p_id and f.owner_id=p_owner) then raise exception 'Animal does not belong to this account'; end if;
  select jsonb_build_object('animal',to_jsonb(a)-'photo_path'-'dedupe_hash',
   'sire',(select jsonb_build_object('name',s.name,'tattoo',s.tattoo) from public.animals s where s.id=a.sire_id),
   'dam',(select jsonb_build_object('name',d.name,'tattoo',d.tattoo) from public.animals d where d.id=a.dam_id),
   'weights',(select coalesce(jsonb_agg(to_jsonb(w)),'[]') from (select weight,recorded_at from public.animal_weights where animal_id=a.id order by recorded_at desc limit 100) w),
   'health',(select coalesce(jsonb_agg(to_jsonb(h)),'[]') from (select record_type,title,description,administered_date,medication,dosage,veterinarian from public.animal_health_records where animal_id=a.id order by administered_date desc limit 100) h)) into result from public.animals a where a.id=p_id;
 end if;
 insert into breeder_private.support_audit(actor_id,target_owner_id,action) values(auth.uid(),p_owner,p_action);
 return result;
end $$;
revoke all on function public.breeder_support_view(text,text,uuid,text,integer) from public,anon;
grant execute on function public.breeder_support_view(text,text,uuid,text,integer) to authenticated;

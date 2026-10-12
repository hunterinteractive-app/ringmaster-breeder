create table breeder_private.calendar_subscriptions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 ring_id uuid not null references public.farms(id) on delete cascade,
 token text not null unique,
 timezone text not null default 'UTC',
 created_at timestamptz not null default now(),
 unique(user_id,ring_id)
);
alter table breeder_private.calendar_subscriptions enable row level security;
revoke all on breeder_private.calendar_subscriptions from public,anon,authenticated;
grant all on breeder_private.calendar_subscriptions to service_role;

-- Each family member manages only their own subscription, not another device user's link.
create function public.manage_calendar_subscription(p_ring uuid,p_action text default 'status',p_timezone text default 'UTC') returns jsonb
language plpgsql security definer set search_path='' as $$
declare sub breeder_private.calendar_subscriptions;
begin
 if auth.uid() is null or not exists(select 1 from auth.users a join public.users u on u.auth_user_id=a.id where a.id=auth.uid() and u.is_active and a.email_confirmed_at is not null and a.deleted_at is null and (a.banned_until is null or a.banned_until<now()))
 or not exists(select 1 from public.farms f where f.id=p_ring and not coalesce(f.is_demo,false) and breeder_private.has_access(f.owner_id)) then raise exception 'Herd access denied' using errcode='42501'; end if;
 if p_action not in ('status','create','rotate','revoke') then raise exception 'Unknown action'; end if;
 if p_action in ('create','rotate') then
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_timezone) then raise exception 'Invalid timezone'; end if;
  insert into breeder_private.calendar_subscriptions(user_id,ring_id,token,timezone)
  values(auth.uid(),p_ring,encode(extensions.gen_random_bytes(32),'hex'),p_timezone)
  on conflict(user_id,ring_id) do update set token=case when p_action='rotate' then excluded.token else calendar_subscriptions.token end,
   timezone=excluded.timezone;
 elsif p_action='revoke' then
  delete from breeder_private.calendar_subscriptions where user_id=auth.uid() and ring_id=p_ring;
 end if;
 select * into sub from breeder_private.calendar_subscriptions where user_id=auth.uid() and ring_id=p_ring;
 return case when sub.id is null then jsonb_build_object('enabled',false) else jsonb_build_object('enabled',true,'token',sub.token,'timezone',sub.timezone) end;
end $$;
revoke all on function public.manage_calendar_subscription(uuid,text,text) from public,anon;
grant execute on function public.manage_calendar_subscription(uuid,text,text) to authenticated;

-- Device requests have a bearer link, never an app session. Recheck current access on every poll.
create function public.resolve_calendar_subscription(p_token text) returns jsonb
language sql security invoker set search_path='' as $$
 select jsonb_build_object('id',s.id,'ring_id',s.ring_id,'timezone',s.timezone,'name',f.name,'owner_id',f.owner_id,'owner_auth_id',o.auth_user_id)
 from breeder_private.calendar_subscriptions s
 join public.farms f on f.id=s.ring_id
 join public.users o on o.id=f.owner_id and o.is_active
 join auth.users a on a.id=s.user_id
 join public.users u on u.auth_user_id=a.id and u.is_active
 where s.token=p_token and not coalesce(f.is_demo,false)
 and a.email_confirmed_at is not null and a.deleted_at is null and (a.banned_until is null or a.banned_until<now())
 and (o.auth_user_id=s.user_id or exists(select 1 from breeder_private.invitations i where i.owner_id=f.owner_id and i.member_user_id=s.user_id and i.accepted_at is not null and i.revoked_at is null));
$$;
revoke all on function public.resolve_calendar_subscription(text) from public,anon,authenticated;
grant execute on function public.resolve_calendar_subscription(text) to service_role;

-- Annual USD catalogue; this configures entitlements, not payment collection.
alter table public.license_tiers
 add column annual_price_cents integer not null default 0 check(annual_price_cents>=0),
 add column currency text not null default 'USD' check(currency='USD'),
 add column max_active_animals integer not null default 0 check(max_active_animals>=0),
 add column buyer_pedigree_email boolean not null default false,
 add column custom_pedigree_branding boolean not null default false,
 add column saved_pedigree_layouts boolean not null default false;
update public.license_tiers set
 annual_price_cents=case code when 'HOBBY' then 4900 when 'PRO' then 9900 when 'TOP' then 17900 else 0 end,
 max_active_animals=case code when 'HOBBY' then 50 when 'PRO' then 250 when 'TOP' then 1000 else 0 end,
 max_rings=case code when 'TOP' then 5 when 'FREE' then 0 else 1 end,
 buyer_pedigree_email=code in ('PRO','TOP'),
 custom_pedigree_branding=code in ('PRO','TOP'),
 saved_pedigree_layouts=code in ('PRO','TOP')
where code in ('FREE','HOBBY','PRO','TOP');

-- One effective plan per owner, consistently used by server and client.
-- Multiple licenses do not add capacity or accidentally pick a newer lower plan.
create function breeder_private.effective_license(p_owner text) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce((select to_jsonb(t)||jsonb_build_object('active',true)
 from public.user_licenses l join public.license_tiers t on t.code=l.tier_code
 where l.user_id=p_owner and l.status='active'
 and (l.started_at is null or l.started_at<=now())
 and (l.expires_at is null or l.expires_at>now())
 order by t.max_active_animals desc,t.max_rings desc,t.annual_price_cents desc,l.id
 limit 1),jsonb_build_object('code','FREE','name','No active license','active',false,
 'max_rings',0,'max_active_animals',0,'annual_price_cents',0,'currency','USD',
 'buyer_pedigree_email',false,'custom_pedigree_branding',false,'saved_pedigree_layouts',false));
$$;
revoke all on function breeder_private.effective_license(text) from public,anon,authenticated;

-- A serialized counter prevents parallel imports/devices exceeding an expired
-- grace period. Clients can read their family's usage but never alter it.
create table public.breeder_license_usage (
 owner_id text primary key references public.users(id) on delete cascade,
 active_count integer not null default 0 check(active_count>=0),
 limit_reached_at timestamptz,
 updated_at timestamptz not null default now()
);
alter table public.breeder_license_usage enable row level security;
revoke all on public.breeder_license_usage from public,anon,authenticated;
grant select on public.breeder_license_usage to authenticated;
grant all on public.breeder_license_usage to service_role;
create policy family_usage_read on public.breeder_license_usage for select to authenticated
 using(breeder_private.has_access(owner_id));
create index animals_active_quota on public.animals(ring_id)
 where status='active' and not pedigree_only;
create index if not exists user_licenses_tier_lookup on public.user_licenses(tier_code);

create function breeder_private.adjust_animal_usage(p_owner text,p_delta integer) returns void
language plpgsql security definer set search_path='' as $$
declare usage public.breeder_license_usage; plan jsonb; cap integer; next_count integer;
begin
 insert into public.breeder_license_usage(owner_id) values(p_owner) on conflict do nothing;
 select * into strict usage from public.breeder_license_usage where owner_id=p_owner for update;
 plan=breeder_private.effective_license(p_owner);
 cap=(plan->>'max_active_animals')::integer;
 next_count=usage.active_count+p_delta;
 if p_delta>0 then
  if not (plan->>'active')::boolean or cap=0 then
   raise exception 'An active Breeder license is required to add active animals. Existing records remain available.' using errcode='P0001';
  end if;
  if usage.active_count>=cap and usage.limit_reached_at is not null
   and usage.limit_reached_at+interval '30 days'<=now() then
   raise exception 'Your 30-day animal-limit grace period has ended. Upgrade your plan or mark animals sold or deceased before adding active animals. Your existing records remain available.' using errcode='P0001';
  end if;
 end if;
 if next_count is distinct from usage.active_count or
  usage.limit_reached_at is distinct from (case when cap>0 and next_count>=cap then coalesce(usage.limit_reached_at,now()) else null end) then
  update public.breeder_license_usage set active_count=next_count,
   limit_reached_at=case when cap>0 and next_count>=cap
    then coalesce(usage.limit_reached_at,now()) else null end,updated_at=now()
  where owner_id=p_owner;
 end if;
end $$;
revoke all on function breeder_private.adjust_animal_usage(text,integer) from public,anon,authenticated;

create function breeder_private.animal_usage_changed() returns trigger
language plpgsql security definer set search_path='' as $$
declare old_owner text; new_owner text; own text;
begin
 if tg_op<>'INSERT' and old.status='active' and not old.pedigree_only then
  select owner_id into old_owner from public.farms where id=old.ring_id and not coalesce(is_demo,false);
 end if;
 if tg_op<>'DELETE' and new.status='active' and not new.pedigree_only then
  select owner_id into new_owner from public.farms where id=new.ring_id and not coalesce(is_demo,false);
 end if;
 if old_owner is not distinct from new_owner then return null; end if;
 -- Order owner locks when an animal moves between families.
 for own in select distinct x from unnest(array[old_owner,new_owner]) x where x is not null order by x loop
  perform breeder_private.adjust_animal_usage(own,case when own=new_owner then 1 else -1 end);
 end loop;
 return null;
end $$;
revoke all on function breeder_private.animal_usage_changed() from public,anon,authenticated;

create function breeder_private.license_usage_changed() returns trigger
language plpgsql security definer set search_path='' as $$
declare own text;
begin
 for own in select distinct x from unnest(array[
  case when tg_op<>'INSERT' then old.user_id end,
  case when tg_op<>'DELETE' then new.user_id end]) x where x is not null order by x loop
  perform breeder_private.adjust_animal_usage(own,0);
 end loop;
 return null;
end $$;
revoke all on function breeder_private.license_usage_changed() from public,anon,authenticated;

create function breeder_private.license_status(p_owner text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare plan jsonb; usage public.breeder_license_usage; cap integer; due timestamptz; rings integer;
begin
 if auth.uid() is null or not breeder_private.has_access(p_owner) then
  raise insufficient_privilege using message='Family access required';
 end if;
 perform breeder_private.adjust_animal_usage(p_owner,0);
 select * into strict usage from public.breeder_license_usage where owner_id=p_owner;
 plan=breeder_private.effective_license(p_owner);
 cap=(plan->>'max_active_animals')::integer;
 due=usage.limit_reached_at+interval '30 days';
 select count(*) into rings from public.farms where owner_id=p_owner and not coalesce(is_demo,false);
 return plan||jsonb_build_object('owner_id',p_owner,'active_count',usage.active_count,
  'current_rings',rings,'limit_reached_at',usage.limit_reached_at,'grace_ends_at',due,
  'growth_blocked',not (plan->>'active')::boolean or cap=0 or (usage.active_count>=cap and due<=now()),
  'warning_level',case when cap=0 then 0 when usage.active_count>=cap then 100
   when usage.active_count::bigint*100>=cap::bigint*95 then 95
   when usage.active_count::bigint*100>=cap::bigint*85 then 85
   when usage.active_count::bigint*100>=cap::bigint*75 then 75 else 0 end,
  'server_checked_at',now(),'provisional',false);
end $$;
revoke all on function breeder_private.license_status(text) from public,anon;
grant execute on function breeder_private.license_status(text) to authenticated;
create function public.breeder_license_status(p_owner text) returns jsonb
language sql security invoker set search_path='' as $$ select breeder_private.license_status(p_owner); $$;
revoke all on function public.breeder_license_status(text) from public,anon;
grant execute on function public.breeder_license_status(text) to authenticated;

-- Feature names are allowlisted. Branding/layouts are reserved entitlements;
-- there is no unfinished editor or save endpoint exposed by this migration.
create function breeder_private.require_feature(p_owner text,p_feature text) returns boolean
language plpgsql security definer set search_path='' as $$
declare plan jsonb;
begin
 if auth.uid() is null or not breeder_private.has_access(p_owner) then
  raise insufficient_privilege using message='Family access required';
 end if;
 if p_feature not in ('buyer_pedigree_email','custom_pedigree_branding','saved_pedigree_layouts') or p_feature is null then
  raise exception 'Unknown Breeder feature';
 end if;
 plan=breeder_private.effective_license(p_owner);
 if not coalesce((plan->>p_feature)::boolean,false) then
  raise insufficient_privilege using message='This feature requires Professional Breeder or Top Tier. Upgrade your plan to continue.';
 end if;
 return true;
end $$;
revoke all on function breeder_private.require_feature(text,text) from public,anon;
grant execute on function breeder_private.require_feature(text,text) to authenticated;
create function public.breeder_require_feature(p_owner text,p_feature text) returns boolean
language sql security invoker set search_path='' as $$ select breeder_private.require_feature(p_owner,p_feature); $$;
revoke all on function public.breeder_require_feature(text,text) from public,anon;
grant execute on function public.breeder_require_feature(text,text) to authenticated;

-- Keep the existing guarded creation path and deterministic offline IDs.
create or replace function breeder_private.create_ring(p_name text,p_owner_id text) returns uuid
language plpgsql security definer set search_path='' as $$
declare plan jsonb; v_id uuid;
begin
 perform breeder_private.ensure_identity();
 if not breeder_private.has_access(p_owner_id) then raise exception 'Family access required'; end if;
 if nullif(btrim(p_name),'') is null then raise exception 'Ring name required'; end if;
 perform 1 from public.users where id=p_owner_id for update;
 plan=breeder_private.effective_license(p_owner_id);
 if not (plan->>'active')::boolean or
  (select count(*) from public.farms where owner_id=p_owner_id and not coalesce(is_demo,false))>=(plan->>'max_rings')::integer
 then raise exception 'Ring limit reached'; end if;
 insert into public.farms(id,name,owner_id,is_demo) values(breeder_private.next_offline_id(),btrim(p_name),p_owner_id,false) returning id into v_id;
 return v_id;
end $$;

-- Atomic cutover: existing accounts at capacity receive a fresh 30 days.
lock table public.animals in share row exclusive mode;
insert into public.breeder_license_usage(owner_id,active_count)
 select u.id,count(a.id) from public.users u
 left join public.farms f on f.owner_id=u.id and not coalesce(f.is_demo,false)
 left join public.animals a on a.ring_id=f.id and a.status='active' and not a.pedigree_only group by u.id;
do $$ declare own text; begin
 for own in select owner_id from public.breeder_license_usage order by owner_id loop
  perform breeder_private.adjust_animal_usage(own,0);
 end loop;
end $$;
create trigger breeder_animal_usage after insert or update or delete on public.animals
 for each row execute function breeder_private.animal_usage_changed();
create trigger breeder_license_usage after insert or update or delete on public.user_licenses
 for each row execute function breeder_private.license_usage_changed();
-- Include authoritative usage/grace state in the existing private offline download.
insert into breeder_private.offline_versions(name) values('breeder_license_usage');
create trigger breeder_offline_changed after insert or update or delete on public.breeder_license_usage
 for each statement execute function breeder_private.offline_changed();

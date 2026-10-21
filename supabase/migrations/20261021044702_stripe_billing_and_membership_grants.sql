alter table public.user_licenses add column source text not null default 'legacy', add column billing_reference text unique;
create table public.breeder_billing_settings(id boolean primary key default true check(id), checkout_enabled boolean not null default false, stripe_account text not null default 'acct_1T85ZRLAhl5IBJ5k',portal_configuration text,webhook_id text);
insert into public.breeder_billing_settings(id) values(true);
create table public.breeder_billing_prices(id uuid primary key default gen_random_uuid(),tier_code text not null references public.license_tiers(code),interval text not null check(interval in ('month','year','lifetime')),amount_cents integer not null check(amount_cents>0),currency text not null default 'usd' check(currency='usd'),stripe_product text not null,stripe_price text not null unique,available boolean not null default true,created_at timestamptz not null default now(),check(tier_code in ('HOBBY','PRO','TOP')),check(interval<>'lifetime' or tier_code in ('PRO','TOP')));
create unique index breeder_current_price on public.breeder_billing_prices(tier_code,interval) where available and interval<>'lifetime';
create table public.breeder_billing_customers(id uuid primary key default gen_random_uuid(),owner_id text unique references public.users(id) on delete set null,stripe_customer text unique,manual_price_lock boolean not null default false);
create table public.breeder_early_adopter_rules(tier_code text primary key references public.license_tiers(code),quota integer not null default 0 check(quota>=0),enabled boolean not null default false);
insert into public.breeder_early_adopter_rules(tier_code) values('HOBBY'),('PRO'),('TOP');
create table public.breeder_billing_checkouts(id uuid primary key default gen_random_uuid(),owner_id text references public.users(id) on delete set null,offer_id uuid not null references public.breeder_billing_prices(id),stripe_session text unique,url text,state text not null default 'creating' check(state in ('creating','open','paid','expired')),early_reserved boolean not null default false,created_at timestamptz not null default now());
create unique index breeder_one_open_checkout on public.breeder_billing_checkouts(owner_id) where state in ('creating','open');
create index breeder_checkout_offer on public.breeder_billing_checkouts(offer_id);
create table public.breeder_billing_subscriptions(stripe_subscription text primary key,owner_id text references public.users(id) on delete set null,offer_id uuid not null references public.breeder_billing_prices(id),status text not null,paid_through timestamptz,period_end timestamptz,cancel_at_period_end boolean not null default false,price_locked boolean not null default false,lock_reason text,pending_offer_id uuid references public.breeder_billing_prices(id),schedule_id text,observed_at timestamptz not null default '-infinity',license_id uuid references public.user_licenses(id) on delete set null);
create index breeder_subscription_owner on public.breeder_billing_subscriptions(owner_id);
create table public.breeder_membership_grants(id uuid primary key default gen_random_uuid(),owner_id text references public.users(id) on delete set null,tier_code text not null references public.license_tiers(code) check(tier_code in ('PRO','TOP')),source text not null check(source in ('manual_lifetime','stripe_lifetime')),active boolean not null default true,note text not null,actor_id uuid,created_at timestamptz not null default now(),revoked_at timestamptz,stripe_session text unique,stripe_payment_intent text unique,license_id uuid references public.user_licenses(id) on delete set null);
create index breeder_grant_owner on public.breeder_membership_grants(owner_id);
create table public.breeder_lifetime_invitations(id uuid primary key default gen_random_uuid(),owner_id text references public.users(id) on delete set null,offer_id uuid not null references public.breeder_billing_prices(id),stripe_link text unique,url text,active boolean not null default true,paid_session text unique,created_at timestamptz not null default now());
create index breeder_invitation_owner on public.breeder_lifetime_invitations(owner_id);
create index breeder_invitation_offer on public.breeder_lifetime_invitations(offer_id);
create table public.breeder_billing_events(id text primary key,type text not null,processed_at timestamptz not null default now());
create table public.breeder_billing_audit(id bigint generated always as identity primary key,actor_id uuid,owner_id text,action text not null,details jsonb not null default '{}',created_at timestamptz not null default now());
do $$ declare n text; begin
 foreach n in array array['breeder_billing_settings','breeder_billing_prices','breeder_billing_customers','breeder_early_adopter_rules','breeder_billing_checkouts','breeder_billing_subscriptions','breeder_membership_grants','breeder_lifetime_invitations','breeder_billing_events','breeder_billing_audit'] loop
 execute format('alter table public.%I enable row level security',n);
 execute format('revoke all on public.%I from public,anon,authenticated',n);
 execute format('grant all on public.%I to service_role',n);
 end loop;
end $$;
grant usage,select on sequence public.breeder_billing_audit_id_seq to service_role;
-- Invoker privileges are service-only. The Edge Function verifies the actor.
create function public.breeder_billing_transaction(p_action text,p_data jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare o text=p_data->>'owner'; offer public.breeder_billing_prices;c public.breeder_billing_checkouts;s public.breeder_billing_subscriptions;g public.breeder_membership_grants;inv public.breeder_lifetime_invitations;r public.breeder_early_adopter_rules;lid uuid;locked boolean=false;n integer;through_date timestamptz;
begin
 perform pg_advisory_xact_lock(hashtextextended('billing:'||coalesce(o,''),0));
 if p_action='reserve' then
  if not exists(select 1 from public.users where id=o and is_active) or exists(select 1 from public.account_deletions where owner_id=o) then raise exception 'Account unavailable';end if;
  select * into strict offer from public.breeder_billing_prices where id=(p_data->>'offer')::uuid and available and interval<>'lifetime';
  if not (select checkout_enabled from public.breeder_billing_settings where id) then raise exception 'Checkout is not enabled';end if;
  if exists(select 1 from public.breeder_billing_subscriptions where owner_id=o and status not in ('canceled','incomplete_expired')) then raise exception 'Manage your existing subscription instead';end if;
  if exists(select 1 from public.breeder_membership_grants where owner_id=o and active) then raise exception 'Lifetime membership already active';end if;
  select * into c from public.breeder_billing_checkouts where owner_id=o and state in ('creating','open') for update;
  if found then
   if c.offer_id<>offer.id then raise exception 'Finish or cancel your open checkout first';end if;
   return to_jsonb(c);
  end if;
  select * into strict r from public.breeder_early_adopter_rules where tier_code=offer.tier_code for update;
  select count(*) into n from public.breeder_billing_checkouts b join public.breeder_billing_prices p on p.id=b.offer_id where p.tier_code=offer.tier_code and b.early_reserved and b.state<>'expired';
  locked=r.enabled and n<r.quota and not exists(select 1 from public.breeder_billing_checkouts b join public.breeder_billing_prices p on p.id=b.offer_id where b.owner_id=o and b.state='paid' and b.early_reserved and p.tier_code=offer.tier_code);
  insert into public.breeder_billing_checkouts(owner_id,offer_id,early_reserved) values(o,offer.id,locked) returning * into c;
  return to_jsonb(c);
 elsif p_action='subscription' then
  if not exists(select 1 from public.users where id=o and is_active) then return 'null';end if;
  select * into strict offer from public.breeder_billing_prices where stripe_price=p_data->>'price' and interval<>'lifetime';
  select * into s from public.breeder_billing_subscriptions where stripe_subscription=p_data->>'id' for update;
  if found and (s.owner_id is distinct from o or s.observed_at>=(p_data->>'observed_at')::timestamptz or (s.status='canceled' and p_data->>'status'<>'canceled')) then return to_jsonb(s);end if;
  through_date=(p_data->>'paid_through')::timestamptz;
  if s.paid_through is not null and (through_date is null or through_date<s.paid_through) then through_date=s.paid_through;end if;
  if s.stripe_subscription is null then
   select * into c from public.breeder_billing_checkouts where id=(p_data->>'checkout')::uuid and owner_id=o and offer_id=offer.id;
   if not found then raise exception 'Unrecognized checkout';end if;
   locked=c.early_reserved or coalesce((select manual_price_lock from public.breeder_billing_customers where owner_id=o),false);
   insert into public.breeder_billing_subscriptions(stripe_subscription,owner_id,offer_id,status,price_locked,lock_reason) values(p_data->>'id',o,offer.id,p_data->>'status',locked,case when locked then 'early_adopter' end) returning * into s;
  end if;
  if p_data->>'paid_through' is not null and (p_data->>'paid_through')::timestamptz>now() then
   lid=s.license_id;
   if lid is null then
    insert into public.user_licenses(user_id,tier_code,source,billing_reference,expires_at) values(o,offer.tier_code,'stripe_subscription',p_data->>'id',through_date) returning id into lid;
    update public.user_licenses set status='cancelled' where user_id=o and source='legacy' and id<>lid;
   else
    update public.user_licenses set tier_code=offer.tier_code,expires_at=through_date,status='active' where id=lid;
   end if;
   update public.breeder_billing_checkouts set state='paid' where id=(p_data->>'checkout')::uuid;
   update public.breeder_billing_customers set manual_price_lock=false where owner_id=o;
  end if;
  update public.breeder_billing_subscriptions set offer_id=case when p_data->>'paid_through' is not null then offer.id else offer_id end,status=p_data->>'status',paid_through=through_date,period_end=(p_data->>'period_end')::timestamptz,cancel_at_period_end=coalesce((p_data->>'cancel')::boolean,false),license_id=coalesce(lid,license_id),price_locked=case when p_data->>'status' in ('canceled','incomplete_expired') then false else price_locked end,pending_offer_id=case when pending_offer_id=offer.id then null else pending_offer_id end,observed_at=(p_data->>'observed_at')::timestamptz where stripe_subscription=p_data->>'id' returning * into s;
  return to_jsonb(s);
 elsif p_action in ('grant','lifetime_paid') then
  if not exists(select 1 from public.users where id=o and is_active) or exists(select 1 from public.account_deletions where owner_id=o) then raise exception 'Account unavailable';end if;
  if p_action='lifetime_paid' then
   select * into strict inv from public.breeder_lifetime_invitations where id=(p_data->>'invitation')::uuid and owner_id=o for update;
   if inv.paid_session is not null then return jsonb_build_object('duplicate',true);end if;
   select * into strict offer from public.breeder_billing_prices where id=inv.offer_id and interval='lifetime';
   if offer.stripe_price<>p_data->>'price' then raise exception 'Incorrect lifetime price';end if;
   update public.breeder_lifetime_invitations set paid_session=p_data->>'session',active=false where id=inv.id;
  end if;
  insert into public.breeder_membership_grants(owner_id,tier_code,source,note,actor_id,stripe_session,stripe_payment_intent) values(o,case when p_action='grant' then p_data->>'tier' else offer.tier_code end,case when p_action='grant' then 'manual_lifetime' else 'stripe_lifetime' end,coalesce(nullif(trim(p_data->>'note'),''),'Stripe lifetime purchase'),(p_data->>'actor')::uuid,p_data->>'session',p_data->>'payment_intent') returning * into g;
  insert into public.user_licenses(user_id,tier_code,source,billing_reference) values(o,g.tier_code,g.source,g.id::text) returning id into lid;
  update public.breeder_membership_grants set license_id=lid where id=g.id;
  update public.user_licenses set status='cancelled' where user_id=o and source='legacy';
  insert into public.breeder_billing_audit(actor_id,owner_id,action,details) values(g.actor_id,o,p_action,jsonb_build_object('grant',g.id,'tier',g.tier_code,'note',g.note));
  return to_jsonb(g);
 elsif p_action='revoke' then
  select * into strict g from public.breeder_membership_grants where id=(p_data->>'grant')::uuid and owner_id=o for update;
  update public.breeder_membership_grants set active=false,revoked_at=now() where id=g.id;
  update public.user_licenses set status='cancelled' where id=g.license_id;
  insert into public.breeder_billing_audit(actor_id,owner_id,action,details) values((p_data->>'actor')::uuid,o,'revoke_lifetime',jsonb_build_object('grant',g.id,'note',p_data->>'note'));
  return jsonb_build_object('revoked',true);
 end if;
 raise exception 'Unknown billing transaction';
end $$;
revoke all on function public.breeder_billing_transaction(text,jsonb) from public,anon,authenticated;
grant execute on function public.breeder_billing_transaction(text,jsonb) to service_role;
create table public.breeder_billing_leases(owner_id text primary key,token uuid not null,expires_at timestamptz not null);
alter table public.breeder_billing_leases enable row level security;
revoke all on public.breeder_billing_leases from public,anon,authenticated;
grant all on public.breeder_billing_leases to service_role;
create function public.breeder_billing_lease(p_owner text default null,p_token uuid default null,p_release boolean default false) returns void
language plpgsql security invoker set search_path='' as $$
begin
 if p_release then delete from public.breeder_billing_leases where token=p_token;return;end if;
 insert into public.breeder_billing_leases(owner_id,token,expires_at) values(p_owner,p_token,now()+interval '5 minutes')
 on conflict(owner_id) do update set token=excluded.token,expires_at=excluded.expires_at where public.breeder_billing_leases.expires_at<now();
 if not found then raise exception 'Another billing change is in progress. Please try again shortly.';end if;
end $$;
revoke all on function public.breeder_billing_lease(text,uuid,boolean) from public,anon,authenticated;
grant execute on function public.breeder_billing_lease(text,uuid,boolean) to service_role;
create function public.breeder_publish_price(p_previous uuid,p_price text,p_amount integer,p_actor uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare p public.breeder_billing_prices;r public.breeder_billing_prices;
begin
 select * into strict p from public.breeder_billing_prices where id=p_previous for update;
 select * into r from public.breeder_billing_prices where stripe_price=p_price;
 if found then return to_jsonb(r);end if;
 if not p.available then raise exception 'Catalogue changed. Refresh and retry.';end if;
 update public.breeder_billing_prices set available=false where id=p.id;
 insert into public.breeder_billing_prices(tier_code,interval,amount_cents,stripe_product,stripe_price) values(p.tier_code,p.interval,p_amount,p.stripe_product,p_price) returning * into r;
 insert into public.breeder_billing_audit(actor_id,action,details) values(p_actor,'publish_price',jsonb_build_object('previous',p.id,'offer',r.id,'notice_confirmed',true));
 return to_jsonb(r);
end $$;
revoke all on function public.breeder_publish_price(uuid,text,integer,uuid) from public,anon,authenticated;
grant execute on function public.breeder_publish_price(uuid,text,integer,uuid) to service_role;

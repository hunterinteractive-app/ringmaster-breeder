-- Service-only catalogue campaigns and durable recipient/email/scheduling history.
create table public.breeder_price_changes (
 id uuid primary key default gen_random_uuid(),
 previous_offer_id uuid not null references public.breeder_billing_prices(id),
 offer_id uuid not null unique references public.breeder_billing_prices(id),
 starts_at timestamptz not null,
 created_by uuid references auth.users(id) on delete set null,
 state text not null default 'scheduled' check(state in ('scheduled','active','superseded')),
 created_at timestamptz not null default now()
);
create table public.breeder_price_notices (
 id uuid primary key default gen_random_uuid(),
 change_id uuid not null references public.breeder_price_changes(id),
 stripe_subscription text not null references public.breeder_billing_subscriptions(stripe_subscription),
 owner_id text references public.users(id) on delete set null,
 old_offer_id uuid not null references public.breeder_billing_prices(id),
 effective_at timestamptz,
 recipient text,
 message text,
 email_accepted_at timestamptz,
 provider_id text,
 scheduled_at timestamptz,
 state text not null default 'queued' check(state in ('queued','complete','skipped','review')),
 attempts integer not null default 0,
 last_attempt_at timestamptz,
 retry_at timestamptz not null default now(),
 last_error text,
 created_at timestamptz not null default now(),
 unique(change_id,stripe_subscription)
);
create index breeder_price_notice_queue on public.breeder_price_notices(retry_at) where state='queued';
create index breeder_price_notice_owner on public.breeder_price_notices(owner_id);
create index breeder_price_notice_subscription on public.breeder_price_notices(stripe_subscription);
create index breeder_price_notice_old_offer on public.breeder_price_notices(old_offer_id);
create index breeder_price_change_previous on public.breeder_price_changes(previous_offer_id);
create index breeder_price_change_creator on public.breeder_price_changes(created_by);
alter table public.breeder_price_changes enable row level security;
alter table public.breeder_price_notices enable row level security;
revoke all on public.breeder_price_changes,public.breeder_price_notices from public,anon,authenticated;
grant all on public.breeder_price_changes,public.breeder_price_notices to service_role;
alter table public.breeder_billing_subscriptions add column pending_effective_at timestamptz;

-- Atomically reserve one pending change per tier/interval under the existing catalogue lease.
create function public.breeder_schedule_price(p_previous uuid,p_price text,p_amount integer,p_start timestamptz,p_actor uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare old public.breeder_billing_prices; offer public.breeder_billing_prices; campaign public.breeder_price_changes;
begin
 select * into strict old from public.breeder_billing_prices where id=p_previous for update;
 select c.* into campaign from public.breeder_price_changes c join public.breeder_billing_prices p on p.id=c.offer_id where p.stripe_price=p_price;
 if found then return to_jsonb(campaign); end if;
 if not old.available or old.interval='lifetime' then raise exception 'Catalogue changed. Refresh and retry.'; end if;
 if p_start < now()+interval '1 day' or p_start > now()+interval '2 years' then raise exception 'Choose a start date at least one day ahead and within two years.'; end if;
 if exists(select 1 from public.breeder_price_changes c join public.breeder_billing_prices p on p.id=c.offer_id where c.state='scheduled' and p.tier_code=old.tier_code and p.interval=old.interval) then raise exception 'This tier already has a scheduled change. Wait for activation before scheduling another.'; end if;
 insert into public.breeder_billing_prices(tier_code,interval,amount_cents,stripe_product,stripe_price,available) values(old.tier_code,old.interval,p_amount,old.stripe_product,p_price,false) returning * into offer;
 insert into public.breeder_price_changes(previous_offer_id,offer_id,starts_at,created_by) values(old.id,offer.id,p_start,p_actor) returning * into campaign;
 insert into public.breeder_billing_audit(actor_id,action,details) values(p_actor,'schedule_price',to_jsonb(campaign));
 return to_jsonb(campaign);
end $$;
create function public.breeder_price_tick() returns void language plpgsql security invoker set search_path='' as $$
declare c public.breeder_price_changes; offer public.breeder_billing_prices;
begin
 -- Also catches eligible customers joining the old price during the notice period.
 insert into public.breeder_price_notices(change_id,stripe_subscription,owner_id,old_offer_id)
 select c.id,s.stripe_subscription,s.owner_id,s.offer_id from public.breeder_price_changes c
 join public.breeder_billing_prices p on p.id=c.offer_id
 join public.breeder_billing_prices old on old.tier_code=p.tier_code and old.interval=p.interval and old.id<>p.id
 join public.breeder_billing_subscriptions s on s.offer_id=old.id
 where c.state in ('scheduled','active') and s.owner_id is not null and s.status='active' and not s.price_locked and not s.cancel_at_period_end
 and s.pending_offer_id is null
 and not exists(select 1 from public.breeder_membership_grants g where g.owner_id=s.owner_id and g.active)
 on conflict(change_id,stripe_subscription) do nothing;
 for c in select * from public.breeder_price_changes where state='scheduled' and starts_at<=now() for update skip locked loop
  select * into strict offer from public.breeder_billing_prices where id=c.offer_id;
  update public.breeder_billing_prices set available=false where tier_code=offer.tier_code and interval=offer.interval and available;
  update public.breeder_billing_prices set available=true where id=offer.id;
  update public.breeder_price_changes set state='superseded' where id<>c.id and state='active' and offer_id in(select id from public.breeder_billing_prices where tier_code=offer.tier_code and interval=offer.interval);
  update public.breeder_price_changes set state='active' where id=c.id;
 end loop;
end $$;
revoke all on function public.breeder_schedule_price(uuid,text,integer,timestamptz,uuid),public.breeder_price_tick() from public,anon,authenticated;
grant execute on function public.breeder_schedule_price(uuid,text,integer,timestamptz,uuid),public.breeder_price_tick() to service_role;

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
-- Generated in the database; never embedded in source, frontend, or cron text.
select vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'breeder_price_worker_token');
create function public.breeder_price_worker_authorized(p_token text) returns boolean
language sql security definer set search_path='' as $$
 select length(p_token)=64 and exists(select 1 from vault.decrypted_secrets where name='breeder_price_worker_token' and decrypted_secret=p_token)
$$;
revoke all on function public.breeder_price_worker_authorized(text) from public,anon,authenticated;
grant execute on function public.breeder_price_worker_authorized(text) to service_role;
select cron.schedule('breeder-price-notices','* * * * *', $job$
 select net.http_post(url:='https://aqfsrolvaewcpkdkttiz.supabase.co/functions/v1/billing-price-worker',headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',(select decrypted_secret from vault.decrypted_secrets where name='breeder_price_worker_token')),body:='{}'::jsonb,timeout_milliseconds:=60000);
$job$);

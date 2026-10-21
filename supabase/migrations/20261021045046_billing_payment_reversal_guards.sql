-- Serialize reversals with fulfillment so out-of-order refunds cannot create lifetime access.
create table public.breeder_billing_payment_blocks(stripe_payment_intent text primary key,reason text not null,created_at timestamptz not null default now());
alter table public.breeder_billing_payment_blocks enable row level security;
revoke all on public.breeder_billing_payment_blocks from public,anon,authenticated;
grant all on public.breeder_billing_payment_blocks to service_role;
create or replace function public.breeder_billing_transaction(p_action text,p_data jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare o text=p_data->>'owner'; offer public.breeder_billing_prices;c public.breeder_billing_checkouts;s public.breeder_billing_subscriptions;g public.breeder_membership_grants;inv public.breeder_lifetime_invitations;r public.breeder_early_adopter_rules;lid uuid;locked boolean=false;n integer;through_date timestamptz;
begin
 if p_action in ('lifetime_paid','block_payment') then
  perform pg_advisory_xact_lock(hashtextextended('payment:'||(p_data->>'payment_intent'),0));
 end if;
 if p_action='block_payment' then
  insert into public.breeder_billing_payment_blocks(stripe_payment_intent,reason) values(p_data->>'payment_intent',p_data->>'reason') on conflict do nothing;
  select * into g from public.breeder_membership_grants where stripe_payment_intent=p_data->>'payment_intent';
  if found then
   perform pg_advisory_xact_lock(hashtextextended('billing:'||coalesce(g.owner_id,''),0));
   update public.breeder_membership_grants set active=false,revoked_at=now() where id=g.id;
   update public.user_licenses set status='cancelled' where id=g.license_id;
  end if;
  return jsonb_build_object('blocked',true);
 end if;
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
   if exists(select 1 from public.breeder_billing_payment_blocks where stripe_payment_intent=p_data->>'payment_intent') then return jsonb_build_object('withheld',true);end if;
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

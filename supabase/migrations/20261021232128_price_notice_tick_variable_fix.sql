create or replace function public.breeder_price_tick() returns void language plpgsql security invoker set search_path='' as $$
declare campaign public.breeder_price_changes; offer public.breeder_billing_prices;
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
 for campaign in select * from public.breeder_price_changes where state='scheduled' and starts_at<=now() for update skip locked loop
  select * into strict offer from public.breeder_billing_prices where id=campaign.offer_id;
  update public.breeder_billing_prices set available=false where tier_code=offer.tier_code and interval=offer.interval and available;
  update public.breeder_billing_prices set available=true where id=offer.id;
  update public.breeder_price_changes set state='superseded' where id<>campaign.id and state='active' and offer_id in(select id from public.breeder_billing_prices where tier_code=offer.tier_code and interval=offer.interval);
  update public.breeder_price_changes set state='active' where id=campaign.id;
 end loop;
end $$;

create table public.animal_sales (
 id uuid primary key default gen_random_uuid(),
 animal_id uuid not null references public.animals(id) on delete restrict,
 ring_id uuid not null references public.farms(id) on delete restrict,
 animal_name text not null,
 status text not null default 'for_sale' check(status in ('for_sale','reserved','sold','cancelled')),
 asking_cents bigint check(asking_cents between 0 and 99999999999),
 sale_cents bigint check(sale_cents between 0 and 99999999999),
 currency text not null default 'USD' check(currency='USD'),
 buyer_name text not null default '', buyer_email text not null default '',
 buyer_phone text not null default '', buyer_address text not null default '',
 sale_date date, notes text not null default '',
 version integer not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index animal_sales_one_open on public.animal_sales(animal_id) where status in ('for_sale','reserved');
create index animal_sales_ring on public.animal_sales(ring_id,created_at desc);
create index animal_sales_animal on public.animal_sales(animal_id);
create table public.animal_sale_payments (
 id uuid primary key default gen_random_uuid(),
 sale_id uuid not null references public.animal_sales(id) on delete cascade,
 kind text not null check(kind in ('deposit','payment','refund')),
 amount_cents bigint not null check(amount_cents between 1 and 99999999999),
 paid_on date not null default current_date check(paid_on<=current_date),
 method text not null default '', reference text not null default '', notes text not null default '',
 created_by uuid not null default auth.uid(), created_at timestamptz not null default now()
);
create index animal_sale_payments_sale on public.animal_sale_payments(sale_id,created_at);
create table public.animal_sale_history (
 id uuid primary key default gen_random_uuid(),
 sale_id uuid not null references public.animal_sales(id) on delete cascade,
 event text not null, details jsonb not null,
 created_by uuid not null, created_at timestamptz not null default now()
);
create index animal_sale_history_sale on public.animal_sale_history(sale_id,created_at desc);
alter table public.animal_sales enable row level security;
alter table public.animal_sale_payments enable row level security;
alter table public.animal_sale_history enable row level security;
revoke all on public.animal_sales,public.animal_sale_payments,public.animal_sale_history from public,anon,authenticated;
grant select,insert,update on public.animal_sales to authenticated;
grant select,insert on public.animal_sale_payments to authenticated;
grant select on public.animal_sale_history to authenticated;
grant all on public.animal_sales,public.animal_sale_payments,public.animal_sale_history to service_role;
create policy sales_read on public.animal_sales for select to authenticated using(
 exists(select 1 from public.farms f where f.id=ring_id and not coalesce(f.is_demo,false) and breeder_private.has_access(f.owner_id)));
create policy sales_add on public.animal_sales for insert to authenticated with check(
 exists(select 1 from public.farms f where f.id=ring_id and not coalesce(f.is_demo,false) and breeder_private.has_access(f.owner_id)));
create policy sales_edit on public.animal_sales for update to authenticated using(
 exists(select 1 from public.farms f where f.id=ring_id and not coalesce(f.is_demo,false) and breeder_private.has_access(f.owner_id)))
 with check(exists(select 1 from public.farms f where f.id=ring_id and not coalesce(f.is_demo,false) and breeder_private.has_access(f.owner_id)));
create policy sale_payments_read on public.animal_sale_payments for select to authenticated using(exists(select 1 from public.animal_sales s where s.id=sale_id));
create policy sale_payments_add on public.animal_sale_payments for insert to authenticated with check(exists(select 1 from public.animal_sales s where s.id=sale_id));
create policy sale_history_read on public.animal_sale_history for select to authenticated using(exists(select 1 from public.animal_sales s where s.id=sale_id));

-- Private trigger functions write authoritative history while clients have read-only access.
create function breeder_private.sales_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare a public.animals; paid bigint; owner text;
begin
 select f.owner_id into owner from public.farms f where f.id=new.ring_id and not coalesce(f.is_demo,false);
 if auth.uid() is null or not coalesce(breeder_private.has_access(owner),false) then raise exception 'Sales access denied'; end if;
 if tg_op='INSERT' then
  select * into a from public.animals where id=new.animal_id for update;
  if a.id is null or a.ring_id<>new.ring_id or a.status<>'active' or coalesce(a.pedigree_only,false) then raise exception 'Choose an active herd animal'; end if;
  new.animal_name=concat_ws(' - ',nullif(a.name,''),nullif(a.tattoo,''));
  if new.animal_name='' then new.animal_name='Unnamed animal'; end if;
  new.version=1;new.created_at=now();
 else
  if new.id<>old.id or new.animal_id<>old.animal_id or new.ring_id<>old.ring_id or new.created_at<>old.created_at then raise exception 'Sale identity cannot change'; end if;
  new.animal_name=old.animal_name;
  if old.status='sold' and new.status<>'sold' then raise exception 'Completed sales remain in history'; end if;
  if old.status='cancelled' then raise exception 'Cancelled listings are read-only; create a new listing'; end if;
  new.version=old.version+1;
 end if;
 select coalesce(sum(case when kind='refund' then -amount_cents else amount_cents end),0) into paid from public.animal_sale_payments where sale_id=new.id;
 if paid>0 and (coalesce(new.sale_cents,new.asking_cents) is null or paid>coalesce(new.sale_cents,new.asking_cents)) then raise exception 'Price cannot be below payments received'; end if;
 if new.status='cancelled' and paid<>0 then raise exception 'Record refunds before cancelling this sale'; end if;
 if new.status in ('reserved','sold') and trim(new.buyer_name)='' then raise exception 'Enter the buyer name'; end if;
 if new.status='sold' and (new.sale_cents is null or new.sale_date is null or new.sale_date>current_date) then raise exception 'Enter a sale price and sale date that is not in the future'; end if;
 if length(new.buyer_name)>500 or length(new.buyer_email)>500 or length(new.buyer_phone)>100 or length(new.buyer_address)>2000 or length(new.notes)>10000 then raise exception 'Sale details are too long'; end if;
 new.updated_at=clock_timestamp();return new;
end $$;
create trigger sales_guard before insert or update on public.animal_sales for each row execute function breeder_private.sales_guard();
create function breeder_private.sales_audit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 insert into public.animal_sale_history(sale_id,event,details,created_by)
 values(new.id,case when tg_op='INSERT' then 'listed' else 'updated' end,
   jsonb_build_object('before',case when tg_op='UPDATE' then to_jsonb(old) else null end,'after',to_jsonb(new)),auth.uid());
 if new.status='sold' and (tg_op='INSERT' or old.status<>'sold') then
  update public.animals set status='sold' where id=new.animal_id;
 end if;
 return new;
end $$;
create trigger sales_audit after insert or update on public.animal_sales for each row execute function breeder_private.sales_audit();
create function breeder_private.sale_payment_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare s public.animal_sales; paid bigint; owner text;
begin
 select * into s from public.animal_sales where id=new.sale_id for update;
 select owner_id into owner from public.farms where id=s.ring_id and not coalesce(is_demo,false);
 if auth.uid() is null or not coalesce(breeder_private.has_access(owner),false) then raise exception 'Sales access denied'; end if;
 if s.status='cancelled' then raise exception 'This listing is cancelled'; end if;
 if new.paid_on>current_date then raise exception 'Payment date cannot be in the future'; end if;
 select coalesce(sum(case when kind='refund' then -amount_cents else amount_cents end),0) into paid from public.animal_sale_payments where sale_id=s.id;
 if new.kind='refund' then
  if new.amount_cents>paid then raise exception 'Refund exceeds payments received'; end if;
 else
  if coalesce(s.sale_cents,s.asking_cents) is null then raise exception 'Set a price before recording payments'; end if;
  if paid+new.amount_cents>coalesce(s.sale_cents,s.asking_cents) then raise exception 'Payment exceeds the balance due'; end if;
 end if;
 if length(new.method)>100 or length(new.reference)>500 or length(new.notes)>10000 then raise exception 'Payment details are too long'; end if;
 new.created_by=auth.uid();new.created_at=clock_timestamp();return new;
end $$;
create trigger sale_payment_guard before insert on public.animal_sale_payments for each row execute function breeder_private.sale_payment_guard();
create function breeder_private.sale_payment_audit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 insert into public.animal_sale_history(sale_id,event,details,created_by)
 values(new.sale_id,new.kind,to_jsonb(new),auth.uid());return new;
end $$;
create trigger sale_payment_audit after insert on public.animal_sale_payments for each row execute function breeder_private.sale_payment_audit();
create function breeder_private.sale_animal_guard() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if (new.ring_id<>old.ring_id or new.status<>'active' or new.pedigree_only) and exists(
 select 1 from public.animal_sales where animal_id=old.id and status in ('for_sale','reserved')) then
 raise exception 'Complete or cancel the open sale before changing this animal status or herd'; end if;
 return new;
end $$;
create trigger sale_animal_guard before update of status,ring_id,pedigree_only on public.animals for each row execute function breeder_private.sale_animal_guard();
revoke all on function breeder_private.sales_guard(),breeder_private.sales_audit(),breeder_private.sale_payment_guard(),breeder_private.sale_payment_audit(),breeder_private.sale_animal_guard() from public,anon,authenticated;

-- Keep verified account deletion able to remove private buyer/payment data.
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
 delete from public.animal_sales where ring_id in(select id from public.farms where owner_id=own);
 delete from public.animals where id=any(ids);
 delete from public.farms where owner_id=own;
 delete from public.user_licenses where user_id=own;
 delete from breeder_private.invitations where owner_id=own or member_user_id=p_user or email=(select lower(trim(email)) from public.users where auth_user_id=p_user);
 -- Keep the inactive profile until Auth deletes it through its foreign key.
 -- This prevents an interrupted deletion from recreating an empty profile.
end $$;

create or replace function breeder_private.sales_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare a public.animals; paid bigint; owner text;
begin
 select f.owner_id into owner from public.farms f where f.id=new.ring_id and not coalesce(f.is_demo,false);
 if auth.uid() is null or not coalesce(breeder_private.has_access(owner),false) then raise exception 'Sales access denied'; end if;
 if new.import_source is not null and (new.import_source<>'global_pedigree' or nullif(btrim(new.import_source_account),'') is null or nullif(btrim(new.import_source_id),'') is null or new.status<>'sold') then raise exception 'Invalid historical sale source'; end if;
 if tg_op='INSERT' then
  select * into a from public.animals where id=new.animal_id for update;
  if a.id is null or a.ring_id<>new.ring_id then raise exception 'Choose an animal in this herd'; end if;
  if new.import_source is null and (a.status<>'active' or coalesce(a.pedigree_only,false)) then raise exception 'Choose an active herd animal'; end if;
  if new.import_source is not null and not coalesce(breeder_private.owns(owner),false) then raise exception 'Only the herd owner can import historical sales'; end if;
  new.animal_name=concat_ws(' - ',nullif(a.name,''),nullif(a.tattoo,''));
  if new.animal_name='' then new.animal_name='Unnamed animal'; end if;
  new.version=1;new.created_at=now();
 else
  if new.id<>old.id or new.animal_id<>old.animal_id or new.ring_id<>old.ring_id or new.created_at<>old.created_at then raise exception 'Sale identity cannot change'; end if;
  if new.import_source is distinct from old.import_source or new.import_source_account is distinct from old.import_source_account or new.import_source_id is distinct from old.import_source_id or new.import_record is distinct from old.import_record then raise exception 'Imported sale identity cannot change'; end if;
  new.animal_name=old.animal_name;
  if old.status='sold' and new.status<>'sold' then raise exception 'Completed sales remain in history'; end if;
  if old.status='cancelled' then raise exception 'Cancelled listings are read-only; create a new listing'; end if;
  new.version=old.version+1;
 end if;
 select coalesce(sum(case when kind='refund' then -amount_cents else amount_cents end),0) into paid from public.animal_sale_payments where sale_id=new.id;
 if paid>0 and (coalesce(new.sale_cents,new.asking_cents) is null or paid>coalesce(new.sale_cents,new.asking_cents)) then raise exception 'Price cannot be below payments received'; end if;
 -- Only current listings participate; imported history and completed sales stay unchanged.
 if new.import_source is null and new.status in ('for_sale','reserved')
    and nullif(btrim(new.buyer_name),'') is not null then
  if new.sale_cents is not null and new.sale_cents>0 and paid=new.sale_cents then
   new.status='sold';
   new.sale_date=coalesce(new.sale_date,(select max(paid_on) from public.animal_sale_payments where sale_id=new.id),current_date);
  else
   new.status='reserved';
  end if;
 end if;
 if new.status='cancelled' and paid<>0 then raise exception 'Record refunds before cancelling this sale'; end if;
 if new.import_source is null and new.status in ('reserved','sold') and trim(new.buyer_name)='' then raise exception 'Enter the buyer name'; end if;
 if new.import_source is null and new.status='sold' and (new.sale_cents is null or new.sale_date is null or new.sale_date>current_date) then raise exception 'Enter a sale price and sale date that is not in the future'; end if;
 if length(new.buyer_name)>500 or length(new.buyer_email)>500 or length(new.buyer_phone)>100 or length(new.buyer_address)>2000 or length(new.notes)>10000 then raise exception 'Sale details are too long'; end if;
 if new.import_source is not null and new.sale_date>current_date then raise exception 'Historical sale date cannot be in the future'; end if;
 new.updated_at=clock_timestamp();return new;
end $$;

-- The payment guard already locks the sale row; reconcile within the same transaction.
create function breeder_private.sale_payment_status() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 update public.animal_sales set status=status
 where id=new.sale_id and import_source is null and status in ('for_sale','reserved')
 and nullif(btrim(buyer_name),'') is not null;
 return new;
end $$;
revoke all on function breeder_private.sale_payment_status() from public,anon,authenticated;
create trigger sale_payment_status after insert on public.animal_sale_payments
for each row execute function breeder_private.sale_payment_status();

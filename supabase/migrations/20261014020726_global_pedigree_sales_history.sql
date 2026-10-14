-- Historical sales retain missing values and source provenance without changing current herd membership.
alter table public.animal_sales add column import_source text;
alter table public.animal_sales add column import_source_account text;
alter table public.animal_sales add column import_source_id text;
alter table public.animal_sales add column import_record jsonb;
alter table public.animal_sales add column payment_history_complete boolean not null default true;
alter table public.animal_sales add constraint animal_sales_import_source_check check (
 (import_source is null and import_source_account is null and import_source_id is null and import_record is null)
 or (import_source='global_pedigree' and import_source_account is not null and length(import_source_account) between 1 and 200
 and import_source_id is not null and length(import_source_id) between 1 and 200 and import_record is not null
 and jsonb_typeof(import_record)='object' and octet_length(import_record::text)<=50000 and status='sold'));
create unique index animal_sales_import_identity on public.animal_sales(ring_id,import_source,import_source_account,import_source_id) where import_source is not null;
alter table public.global_pedigree_import_drafts add column sales_complete boolean not null default false;
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
 if new.status='cancelled' and paid<>0 then raise exception 'Record refunds before cancelling this sale'; end if;
 if new.import_source is null and new.status in ('reserved','sold') and trim(new.buyer_name)='' then raise exception 'Enter the buyer name'; end if;
 if new.import_source is null and new.status='sold' and (new.sale_cents is null or new.sale_date is null or new.sale_date>current_date) then raise exception 'Enter a sale price and sale date that is not in the future'; end if;
 if length(new.buyer_name)>500 or length(new.buyer_email)>500 or length(new.buyer_phone)>100 or length(new.buyer_address)>2000 or length(new.notes)>10000 then raise exception 'Sale details are too long'; end if;
 if new.import_source is not null and new.sale_date>current_date then raise exception 'Historical sale date cannot be in the future'; end if;
 new.updated_at=clock_timestamp();return new;
end $$;
create or replace function breeder_private.sales_audit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 insert into public.animal_sale_history(sale_id,event,details,created_by)
 values(new.id,case when tg_op='INSERT' and new.import_source is not null then 'imported' when tg_op='INSERT' then 'listed' else 'updated' end,
   jsonb_build_object('before',case when tg_op='UPDATE' then to_jsonb(old) else null end,'after',to_jsonb(new)),auth.uid());
 if new.import_source is null and new.status='sold' and (tg_op='INSERT' or old.status<>'sold') then
  update public.animals set status='sold' where id=new.animal_id;
 end if;
 return new;
end $$;
create function public.import_global_pedigree_with_sales(p_ring uuid,p_account text,p_animals jsonb,p_history jsonb default '[]',p_history_complete boolean default false,p_commit boolean default false,p_sales_complete boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare r jsonb; result jsonb; other_history jsonb; aid uuid; existing_sale public.animal_sales; added integer:=0; existing integer:=0; sales_count integer:=0; ids text[]:='{}'; dt date; amount bigint; issues jsonb:='[]'; warnings jsonb:='[]';
begin
 p_commit:=coalesce(p_commit,false);
 perform 1 from public.farms f where f.id=p_ring and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false) for update;
 if not found then raise exception 'Select a herd you own'; end if;
 if jsonb_typeof(p_history) is distinct from 'array' or jsonb_array_length(p_history)>20000 then raise exception 'Invalid history records'; end if;
 for r in select value from jsonb_array_elements(p_history) where value->>'kind'='sale' loop
  sales_count:=sales_count+1;
  if jsonb_typeof(r) is distinct from 'object' or octet_length(r::text)>50000 or length(coalesce(r->>'source_id','')) not between 1 and 200 then raise exception 'Invalid historical sale record'; end if;
  if (r->>'source_id')=any(ids) then raise exception 'Duplicate sale source ID'; end if; ids:=array_append(ids,r->>'source_id');
  if not exists(select 1 from jsonb_array_elements(p_animals) a where a->>'source_id'=r->>'animal_source_id') then raise exception 'Sale animal is missing'; end if;
  if r->>'sale_date' is not null then
   begin dt:=(r->>'sale_date')::date; exception when others then raise exception 'Invalid historical sale date'; end;
   if dt>current_date then issues:=issues||jsonb_build_array('Sale '||(r->>'source_id')||' has a future sale date. Correct the source before importing.'); end if;
  else warnings:=warnings||jsonb_build_array('Sale '||(r->>'source_id')||' has no usable sale date. Original source text is preserved.'); end if;
  if r->>'sale_cents' is not null then
   begin amount:=(r->>'sale_cents')::bigint; exception when others then raise exception 'Invalid historical sale amount'; end;
   if amount<0 or amount>99999999999 then raise exception 'Invalid historical sale amount'; end if;
  else warnings:=warnings||jsonb_build_array('Sale '||(r->>'source_id')||' has no recorded price.'); end if;
  if coalesce(r->>'currency','USD')<>'USD' then issues:=issues||jsonb_build_array('Sale '||(r->>'source_id')||' uses an unsupported currency.'); end if;
  if length(coalesce(r->>'buyer_name',''))>500 or length(coalesce(r->>'buyer_email',''))>500 or length(coalesce(r->>'buyer_phone',''))>100 or length(coalesce(r->>'buyer_address',''))>2000 or length(coalesce(r->>'notes',''))>10000 then raise exception 'Historical sale details are too long'; end if;
 end loop;
 select coalesce(jsonb_agg(value),'[]') into other_history from jsonb_array_elements(p_history) where value->>'kind' is distinct from 'sale';
 result:=public.import_global_pedigree_with_history(p_ring,p_account,p_animals,other_history,p_history_complete,p_commit and jsonb_array_length(issues)=0);
 if result->>'status'='preview' then
  update public.global_pedigree_import_drafts set history=p_history,sales_complete=coalesce(p_sales_complete,false) where auth_user_id=auth.uid() and ring_id=p_ring;
  result:=jsonb_set(result,'{issues}',coalesce(result->'issues','[]')||issues);
 else
  for r in select value from jsonb_array_elements(p_history) where value->>'kind'='sale' loop
   select * into existing_sale from public.animal_sales s where s.ring_id=p_ring and s.import_source='global_pedigree' and s.import_source_account=p_account and s.import_source_id=r->>'source_id';
   if found then existing:=existing+1;continue; end if;
   select g.animal_id into aid from public.global_pedigree_animals g where g.ring_id=p_ring and g.source_account=p_account and g.source_id=r->>'animal_source_id';
   if aid is null then raise exception 'Imported sale animal is missing'; end if;
   insert into public.animal_sales(animal_id,ring_id,animal_name,status,sale_cents,currency,buyer_name,buyer_email,buyer_phone,buyer_address,sale_date,notes,import_source,import_source_account,import_source_id,import_record,payment_history_complete)
   values(aid,p_ring,'','sold',nullif(r->>'sale_cents','')::bigint,'USD',coalesce(r->>'buyer_name',''),coalesce(r->>'buyer_email',''),coalesce(r->>'buyer_phone',''),coalesce(r->>'buyer_address',''),nullif(r->>'sale_date','')::date,coalesce(r->>'notes',''),'global_pedigree',p_account,r->>'source_id',r,false);
   added:=added+1;
  end loop;
  delete from public.global_pedigree_sales_source_previews where auth_user_id=auth.uid() and account=p_account;
 end if;
 return result||jsonb_build_object('sales_count',sales_count,'sales_added',added,'sales_existing',existing,'sales_complete',coalesce(p_sales_complete,false),'history_count',jsonb_array_length(p_history),'history_warnings',coalesce(result->'history_warnings','[]')||warnings);
end $$;
revoke all on function public.import_global_pedigree_with_sales(uuid,text,jsonb,jsonb,boolean,boolean,boolean) from public,anon;
grant execute on function public.import_global_pedigree_with_sales(uuid,text,jsonb,jsonb,boolean,boolean,boolean) to authenticated;

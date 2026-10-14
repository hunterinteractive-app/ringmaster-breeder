-- Synthetic fixtures only; all changes roll back.
begin;
do $$
declare u uuid=gen_random_uuid(); r uuid=gen_random_uuid(); a uuid=gen_random_uuid(); b uuid=gen_random_uuid(); s uuid; t uuid;
begin
 insert into auth.users(id,email,email_confirmed_at) values(u,u||'@example.invalid',now());
 insert into public.users(id,auth_user_id,username,email) values(u::text,u,u::text,u||'@example.invalid');
 insert into public.farms(id,name,owner_id) values(r,'Automatic sales test',u::text);
 insert into public.animals(id,ring_id,name,species,sex,status) values(a,r,'Automatic test A','rabbit','F','active'),(b,r,'Automatic test B','rabbit','F','active');
 perform set_config('request.jwt.claim.sub',u::text,true); execute 'set local role authenticated';
 insert into public.animal_sales(animal_id,ring_id,animal_name,asking_cents,sale_cents) values(a,r,'',10000,10000) returning id into s;
 update public.animal_sales set buyer_name='Synthetic Buyer' where id=s;
 if (select status from public.animal_sales where id=s)<>'reserved' then raise exception 'Buyer did not reserve'; end if;
 insert into public.animal_sale_payments(sale_id,kind,amount_cents) values(s,'deposit',2500);
 if (select status from public.animal_sales where id=s)<>'reserved' then raise exception 'Partial payment sold'; end if;
 insert into public.animal_sale_payments(sale_id,kind,amount_cents) values(s,'payment',7500);
 if not exists(select 1 from public.animal_sales where id=s and status='sold' and sale_date=current_date) then raise exception 'Full payment did not sell/date'; end if;
 if (select status from public.animals where id=a)<>'sold' then raise exception 'Animal not sold'; end if;
 insert into public.animal_sale_payments(sale_id,kind,amount_cents) values(s,'refund',1000);
 if (select status from public.animal_sales where id=s)<>'sold' then raise exception 'Refund reopened sale'; end if;
 insert into public.animal_sales(animal_id,ring_id,animal_name,asking_cents) values(b,r,'',10000) returning id into t;
 insert into public.animal_sale_payments(sale_id,kind,amount_cents) values(t,'payment',10000);
 if (select status from public.animal_sales where id=t)<>'for_sale' then raise exception 'Missing buyer/agreed sold'; end if;
 update public.animal_sales set buyer_name='Synthetic Buyer' where id=t;
 if (select status from public.animal_sales where id=t)<>'reserved' then raise exception 'Missing agreed sold'; end if;
 update public.animal_sales set sale_cents=10000 where id=t;
 if (select status from public.animal_sales where id=t)<>'sold' then raise exception 'Price edit did not reconcile'; end if;
 execute 'reset role';
end $$;
rollback;

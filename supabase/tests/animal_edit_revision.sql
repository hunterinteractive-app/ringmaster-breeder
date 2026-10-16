-- Synthetic fixtures only; verifies revision semantics and existing family RLS.
begin;
insert into auth.users(id,email,email_confirmed_at) values('e2000000-0000-4000-8000-000000000001','revision-owner@example.invalid',now());
insert into public.users(id,auth_user_id,username,email) values('revision-owner','e2000000-0000-4000-8000-000000000001','revision-owner','revision-owner@example.invalid');
insert into public.farms(id,name,owner_id) values('e2000000-0000-4000-8000-000000000010','Revision fixture','revision-owner');
select set_config('request.jwt.claim.sub','e2000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $$ declare animal uuid; n integer; begin
 insert into public.animals(ring_id,name,species,sex,revision) values('e2000000-0000-4000-8000-000000000010','Original','rabbit','Doe',9999) returning id into animal;
 if (select revision from public.animals where id=animal)<>1 then raise exception 'Forged initial revision accepted'; end if;
 update public.animals set name='First editor' where id=animal and revision=1;
 get diagnostics n=row_count;
 if n<>1 then raise exception 'First edit failed'; end if;
 update public.animals set name='Stale editor' where id=animal and revision=1;
 get diagnostics n=row_count;
 if n<>0 or (select name from public.animals where id=animal)<>'First editor' then raise exception 'Stale edit overwrote data'; end if;
 update public.animals set revision=9999 where id=animal and revision=2;
 if (select revision from public.animals where id=animal)<>3 then raise exception 'Revision was forged'; end if;
 perform set_config('request.jwt.claim.sub','e2000000-0000-4000-8000-000000000099',true);
 update public.animals set name='Outsider' where id=animal and revision=3;
 get diagnostics n=row_count;
 if n<>0 or exists(select 1 from public.animals where id=animal) then raise exception 'Revision update bypassed family isolation'; end if;
end $$;
reset role;
rollback;

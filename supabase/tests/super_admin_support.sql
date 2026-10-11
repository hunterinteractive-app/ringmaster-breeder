begin;
insert into auth.users(id,email,email_confirmed_at) values ('b0000000-0000-0000-0000-000000000001','support-admin@example.invalid',now()),('b0000000-0000-0000-0000-000000000002','support-target@example.invalid',now());
insert into public.users(id,username,email,auth_user_id) values ('support-admin-test','support-admin-test','support-admin@example.invalid','b0000000-0000-0000-0000-000000000001'),('support-target-test','support-target-test','support-target@example.invalid','b0000000-0000-0000-0000-000000000002');
insert into breeder_private.super_admins(user_id) values('b0000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-0000-0000-000000000002',true);
do $$ begin
 if public.breeder_is_super_admin() then raise exception 'Ordinary user elevated'; end if;
 begin
  perform public.breeder_support_view('account','support-admin-test');
  raise exception 'Ordinary user was allowed';
 exception when insufficient_privilege then null;
 end;
 begin
  insert into breeder_private.super_admins(user_id) values(auth.uid());
  raise exception 'Self elevation allowed';
 exception when insufficient_privilege then null;
 end;
end $$;
select set_config('request.jwt.claim.sub','b0000000-0000-0000-0000-000000000001',true);
do $$ begin
 if not public.breeder_is_super_admin() then raise exception 'Admin denied'; end if;
 if (public.breeder_support_view('account','support-target-test')->'profile'->>'email')<>'support-target@example.invalid' then raise exception 'Wrong account snapshot'; end if;
 if jsonb_array_length(public.breeder_support_view('search',p_query=>'support-target@example.invalid'))<>1 then raise exception 'Search failed'; end if;
 if exists(select 1 from public.users where id='support-target-test') then raise exception 'Ordinary RLS was broadened'; end if;
end $$;
reset role;
do $$ begin
 if not exists(select 1 from breeder_private.support_audit where actor_id='b0000000-0000-0000-0000-000000000001' and target_owner_id='support-target-test') then raise exception 'Audit missing'; end if;
end $$;
delete from breeder_private.super_admins where user_id='b0000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$ begin
 if public.breeder_is_super_admin() then raise exception 'Revoked admin still allowed'; end if;
 begin
  perform public.breeder_support_view('search');
  raise exception 'Revoked admin allowed';
 exception when insufficient_privilege then null;
 end;
end $$;
rollback;

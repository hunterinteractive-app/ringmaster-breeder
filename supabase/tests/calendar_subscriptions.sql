begin;
insert into auth.users(id,email,email_confirmed_at) values ('b1000000-0000-0000-0000-000000000001','calendar-test@example.invalid',now());
insert into public.users(id,username,email,auth_user_id) values ('calendar-test','calendar-test','calendar-test@example.invalid','b1000000-0000-0000-0000-000000000001');
insert into public.farms(id,name,owner_id) values('b1000000-0000-0000-0000-000000000002','Calendar test','calendar-test');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
do $$ declare a jsonb; b jsonb; begin
a:=public.manage_calendar_subscription('b1000000-0000-0000-0000-000000000002','create','America/Indiana/Indianapolis');
b:=public.manage_calendar_subscription('b1000000-0000-0000-0000-000000000002','create','America/Indiana/Indianapolis');
if a->>'token'<>b->>'token' then raise exception 'Create not idempotent'; end if;
if public.resolve_calendar_subscription(a->>'token') is null then raise exception 'Valid link denied'; end if;
b:=public.manage_calendar_subscription('b1000000-0000-0000-0000-000000000002','rotate','UTC');
if a->>'token'=b->>'token' or public.resolve_calendar_subscription(a->>'token') is not null then raise exception 'Rotate failed'; end if;
update public.users set is_active=false where id='calendar-test';
if public.resolve_calendar_subscription(b->>'token') is not null then raise exception 'Inactive subscriber allowed'; end if;
update public.users set is_active=true where id='calendar-test';
perform public.manage_calendar_subscription('b1000000-0000-0000-0000-000000000002','revoke');
if public.resolve_calendar_subscription(b->>'token') is not null then raise exception 'Revoke failed'; end if;
end $$;
set local role authenticated;
do $$ begin
begin perform public.resolve_calendar_subscription('x'); raise exception 'Client resolve allowed'; exception when insufficient_privilege then null; end;
begin perform token from breeder_private.calendar_subscriptions; raise exception 'Client token read allowed'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
do $$ begin
begin perform public.manage_calendar_subscription('b1000000-0000-0000-0000-000000000002','create'); raise exception 'Stranger allowed'; exception when insufficient_privilege then null; end;
end $$;
rollback;
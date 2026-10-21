begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAILED: %',label;end if;end$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('e6102121-0000-4000-8000-000000000201','registration-one@example.test',now()),
 ('e6102121-0000-4000-8000-000000000202','registration-two@example.test',now()),
 ('e6102121-0000-4000-8000-000000000203','registration-three@example.test',now());
insert into public.users(id,username,email,auth_user_id,created_at) values
 ('registration-one','regone','registration-one@example.test','e6102121-0000-4000-8000-000000000201',now()-interval '1 year'),
 ('registration-two','regtwo','registration-two@example.test','e6102121-0000-4000-8000-000000000202',now()),
 ('registration-three','regthree','registration-three@example.test','e6102121-0000-4000-8000-000000000203',now());
select set_config('request.jwt.claims','{"sub":"e6102121-0000-4000-8000-000000000201","role":"authenticated"}',true);
create temp table referrer as select public.breeder_registration_feedback() data;
select pg_temp.ok(not (select (data->>'show_onboarding')::boolean from referrer),'existing member not interrupted');
select set_config('request.jwt.claims','{"sub":"e6102121-0000-4000-8000-000000000202","role":"authenticated"}',true);
select pg_temp.ok((public.breeder_registration_feedback()->>'show_onboarding')::boolean,'new registration offered optional questions');
select public.breeder_registration_feedback('save',jsonb_build_object('herd_tracking','Paper records','referred_by',(select data->>'referral_code' from referrer),'requested_features','Health reminders','owner_id','registration-one'));
select pg_temp.ok((select herd_tracking='Paper records' and referrer_owner_id='registration-one' from public.breeder_registration_feedback where owner_id='registration-two'),'answers belong to actor and referral linked');
select pg_temp.ok(not (public.breeder_registration_feedback()->>'show_onboarding')::boolean,'saved registration not prompted repeatedly');
do $$begin
 begin perform public.breeder_registration_feedback('save','{"referred_by":"someone else"}');raise exception 'changed referral';exception when others then if sqlerrm='changed referral' then raise;end if;end;
 begin perform public.breeder_registration_feedback('save',jsonb_build_object('requested_features',repeat('x',4001)));raise exception 'oversize accepted';exception when others then if sqlerrm='oversize accepted' then raise;end if;end;
end$$;
select set_config('request.jwt.claims','{"sub":"e6102121-0000-4000-8000-000000000201","role":"authenticated"}',true);
select pg_temp.ok((public.breeder_registration_feedback()->>'referred_signups')::int=1,'referrer sees signup count');
select pg_temp.ok((public.breeder_registration_feedback()->>'herd_tracking')='','request owner cannot overwrite another member');
select set_config('request.jwt.claims','{"sub":"e6102121-0000-4000-8000-000000000203","role":"authenticated"}',true);
select public.breeder_registration_feedback('save',jsonb_build_object('referred_by',public.breeder_registration_feedback()->>'referral_code'));
select pg_temp.ok((select referrer_owner_id is null from public.breeder_registration_feedback where owner_id='registration-three'),'self referral never counted');
set local role authenticated;
do $$begin
 begin perform * from public.breeder_registration_feedback;raise exception 'read another member response';exception when insufficient_privilege then null;end;
 begin perform public.breeder_registration_feedback('admin-list');raise exception 'nonadmin listed responses';exception when others then if sqlerrm='nonadmin listed responses' then raise;end if;end;
end$$;
reset role;
insert into breeder_private.super_admins(user_id) values('e6102121-0000-4000-8000-000000000201');
select set_config('request.jwt.claims','{"sub":"e6102121-0000-4000-8000-000000000201","role":"authenticated"}',true);
select pg_temp.ok(jsonb_array_length(public.breeder_registration_feedback('admin-list')->'responses')>=2,'admin can review saved answers');
set local role anon;
do $$begin
 begin perform public.breeder_registration_feedback();raise exception 'anonymous read';exception when insufficient_privilege then null;end;
end$$;
reset role;
select 'registration feedback checks passed' as result;
rollback;

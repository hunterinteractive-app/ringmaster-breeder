begin;
insert into auth.users (id, aud, role, email) values
 ('aaaaaaaa-0000-0000-0000-000000000001','authenticated','authenticated','policy-test@example.invalid'),
 ('aaaaaaaa-0000-0000-0000-000000000002','authenticated','authenticated','policy-other@example.invalid');
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',true);
insert into public.breeder_legal_acceptances(user_id,terms_version,privacy_version)
 values ('aaaaaaaa-0000-0000-0000-000000000001','2026-10','2026-10');
do $$ begin
 if not exists(select 1 from public.breeder_legal_acceptances where accepted_at is not null) then raise exception 'own acceptance missing'; end if;
 if exists(select 1 from public.breeder_legal_acceptances where terms_version='future') then raise exception 'wrong version accepted'; end if;
 begin
  insert into public.breeder_legal_acceptances(user_id,terms_version,privacy_version)
   values ('aaaaaaaa-0000-0000-0000-000000000002','2026-10','2026-10');
  raise exception 'cross user insert allowed';
 exception when insufficient_privilege then null; end;
 begin
  update public.breeder_legal_acceptances set accepted_at=now();
  raise exception 'updates allowed';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000002',true);
do $$ begin if exists(select 1 from public.breeder_legal_acceptances) then raise exception 'cross user read allowed'; end if; end $$;
reset role;
rollback;

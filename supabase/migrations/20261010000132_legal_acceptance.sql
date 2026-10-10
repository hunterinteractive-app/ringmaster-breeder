create table public.breeder_legal_acceptances (
  user_id uuid not null references auth.users(id) on delete cascade,
  terms_version text not null,
  privacy_version text not null,
  accepted_at timestamptz not null default now(),
  primary key (user_id, terms_version, privacy_version)
);
alter table public.breeder_legal_acceptances enable row level security;
revoke all on public.breeder_legal_acceptances from anon, authenticated;
grant select on public.breeder_legal_acceptances to authenticated;
grant insert (user_id, terms_version, privacy_version) on public.breeder_legal_acceptances to authenticated;
grant all on public.breeder_legal_acceptances to service_role;
create policy own_acceptance_read on public.breeder_legal_acceptances
  for select to authenticated using ((select auth.uid()) = user_id);
create policy own_acceptance_insert on public.breeder_legal_acceptances
  for insert to authenticated with check ((select auth.uid()) = user_id);

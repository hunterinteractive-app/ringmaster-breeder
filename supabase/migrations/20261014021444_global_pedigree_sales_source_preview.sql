-- Temporary authenticated source inspection; never contains login/session data.
create table public.global_pedigree_sales_source_previews (
 auth_user_id uuid primary key references auth.users(id) on delete cascade,
 account text not null check(length(account)<=200),
 page jsonb not null check(jsonb_typeof(page)='object' and octet_length(page::text)<=2000000),
 collected_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '24 hours'
);
alter table public.global_pedigree_sales_source_previews enable row level security;
revoke all on public.global_pedigree_sales_source_previews from public,anon,authenticated;
grant select,insert,update,delete on public.global_pedigree_sales_source_previews to authenticated;
create policy own_sales_source_preview on public.global_pedigree_sales_source_previews for all to authenticated
 using(auth_user_id=(select auth.uid())) with check(auth_user_id=(select auth.uid()));

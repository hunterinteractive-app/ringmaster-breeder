create table public.show_connections (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null unique references auth.users(id) on delete cascade,
 show_user_id uuid not null unique,
 enabled boolean not null default false,
 herd_ids uuid[] not null default '{}',
 updated_at timestamptz not null default clock_timestamp(),
 last_synced_at timestamptz,
 last_error text
);
alter table public.show_connections enable row level security;
revoke all on public.show_connections from anon,authenticated;
grant select on public.show_connections to authenticated;
create policy own_show_connection on public.show_connections for select to authenticated using(user_id=(select auth.uid()));
-- Connection mutations are performed only by the verified server bridge.
grant all on public.show_connections to service_role;

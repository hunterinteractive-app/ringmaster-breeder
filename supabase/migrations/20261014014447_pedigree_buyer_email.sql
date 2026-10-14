-- Draft/export and send state are server-only; no mail credentials reach clients.
create table public.pedigree_buyer_emails (
 id uuid primary key,
 actor_id uuid not null references auth.users(id) on delete cascade,
 animal_id uuid not null references public.animals(id) on delete cascade,
 sale_id uuid references public.animal_sales(id) on delete cascade,
 export_json jsonb not null,
 owner_name text not null, owner_email text not null,
 suggested_recipient text not null default '',
 recipient text, payload_hash text,
 status text not null default 'draft' check(status in ('draft','pending','accepted')),
 provider_id text, created_at timestamptz not null default now(), accepted_at timestamptz,
 check((status='draft') or (recipient is not null and payload_hash is not null))
);
create index pedigree_buyer_emails_actor on public.pedigree_buyer_emails(actor_id,created_at desc);
create index pedigree_buyer_emails_animal on public.pedigree_buyer_emails(animal_id);
create index pedigree_buyer_emails_sale on public.pedigree_buyer_emails(sale_id);
alter table public.pedigree_buyer_emails enable row level security;
revoke all on public.pedigree_buyer_emails from public,anon,authenticated;
grant all on public.pedigree_buyer_emails to service_role;
create unique index sale_pedigree_email_audit_once on public.animal_sale_history ((details->>'email_request_id')) where event='pedigree_email_accepted';

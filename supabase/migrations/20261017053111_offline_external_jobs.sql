create table public.breeder_offline_jobs (
 id uuid primary key,
 actor uuid not null references auth.users(id) on delete cascade,
 target text not null check(target in ('email-buyer-pedigree','global-pedigree','global-pedigree-import','import-ringmaster-records','show-reports','show-calendar','show-connection','sync-breed-catalog')),
 payload jsonb not null,
 payload_hash text not null,
 state text not null default 'queued' check(state in ('queued','running','needs_input','review','complete','failed','cancelled')),
 result jsonb,
 error text,
 created_at timestamptz not null default now(),
 started_at timestamptz,
 completed_at timestamptz
);
alter table public.breeder_offline_jobs enable row level security;
revoke all on public.breeder_offline_jobs from public,anon,authenticated;
grant select on public.breeder_offline_jobs to authenticated;
grant all on public.breeder_offline_jobs to service_role;
create policy own_offline_jobs on public.breeder_offline_jobs for select to authenticated using(actor=(select auth.uid()));
create index breeder_offline_jobs_actor_created on public.breeder_offline_jobs(actor,created_at desc);

create function breeder_private.offline_job_account_guard() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 perform pg_advisory_xact_lock(hashtextextended(new.actor::text,0));
 if new.state in ('queued','running') and exists(select 1 from public.account_deletions where user_id=new.actor) then
  raise exception 'Account deletion is pending. This outside-service request was not started.';
 end if;
 return new;
end $$;
revoke all on function breeder_private.offline_job_account_guard() from public,anon,authenticated;
create trigger offline_job_account_guard before insert or update of state on public.breeder_offline_jobs
for each row execute function breeder_private.offline_job_account_guard();

create function breeder_private.offline_result_deletion_manifest() returns trigger
language plpgsql security definer set search_path='' as $$ declare files jsonb;begin
 if exists(select 1 from public.breeder_offline_jobs where actor=new.user_id and state in ('queued','running')) then
  raise exception 'Wait for running requests or cancel queued requests in Sync before deleting this account.';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket_id,'name',name)),'[]') into files from storage.objects
 where bucket_id='offline_results' and split_part(name,'/',1)=new.user_id::text;
 new.files=coalesce(new.files,'[]')||files;
 return new;
end $$;
revoke all on function breeder_private.offline_result_deletion_manifest() from public,anon,authenticated;
create trigger offline_result_deletion_manifest before insert on public.account_deletions
for each row execute function breeder_private.offline_result_deletion_manifest();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('offline_results','offline_results',false,10485760,array['application/pdf','application/json'])
on conflict(id) do nothing;
create policy own_offline_result_read on storage.objects for select to authenticated
 using(bucket_id='offline_results' and split_part(name,'/',1)=(select auth.uid())::text);

-- Reports and connection metadata join the authorized record download.
do $$ declare t text;begin
 foreach t in array array['connected_show_reports','show_connections','breeder_offline_jobs'] loop
  insert into breeder_private.offline_versions(name) values(t);
  execute format('create trigger breeder_offline_changed after insert or update or delete on public.%I for each statement execute function breeder_private.offline_changed()',t);
 end loop;
end $$;
-- Include the new private result bucket in the file manifest, under its RLS.
do $$ declare definition text;begin
 definition=pg_get_functiondef('public.breeder_offline_snapshot(jsonb)'::regprocedure);
 definition=replace(definition,'''animal_photos'',''health_attachments''','''animal_photos'',''health_attachments'',''offline_results''');
 execute definition;
end $$;

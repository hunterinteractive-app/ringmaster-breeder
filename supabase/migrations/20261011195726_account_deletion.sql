-- Only the verified server can start or carry out deletion. The row survives
-- partial failures so the same signed-in user can resume without losing scope.
create table public.account_deletions (
 user_id uuid primary key references auth.users(id) on delete cascade,
 owner_id text not null,
 started_at timestamptz not null default now(),
 connection jsonb,
 files jsonb not null default '[]'
);
alter table public.account_deletions enable row level security;
revoke all on public.account_deletions from anon,authenticated;
grant select on public.account_deletions to authenticated;
grant all on public.account_deletions to service_role;
create policy own_deletion on public.account_deletions for select to authenticated using(user_id=(select auth.uid()));
alter table public.users drop constraint users_auth_user_id_fkey;
alter table public.users add constraint users_auth_user_id_fkey foreign key(auth_user_id) references auth.users(id) on delete cascade;

create function public.begin_account_deletion(p_user uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare own text; animals uuid[]; job public.account_deletions; files jsonb;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_user::text,0));
 select * into job from public.account_deletions where user_id=p_user;
 if found then return to_jsonb(job); end if;
 select id into strict own from public.users where auth_user_id=p_user for update;
 select coalesce(array_agg(a.id),'{}') into animals from public.animals a join public.farms f on f.id=a.ring_id where f.owner_id=own;
 -- Do not silently alter another household's pedigree or breeding records.
 if exists(select 1 from public.animals a where not(a.id=any(animals)) and (a.sire_id=any(animals) or a.dam_id=any(animals)))
 or exists(select 1 from public.breeder_imported_animals where owner_id<>own and animal_id=any(animals))
 or exists(select 1 from public.breeder_show_history where owner_id<>own and animal_id=any(animals))
 or exists(select 1 from public.breeding_records where (sire_id=any(animals))<>(dam_id=any(animals)))
 or exists(select 1 from storage.objects where owner_id=p_user::text and not(bucket_id in ('animal_photos','health_attachments') and split_part(name,'/',1)=any(animals::text[])))
 then raise exception 'ACCOUNT_SHARED_DATA_REVIEW'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket_id,'name',name)),'[]') into files from storage.objects
 where bucket_id in ('animal_photos','health_attachments') and split_part(name,'/',1)=any(animals::text[]);
 insert into public.account_deletions(user_id,owner_id,connection,files)
 values(p_user,own,(select to_jsonb(c) from public.show_connections c where user_id=p_user),files) returning * into job;
 update public.users set is_active=false where id=own;
 -- Stop other family members and this user's existing sessions writing data.
 update breeder_private.invitations set revoked_at=now() where owner_id=own or member_user_id=p_user;
 update public.show_connections set enabled=false,reports_enabled=false,herd_ids='{}',updated_at=clock_timestamp(),reports_changed_at=clock_timestamp() where user_id=p_user;
 return to_jsonb(job);
end $$;

create function public.purge_account_data(p_user uuid) returns void
language plpgsql security invoker set search_path='' as $$
declare own text; ids uuid[]; breedings uuid[];
begin
 perform pg_advisory_xact_lock(hashtextextended(p_user::text,0));
 select owner_id into strict own from public.account_deletions where user_id=p_user;
 select coalesce(array_agg(a.id),'{}') into ids from public.animals a join public.farms f on f.id=a.ring_id where f.owner_id=own;
 select coalesce(array_agg(id),'{}') into breedings from public.breeding_records where sire_id=any(ids) and dam_id=any(ids);
 delete from public.breeding_offspring where breeding_id=any(breedings) or animal_id=any(ids);
 delete from public.breeding_tracking where breeding_id=any(breedings);
 delete from public.breeding_records where id=any(breedings);
 delete from public.pedigree_drafts where user_id=p_user or ring_id in(select id from public.farms where owner_id=own);
 delete from public.breeding_settings where ring_id in(select id from public.farms where owner_id=own);
 delete from public.connected_show_reports where owner_id=own;
 delete from public.breeder_show_history where owner_id=own;
 delete from public.breeder_imported_animals where owner_id=own;
 delete from public.breeder_exhibitor_profiles where owner_id=own;
 delete from public.show_connections where user_id=p_user;
 delete from public.animals where id=any(ids);
 delete from public.farms where owner_id=own;
 delete from public.user_licenses where user_id=own;
 delete from breeder_private.invitations where owner_id=own or member_user_id=p_user or email=(select lower(trim(email)) from auth.users where id=p_user);
 -- Keep the inactive profile until Auth deletes it through its foreign key.
 -- This prevents an interrupted deletion from recreating an empty profile.
end $$;
revoke all on function public.begin_account_deletion(uuid),public.purge_account_data(uuid) from public,anon,authenticated;
grant execute on function public.begin_account_deletion(uuid),public.purge_account_data(uuid) to service_role;

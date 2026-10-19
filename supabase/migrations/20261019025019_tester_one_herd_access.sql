-- Testing enrollment is controlled by an administrator, never a client claim.
-- Disable future grants with:
-- update breeder_private.testing_access set enabled=false where singleton;
-- Existing licenses are retained when enrollment is disabled.
create table breeder_private.testing_access (
 singleton boolean primary key default true check (singleton),
 enabled boolean not null default false
);
alter table breeder_private.testing_access enable row level security;
revoke all on breeder_private.testing_access from public,anon,authenticated;
grant all on breeder_private.testing_access to service_role;
insert into breeder_private.testing_access(singleton,enabled) values(true,true);

create function breeder_private.grant_testing_herd_access() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.is_active and new.auth_user_id is not null
  and exists(select 1 from breeder_private.testing_access where singleton and enabled)
  and exists(select 1 from auth.users where id=new.auth_user_id and email_confirmed_at is not null and deleted_at is null)
  -- Never overwrite paid access, renew an expired license, or undo cancellation.
  and not exists(select 1 from public.user_licenses where user_id=new.id) then
  insert into public.user_licenses(user_id,tier_code,status)
   values(new.id,'HOBBY','active');
 end if;
 return new;
end;
$$;
revoke all on function breeder_private.grant_testing_herd_access() from public,anon,authenticated;
create trigger breeder_testing_herd_access
 after insert on public.users
 for each row execute function breeder_private.grant_testing_herd_access();

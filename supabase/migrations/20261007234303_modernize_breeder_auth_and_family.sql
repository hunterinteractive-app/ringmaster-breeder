-- Preserve legacy IDs and all records. Link identities only after email verification.
create schema breeder_private;
revoke all on schema breeder_private from public, anon;
grant usage on schema breeder_private to authenticated, service_role;
alter table public.users add column auth_user_id uuid unique references auth.users(id);
alter table public.users add column address text;
alter table public.users add column city text;
alter table public.users add column state text;
alter table public.users add column zip text;
alter table public.users add column phone text;
create unique index users_normalized_email on public.users(lower(btrim(email)));

create table breeder_private.invitations (
 id uuid primary key default gen_random_uuid(),
 owner_id text not null references public.users(id),
 email text not null check (email=lower(btrim(email))),
 member_user_id uuid references auth.users(id),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '7 days',
 accepted_at timestamptz,
 revoked_at timestamptz
);
alter table breeder_private.invitations enable row level security;
revoke all on breeder_private.invitations from public, anon, authenticated;
create unique index breeder_active_invitation on breeder_private.invitations(owner_id,email) where revoked_at is null;
create index breeder_member_lookup on breeder_private.invitations(member_user_id,owner_id) where revoked_at is null;
create index breeder_invitation_inbox on breeder_private.invitations(email) where revoked_at is null and accepted_at is null;

create function breeder_private.owns(p_owner text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.users where id=p_owner and auth_user_id=auth.uid() and is_active=true);
$$;
create function breeder_private.has_access(p_owner text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (breeder_private.owns(p_owner) or exists(
  select 1 from breeder_private.invitations i join public.users u on u.id=i.owner_id
  where i.owner_id=p_owner and i.member_user_id=auth.uid() and i.accepted_at is not null
   and i.revoked_at is null and u.is_active=true));
$$;
create function breeder_private.animal_access(p_animal uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.animals a join public.farms f on f.id=a.ring_id
  where a.id=p_animal and not coalesce(f.is_demo,false) and breeder_private.has_access(f.owner_id));
$$;
create function breeder_private.ensure_identity() returns text
language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_email text; v_id text; v_link uuid;
begin
 if v_actor is null then raise exception 'Sign in first'; end if;
 select lower(btrim(email)) into v_email from auth.users where id=v_actor and email_confirmed_at is not null;
 if v_email is null then raise exception 'Verify your email first'; end if;
 select id into v_id from public.users where auth_user_id=v_actor and is_active=true;
 if v_id is not null then return v_id; end if;
 -- Unique normalized email and a row lock prevent ambiguous legacy claims.
 select id,auth_user_id into v_id,v_link from public.users where lower(btrim(email))=v_email for update;
 if v_id is not null then
  if v_link is not null and v_link<>v_actor then raise exception 'Account is already linked'; end if;
  if not exists(select 1 from public.users where id=v_id and is_active=true) then raise exception 'Account is inactive'; end if;
  update public.users set auth_user_id=v_actor where id=v_id;
 else
  v_id:=v_actor::text;
  insert into public.users(id,username,email,display_name,auth_user_id)
   values(v_id,'breeder_'||replace(v_actor::text,'-',''),v_email,'',v_actor);
 end if;
 return v_id;
end;
$$;
create function breeder_private.family_access(p_action text default 'list',p_invitation_id uuid default null,p_email text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_owner text; v_email text; v_i breeder_private.invitations;
begin
 v_owner:=breeder_private.ensure_identity();
 select lower(btrim(email)) into v_email from auth.users where id=auth.uid() and email_confirmed_at is not null;
 if p_action='invite' then
  p_email:=lower(btrim(p_email));
  if p_email is null or length(p_email)>254 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Enter a valid email'; end if;
  if p_email=v_email then raise exception 'You already own this family'; end if;
  update breeder_private.invitations set revoked_at=now() where owner_id=v_owner and email=p_email and revoked_at is null and accepted_at is null and expires_at<=now();
  insert into breeder_private.invitations(owner_id,email) values(v_owner,p_email)
   on conflict(owner_id,email) where revoked_at is null do nothing;
 elsif p_action in ('accept','revoke','leave') then
  select * into v_i from breeder_private.invitations where id=p_invitation_id for update;
  if not found or v_i.revoked_at is not null then raise exception 'Invitation unavailable'; end if;
  if p_action='accept' then
   if v_i.email<>v_email or v_i.owner_id=v_owner or v_i.expires_at<=now()
    or v_i.accepted_at is not null then raise exception 'Invitation unavailable for this login'; end if;
   update breeder_private.invitations set member_user_id=auth.uid(),accepted_at=now() where id=v_i.id;
  elsif p_action='revoke' then
   if v_i.owner_id<>v_owner then raise exception 'Only the owner can revoke'; end if;
   update breeder_private.invitations set revoked_at=now() where id=v_i.id;
  else
   if v_i.member_user_id is distinct from auth.uid() and not(v_i.member_user_id is null and v_i.email=v_email) then raise exception 'Cannot leave another family'; end if;
   update breeder_private.invitations set revoked_at=now() where id=v_i.id;
  end if;
 elsif p_action<>'list' then raise exception 'Unknown family action'; end if;
 return jsonb_build_object(
  'households',(select coalesce(jsonb_agg(h),'[]'::jsonb) from (
   select v_owner owner_user_id,'My family'::text label,true is_owner
   union all select distinct i.owner_id,coalesce(nullif(u.display_name,''),u.email)||' family',false
   from breeder_private.invitations i join public.users u on u.id=i.owner_id
   where i.member_user_id=auth.uid() and i.accepted_at is not null and i.revoked_at is null and u.is_active=true) h),
  'invitations',(select coalesce(jsonb_agg(x order by x.created_at),'[]'::jsonb) from (
   select i.id,i.owner_id owner_user_id,i.email,i.accepted_at,i.expires_at,i.created_at,u.email owner_email,(i.owner_id=v_owner) is_owner
   from breeder_private.invitations i join public.users u on u.id=i.owner_id
   where i.revoked_at is null and (i.accepted_at is not null or i.expires_at>now())
    and (i.owner_id=v_owner or i.member_user_id=auth.uid() or (i.member_user_id is null and i.email=v_email))) x));
end;
$$;
create function public.breeder_family_access(p_action text default 'list',p_invitation_id uuid default null,p_email text default null)
returns jsonb language sql security invoker set search_path='' as $$
 select breeder_private.family_access(p_action,p_invitation_id,p_email);
$$;

-- Only a verified family can create Rings. Lock the owner to serialize quota checks.
create function breeder_private.create_ring(p_name text,p_owner_id text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_max integer; v_id uuid;
begin
 perform breeder_private.ensure_identity();
 if not breeder_private.has_access(p_owner_id) then raise exception 'Family access required'; end if;
 if nullif(btrim(p_name),'') is null then raise exception 'Ring name required'; end if;
 perform 1 from public.users where id=p_owner_id for update;
 select max(t.max_rings) into v_max from public.user_licenses l join public.license_tiers t on t.code=l.tier_code
  where l.user_id=p_owner_id and l.status='active' and (l.expires_at is null or l.expires_at>now());
 if v_max is null or (select count(*) from public.farms where owner_id=p_owner_id and not coalesce(is_demo,false))>=v_max then raise exception 'Ring limit reached'; end if;
 insert into public.farms(name,owner_id,is_demo) values(btrim(p_name),p_owner_id,false) returning id into v_id;
 return v_id;
end;
$$;
create function public.create_breeder_ring(p_name text,p_owner_id text) returns uuid
language sql security invoker set search_path='' as $$ select breeder_private.create_ring(p_name,p_owner_id); $$;

-- Remove obsolete permissive policies: permissive policies combine with OR.
do $$ declare r record; begin
 for r in select schemaname,tablename,policyname from pg_policies where schemaname='public'
  and tablename in ('users','farms','animals','animal_weights','animal_health_records','user_licenses','license_tiers','species','breeds','varieties') loop
  execute format('drop policy %I on %I.%I',r.policyname,r.schemaname,r.tablename);
 end loop;
 for r in select policyname from pg_policies where schemaname='storage' and tablename='objects'
  and (coalesce(qual,'') like '%health_attachments%' or coalesce(with_check,'') like '%health_attachments%' or qual='true') loop
  execute format('drop policy %I on storage.objects',r.policyname);
 end loop;
end $$;

alter table public.users enable row level security;
alter table public.user_licenses enable row level security;
alter table public.license_tiers enable row level security;
alter table public.species enable row level security;
alter table public.breeds enable row level security;
alter table public.varieties enable row level security;
create policy family_users_read on public.users for select to authenticated using(breeder_private.has_access(id));
create policy owner_profile_update on public.users for update to authenticated using(breeder_private.owns(id)) with check(breeder_private.owns(id));
create policy family_farms_read on public.farms for select to authenticated using(breeder_private.has_access(owner_id) and not coalesce(is_demo,false));
create policy family_farms_update on public.farms for update to authenticated using(breeder_private.has_access(owner_id) and not coalesce(is_demo,false)) with check(breeder_private.has_access(owner_id) and not coalesce(is_demo,false));
create policy family_animals on public.animals for all to authenticated
 using(exists(select 1 from public.farms f where f.id=ring_id and breeder_private.has_access(f.owner_id) and not coalesce(f.is_demo,false)))
 with check(exists(select 1 from public.farms f where f.id=ring_id and breeder_private.has_access(f.owner_id) and not coalesce(f.is_demo,false)));
create policy family_weights_read on public.animal_weights for select to authenticated using(breeder_private.animal_access(animal_id));
create policy family_weights_insert on public.animal_weights for insert to authenticated with check(breeder_private.animal_access(animal_id));
create policy family_health on public.animal_health_records for all to authenticated using(breeder_private.animal_access(animal_id)) with check(breeder_private.animal_access(animal_id));
create policy family_license_read on public.user_licenses for select to authenticated using(breeder_private.has_access(user_id));
create policy tiers_read on public.license_tiers for select to authenticated using(true);
create policy species_read on public.species for select to authenticated using(true);
create policy breeds_read on public.breeds for select to authenticated using(true);
create policy varieties_read on public.varieties for select to authenticated using(true);

revoke all on public.users,public.farms,public.user_licenses,public.license_tiers,public.species,public.breeds,public.varieties,public.animals,public.animal_weights,public.animal_health_records from anon,authenticated;
grant select on public.users,public.farms,public.user_licenses,public.license_tiers,public.species,public.breeds,public.varieties to authenticated;
grant update(display_name,address,city,state,zip,phone) on public.users to authenticated;
grant update(name) on public.farms to authenticated;
grant select,insert,update on public.animals to authenticated;
grant select,insert on public.animal_weights to authenticated;
grant select,insert,update,delete on public.animal_health_records to authenticated;

-- Private attachment paths are <animal UUID>/<filename>; existing flat paths
-- remain readable only when linked from a health record in an accessible family.
create function breeder_private.attachment_access(p_path text) returns boolean
language plpgsql stable security definer set search_path='' as $$
begin
 if exists(select 1 from public.animal_health_records r where
  (r.attachment_url=p_path or r.attachment_url like '%/health_attachments/'||p_path)
  and breeder_private.animal_access(r.animal_id)) then return true; end if;
 if split_part(p_path,'/',1) ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
  return breeder_private.animal_access(split_part(p_path,'/',1)::uuid);
 end if;
 return false;
end;
$$;
update storage.buckets set public=false,file_size_limit=10485760 where id='health_attachments';
create policy family_attachment_read on storage.objects for select to authenticated using(bucket_id='health_attachments' and breeder_private.attachment_access(name));
create policy family_attachment_insert on storage.objects for insert to authenticated with check(bucket_id='health_attachments' and breeder_private.attachment_access(name));
create policy family_attachment_delete on storage.objects for delete to authenticated using(bucket_id='health_attachments' and breeder_private.attachment_access(name));

-- Correct a pre-existing trigger referring to a nonexistent column.
create or replace function public.prevent_duplicate_animals() returns trigger
language plpgsql set search_path='' as $$ begin
 if new.dedupe_hash is not null and exists(select 1 from public.animals where ring_id=new.ring_id
  and dedupe_hash=new.dedupe_hash and created_at>now()-interval '5 seconds') then raise exception 'Duplicate insert blocked'; end if;
 return new;
end; $$;
-- Existing animal data uses title-case species; normalize in one contract.
alter table public.animals drop constraint animals_species_check;
update public.animals set species=lower(species);
alter table public.animals add constraint animals_species_check check(species in ('rabbit','cavy'));

create function breeder_private.validate_animal() returns trigger
language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' and old.status in ('sold','deceased') then raise exception 'Historical animal is locked'; end if;
 if new.sire_id is not null and not exists(select 1 from public.animals where id=new.sire_id and ring_id=new.ring_id and species=new.species and sex='M') then raise exception 'Invalid sire'; end if;
 if new.dam_id is not null and not exists(select 1 from public.animals where id=new.dam_id and ring_id=new.ring_id and species=new.species and sex='F') then raise exception 'Invalid dam'; end if;
 if new.dob>current_date then raise exception 'Birth date cannot be in the future'; end if;
 return new;
end; $$;
create trigger breeder_validate_animal before insert or update on public.animals for each row execute function breeder_private.validate_animal();
create function breeder_private.validate_weight() returns trigger
language plpgsql set search_path='' as $$ begin
 if exists(select 1 from public.animals where id=new.animal_id and status in ('sold','deceased')) then raise exception 'Historical animal is locked'; end if;
 return new;
end; $$;
create trigger breeder_validate_weight before insert on public.animal_weights for each row execute function breeder_private.validate_weight();

-- Fix search paths and limit all public RPCs to signed-in clients.
do $$ declare r record; begin
 for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' loop
  execute format('alter function %s set search_path=public',r.signature);
  execute format('revoke all on function %s from public,anon',r.signature);
  execute format('grant execute on function %s to authenticated',r.signature);
 end loop;
end $$;
revoke all on all functions in schema breeder_private from public,anon,authenticated;
grant execute on function breeder_private.owns(text),breeder_private.has_access(text),breeder_private.animal_access(uuid),breeder_private.attachment_access(text),breeder_private.family_access(text,uuid,text),breeder_private.create_ring(text,text) to authenticated;
create index farms_owner_lookup on public.farms(owner_id);
create index animals_ring_lookup on public.animals(ring_id);
create index animals_sire_lookup on public.animals(sire_id);
create index animals_dam_lookup on public.animals(dam_id);
create index weights_animal_date on public.animal_weights(animal_id,recorded_at desc);
create index health_animal_lookup on public.animal_health_records(animal_id);
create index licenses_user_lookup on public.user_licenses(user_id);

-- One request returns all fifteen pedigree slots and current weights under RLS.
create function public.breeder_pedigree_snapshot(p_animal_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 with recursive ancestry as (
  select a.*,0 slot,0 depth from public.animals a where a.id=p_animal_id
  union all
  select a.*,parent.slot,ancestry.depth+1 from ancestry
  cross join lateral (values (ancestry.sire_id,ancestry.slot*2+1),(ancestry.dam_id,ancestry.slot*2+2)) parent(id,slot)
  join public.animals a on a.id=parent.id where ancestry.depth<3
 )
 select coalesce(jsonb_object_agg(
  (array['animal','sire','dam','sire_sire','sire_dam','dam_sire','dam_dam','gg1','gg2','gg3','gg4','gg5','gg6','gg7','gg8'])[slot+1],
  (to_jsonb(ancestry)-'slot'-'depth')||jsonb_build_object('weight',(
   select w.weight from public.animal_weights w where w.animal_id=ancestry.id order by recorded_at desc limit 1))), '{}'::jsonb)
 from ancestry;
$$;
revoke all on function public.breeder_pedigree_snapshot(uuid) from public,anon;
grant execute on function public.breeder_pedigree_snapshot(uuid) to authenticated;

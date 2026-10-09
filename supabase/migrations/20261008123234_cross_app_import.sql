create table public.breeder_exhibitor_profiles (
 id uuid primary key default gen_random_uuid(), owner_id text not null references public.users(id),
 source_app text not null check(source_app in ('ringmaster_show','ringmaster_club','ringmaster_breeder')),
 source_id uuid not null, profile jsonb not null, imported_at timestamptz not null default now(),
 unique(owner_id,source_app,source_id)
);
create table public.breeder_imported_animals (
 owner_id text not null references public.users(id), source_app text not null,
 source_id uuid not null, animal_id uuid not null references public.animals(id),
 primary key(owner_id,source_app,source_id)
);
create index breeder_imported_animals_animal_idx on public.breeder_imported_animals(animal_id);
create table public.breeder_show_history (
 id uuid primary key default gen_random_uuid(),owner_id text not null references public.users(id),
 source_app text not null,source_entry_id uuid not null,
 animal_id uuid references public.animals(id),exhibitor_source_id uuid not null,
 record jsonb not null, imported_at timestamptz not null default now(),
 unique(owner_id,source_app,source_entry_id)
);
create index breeder_show_history_animal_idx on public.breeder_show_history(animal_id);
create index breeder_exhibitor_profiles_owner_idx on public.breeder_exhibitor_profiles(owner_id);
create index breeder_show_history_owner_idx on public.breeder_show_history(owner_id);
alter table public.breeder_exhibitor_profiles enable row level security;
alter table public.breeder_imported_animals enable row level security;
alter table public.breeder_show_history enable row level security;
create policy family_read on public.breeder_exhibitor_profiles for select to authenticated using(breeder_private.has_access(owner_id));
create policy family_read on public.breeder_imported_animals for select to authenticated using(breeder_private.has_access(owner_id));
create policy family_read on public.breeder_show_history for select to authenticated using(breeder_private.has_access(owner_id));
revoke all on public.breeder_exhibitor_profiles,public.breeder_imported_animals,public.breeder_show_history from anon,authenticated;
grant select on public.breeder_exhibitor_profiles,public.breeder_imported_animals,public.breeder_show_history to authenticated;
grant all on public.breeder_exhibitor_profiles,public.breeder_imported_animals,public.breeder_show_history to service_role;
-- Service-only lookup. The edge function supplies a verified authentication email.
create function public.find_exhibitors_for_breeder_export(p_email text) returns jsonb
language sql security invoker set search_path='' as $$
 select coalesce(jsonb_agg(x),'[]'::jsonb) from (
 select p.id,p.profile || jsonb_build_object('id',p.id,'owner_user_id',u.auth_user_id,'email',u.email) as profile
 from public.users u join public.breeder_exhibitor_profiles p on p.owner_id=u.id
 where lower(btrim(u.email))=lower(btrim(p_email)) and u.is_active=true
 union all
 select md5('ringmaster_breeder:'||u.id)::uuid,
 jsonb_build_object('id',md5('ringmaster_breeder:'||u.id)::uuid,'owner_user_id',u.auth_user_id,
 'display_name',u.display_name,'showing_name',u.display_name,'email',u.email,'phone',u.phone,
 'address_line1',u.address,'city',u.city,'state',u.state,'zip',u.zip,'arba_number',u.arba_number,
 'type','individual','is_active',true)
 from public.users u where lower(btrim(u.email))=lower(btrim(p_email)) and u.is_active=true
 and not exists(select 1 from public.breeder_exhibitor_profiles p where p.owner_id=u.id)
 ) x;
$$;
revoke all on function public.find_exhibitors_for_breeder_export(text) from public,anon,authenticated;
grant execute on function public.find_exhibitors_for_breeder_export(text) to service_role;
-- One transaction prevents partial imports and serializes concurrent retries per owner.
create function public.apply_breeder_cross_app_import(p_actor uuid,p_source text,p_profiles jsonb,p_animals jsonb default '[]',p_entries jsonb default '[]',p_ring uuid default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_owner text; r jsonb; v_animal uuid; v_existing uuid[]; v_added int:=0; v_history int:=0;
begin
 if p_source not in ('ringmaster_show','ringmaster_club') then raise exception 'Invalid source'; end if;
 select u.id into v_owner from public.users u join auth.users a on a.id=u.auth_user_id
 where u.auth_user_id=p_actor and u.is_active and a.email_confirmed_at is not null for update of u;
 if v_owner is null then raise exception 'Verified Breeder identity required'; end if;
 if jsonb_array_length(p_profiles)=0 then raise exception 'Select a profile'; end if;
 if jsonb_array_length(p_animals)>0 and not exists(select 1 from public.farms where id=p_ring and owner_id=v_owner) then raise exception 'Select your own Ring'; end if;
 for r in select value from jsonb_array_elements(p_profiles) loop
  insert into public.breeder_exhibitor_profiles(owner_id,source_app,source_id,profile)
  values(v_owner,p_source,(r->>'id')::uuid,r) on conflict do nothing;
 end loop;
 for r in select value from jsonb_array_elements(p_animals) loop
  v_animal:=null;
  select animal_id into v_animal from public.breeder_imported_animals where owner_id=v_owner and source_app=p_source and source_id=(r->>'id')::uuid;
  if v_animal is null then
   select array_agg(a.id) into v_existing from public.animals a join public.farms f on f.id=a.ring_id
   where f.owner_id=v_owner and nullif(btrim(r->>'tattoo'),'') is not null
    and lower(btrim(a.tattoo))=lower(btrim(r->>'tattoo')) and lower(a.species)=lower(r->>'species')
    and lower(coalesce(a.breed,''))=lower(coalesce(r->>'breed','')) and upper(coalesce(a.sex,''))=upper(coalesce(r->>'sex',''));
   if cardinality(v_existing)>1 then raise exception 'Multiple matching animals; resolve duplicates before import'; end if;
   v_animal:=v_existing[1];
   if v_animal is null then
    insert into public.animals(ring_id,name,tattoo,species,breed,variety,sex,dob,status)
    values(p_ring,r->>'name',r->>'tattoo',lower(r->>'species'),r->>'breed',r->>'variety',upper(r->>'sex'),nullif(r->>'birth_date','')::date,'active') returning id into v_animal;
    v_added:=v_added+1;
   end if;
   insert into public.breeder_imported_animals values(v_owner,p_source,(r->>'id')::uuid,v_animal);
  end if;
 end loop;
 for r in select value from jsonb_array_elements(p_entries) loop
  v_animal:=null;
  select animal_id into v_animal from public.breeder_imported_animals where owner_id=v_owner and source_app=p_source and source_id=nullif(r->>'animal_id','')::uuid;
  insert into public.breeder_show_history(owner_id,source_app,source_entry_id,animal_id,exhibitor_source_id,record)
  values(v_owner,p_source,(r->>'id')::uuid,v_animal,(r->>'exhibitor_id')::uuid,r) on conflict do nothing;
  if found then v_history:=v_history+1; end if;
 end loop;
 update public.users set display_name=coalesce(nullif(display_name,''),p_profiles->0->>'display_name'),
 phone=coalesce(nullif(phone,''),p_profiles->0->>'phone'),address=coalesce(nullif(address,''),p_profiles->0->>'address_line1'),
 city=coalesce(nullif(city,''),p_profiles->0->>'city'),state=coalesce(nullif(state,''),p_profiles->0->>'state'),
 zip=coalesce(nullif(zip,''),p_profiles->0->>'zip'),arba_number=coalesce(nullif(arba_number,''),p_profiles->0->>'arba_number') where id=v_owner;
 return jsonb_build_object('status','imported','animals_added',v_added,'entries_added',v_history,'profiles_selected',jsonb_array_length(p_profiles));
end;
$$;
revoke all on function public.apply_breeder_cross_app_import(uuid,text,jsonb,jsonb,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.apply_breeder_cross_app_import(uuid,text,jsonb,jsonb,jsonb,uuid) to service_role;

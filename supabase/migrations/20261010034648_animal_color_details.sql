-- Preserve animal color descriptors separately from catalog and showroom names.
alter table public.animals add column color_details jsonb not null default '{}'::jsonb
 check (jsonb_typeof(color_details)='object');

create function public.validate_animal_color_details(p_species text,p_breed text,p_variety text,p_details jsonb)
returns void language plpgsql security invoker set search_path='' as $$
declare k text; v jsonb; cod boolean;
begin
 if p_details is null or jsonb_typeof(p_details)<>'object' then raise exception 'Invalid color details'; end if;
 for k,v in select * from jsonb_each(p_details) loop
  if k not in ('color','pattern','base_color','tipping','eye_color') or jsonb_typeof(v)<>'string' or length(v #>> '{}')>100 then
   raise exception 'Color details must contain text of 100 characters or fewer';
  end if;
 end loop;
 select coalesce(bool_or(b.name ~* '\(\s*cod\s*\)\s*$' or coalesce(vr.name,'') ~* '\(\s*cod\s*\)\s*$'),false) into cod
 from public.breeds b left join public.varieties vr on vr.breed_id=b.id and vr.catalog_key=public.catalog_key(p_variety)
 where b.species=lower(p_species) and b.catalog_key=public.catalog_key(p_breed);
 cod:=cod or coalesce(p_breed ~* '\(\s*cod\s*\)\s*$',false) or coalesce(p_variety ~* '\(\s*cod\s*\)\s*$',false);
 if cod and (nullif(btrim(p_details->>'color'),'') is null or nullif(btrim(p_details->>'pattern'),'') is null) then
  raise exception 'Enter both color and pattern for this COD selection';
 end if;
end $$;
revoke all on function public.validate_animal_color_details(text,text,text,jsonb) from public,anon;
grant execute on function public.validate_animal_color_details(text,text,text,jsonb) to authenticated;

create function public.create_animal_with_color_details(
 p_ring_id uuid,p_name text,p_tattoo text,p_species text,p_breed text,p_variety text,
 p_sex text,p_status text,p_dob date,p_registration text,p_gc text,p_sire_id uuid,p_dam_id uuid,p_weight numeric,p_color_details jsonb)
returns uuid language plpgsql security invoker set search_path='' as $$
declare aid uuid;
begin
 perform public.validate_animal_color_details(p_species,p_breed,p_variety,p_color_details);
 insert into public.animals(ring_id,name,tattoo,species,breed,variety,sex,status,dob,registration_number,grand_champion_number,sire_id,dam_id,color_details)
 values(p_ring_id,p_name,p_tattoo,p_species,p_breed,p_variety,p_sex,p_status,p_dob,p_registration,p_gc,p_sire_id,p_dam_id,p_color_details) returning id into aid;
 if p_weight is not null then
  if p_weight<=0 then raise exception 'Weight must be positive'; end if;
  insert into public.animal_weights(animal_id,weight) values(aid,p_weight);
 end if;
 return aid;
end $$;
revoke all on function public.create_animal_with_color_details(uuid,text,text,text,text,text,text,text,date,text,text,uuid,uuid,numeric,jsonb) from public,anon;
grant execute on function public.create_animal_with_color_details(uuid,text,text,text,text,text,text,text,date,text,text,uuid,uuid,numeric,jsonb) to authenticated;

-- Legacy and imported animals may have unknown details. Explicit detail edits must be complete.
create function breeder_private.check_color_detail_edit() returns trigger
language plpgsql security invoker set search_path='' as $$ begin
 perform public.validate_animal_color_details(new.species,new.breed,new.variety,new.color_details);
 return new;
end $$;
revoke all on function breeder_private.check_color_detail_edit() from public,anon,authenticated;
create trigger check_color_detail_edit before update of color_details on public.animals
for each row execute function breeder_private.check_color_detail_edit();

update public.varieties v set name='Broken',is_recognized=true from public.breeds b
where b.id=v.breed_id and b.species='rabbit' and b.name='English Angora' and v.catalog_key='broken';

create or replace function public.save_pedigree_draft(p_draft uuid) returns uuid
language plpgsql security invoker set search_path='' as $$
declare d public.pedigree_drafts; nodes jsonb; r record; n jsonb; ids jsonb:='{}'; aid uuid; root_id uuid; root_key text; v_species text; k text; parent_key text; cycle_found boolean;
begin
 select * into d from public.pedigree_drafts where id=p_draft for update;
 if not found then raise exception 'Draft not found or access denied'; end if;
 if d.saved_animal_id is not null then return d.saved_animal_id; end if;
 nodes:=d.data->'nodes'; root_key:=d.data->>'root'; v_species:=d.data->>'species';
 if jsonb_typeof(nodes) is distinct from 'object' or v_species not in ('rabbit','cavy') or nodes->root_key is null then raise exception 'Invalid pedigree'; end if;
 if (select count(*) from jsonb_object_keys(nodes))>100 then raise exception 'Too many ancestors'; end if;
 if nullif(nodes->root_key->>'existing_id','') is not null then raise exception 'The new animal must have its own record'; end if;
 with recursive walk(k,path,cycle) as (
  select root_key,array[root_key],false
  union all
  select e.value,w.path||e.value,e.value=any(w.path) from walk w
  cross join lateral (values(nodes->w.k->>'sire'),(nodes->w.k->>'dam')) e(value)
  where e.value is not null and not w.cycle
 ) select coalesce(bool_or(cycle),false) into cycle_found from walk;
 if cycle_found then raise exception 'An animal cannot be its own ancestor'; end if;
 for r in select * from jsonb_each(nodes) loop
  n:=r.value;
  if nullif(n->>'existing_id','') is not null then
   select id into aid from public.animals where id=(n->>'existing_id')::uuid and ring_id=d.ring_id and public.animals.species=v_species;
   if not found then raise exception 'Ancestor not found in this Ring'; end if;
  else
   if coalesce(nullif(btrim(n->>'name'),''),nullif(btrim(n->>'tattoo'),'')) is null then raise exception 'Enter a name or ear number for each ancestor'; end if;
   if nullif(btrim(n->>'tattoo'),'') is not null and exists(select 1 from public.animals a where a.ring_id=d.ring_id and a.species=v_species and lower(btrim(a.tattoo))=lower(btrim(n->>'tattoo')) and a.sex=n->>'sex') then raise exception 'An animal with this ear number already exists. Select it from the matching records'; end if;
   perform public.validate_animal_color_details(v_species,n->>'breed',n->>'variety',coalesce(n->'color_details','{}'::jsonb));
   insert into public.animals(ring_id,name,tattoo,species,breed,variety,sex,dob,status,registration_number,grand_champion_number,legs,pedigree_only,color_details)
   values(d.ring_id,nullif(btrim(n->>'name'),''),nullif(btrim(n->>'tattoo'),''),v_species,n->>'breed',n->>'variety',n->>'sex',nullif(n->>'dob','')::date,'active',n->>'registration_number',n->>'grand_champion_number',nullif(n->>'legs','')::integer,r.key<>root_key,coalesce(n->'color_details','{}'::jsonb)) returning id into aid;
   if nullif(n->>'weight','') is not null then
    if (n->>'weight')::numeric<=0 then raise exception 'Weight must be positive'; end if;
    insert into public.animal_weights(animal_id,weight) values(aid,(n->>'weight')::numeric);
   end if;
  end if;
  ids:=ids||jsonb_build_object(r.key,aid);
 end loop;
 for r in select * from jsonb_each(nodes) loop
  n:=r.value;
  if nullif(n->>'existing_id','') is null then
   foreach k in array array['sire','dam'] loop
    parent_key:=n->>k;
    if parent_key is not null and ids->>parent_key is null then raise exception 'Missing ancestor reference'; end if;
   end loop;
   update public.animals set sire_id=(ids->>(n->>'sire'))::uuid,dam_id=(ids->>(n->>'dam'))::uuid where id=(ids->>r.key)::uuid;
  end if;
 end loop;
 root_id:=(ids->>root_key)::uuid;
 -- Restricted helper records completion; clients cannot directly set this column.
 perform breeder_private.finish_pedigree_draft(p_draft,root_id);
 return root_id;
end; $$;

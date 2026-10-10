alter table public.animals add column leg_details text not null default '' check (length(leg_details)<=4000);

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
   insert into public.animals(ring_id,name,tattoo,species,breed,variety,sex,dob,status,registration_number,grand_champion_number,legs,pedigree_only,color_details,leg_details)
   values(d.ring_id,nullif(btrim(n->>'name'),''),nullif(btrim(n->>'tattoo'),''),v_species,n->>'breed',n->>'variety',n->>'sex',nullif(n->>'dob','')::date,'active',n->>'registration_number',n->>'grand_champion_number',nullif(n->>'legs','')::integer,r.key<>root_key,coalesce(n->'color_details','{}'::jsonb),coalesce(n->>'leg_details','')) returning id into aid;
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

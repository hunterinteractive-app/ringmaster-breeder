-- Reference snapshot before modernization; do not apply to a running project.
create table public.animal_health_records (id uuid not null default gen_random_uuid(), animal_id uuid, record_type text not null, title text not null, description text, administered_date date not null, expires_date date, veterinarian text, medication text, dosage text, created_at timestamp with time zone default now(), readminister_date date, attachment_url text, retention text default '7_days'::text);
create table public.species (id uuid not null default gen_random_uuid(), name text not null);
create table public.users (id text not null, username text not null, email text not null, display_name text, arba_number text, role text default 'breeder'::text, created_at timestamp with time zone default now(), is_active boolean default true);
create table public.user_licenses (id uuid not null default gen_random_uuid(), user_id text not null, tier_code text not null, status text default 'active'::text, started_at timestamp with time zone default now(), expires_at timestamp with time zone);
create table public.license_tiers (code text not null, name text not null, max_rings integer not null, is_demo_allowed boolean default false, created_at timestamp with time zone default now());
create table public.farms (id uuid not null default gen_random_uuid(), name text not null, owner_id text, is_demo boolean default false, created_at timestamp with time zone default now());
create table public.animals (id uuid not null default gen_random_uuid(), ring_id uuid not null, name text, tattoo text, species text not null, breed text, sex text, dob date, status text default 'active'::text, notes text, created_at timestamp with time zone default now(), variety text, registration_number text, grand_champion_number text, dedupe_hash text, sire_id uuid, dam_id uuid, sire_external text, dam_external text);
create table public.animal_weights (id uuid not null default gen_random_uuid(), animal_id uuid not null, weight numeric, recorded_at timestamp with time zone default now());
create table public.breeds (id uuid not null default gen_random_uuid(), species text not null, name text not null, arba_code text, is_recognized boolean default true, created_at timestamp with time zone default now());
create table public.varieties (id uuid not null default gen_random_uuid(), breed_id uuid, name text not null, is_recognized boolean default true, created_at timestamp with time zone default now());
alter table animals add constraint animals_sex_check CHECK ((sex = ANY (ARRAY['M'::text, 'F'::text])));
alter table animal_weights add constraint weight_must_be_positive_numeric CHECK (((weight IS NOT NULL) AND (weight > (0)::numeric) AND (weight < (1000)::numeric)));
alter table animals add constraint animals_species_check CHECK ((species = ANY (ARRAY['Rabbit'::text, 'Cavy'::text])));
alter table animals add constraint animals_status_check CHECK ((status = ANY (ARRAY['active'::text, 'sold'::text, 'retired'::text, 'deceased'::text])));
alter table breeds add constraint breeds_species_check CHECK ((species = ANY (ARRAY['rabbit'::text, 'cavy'::text])));
alter table animals add constraint no_self_parent CHECK (((id <> sire_id) AND (id <> dam_id)));
alter table user_licenses add constraint user_licenses_status_check CHECK ((status = ANY (ARRAY['active'::text, 'expired'::text, 'cancelled'::text])));
alter table license_tiers add constraint license_tiers_pkey PRIMARY KEY (code);
alter table breeds add constraint breeds_pkey PRIMARY KEY (id);
alter table farms add constraint farms_pkey PRIMARY KEY (id);
alter table animals add constraint animals_pkey PRIMARY KEY (id);
alter table species add constraint species_pkey PRIMARY KEY (id);
alter table user_licenses add constraint user_licenses_pkey PRIMARY KEY (id);
alter table animal_weights add constraint animal_weights_pkey PRIMARY KEY (id);
alter table animal_health_records add constraint animal_health_records_pkey PRIMARY KEY (id);
alter table varieties add constraint varieties_pkey PRIMARY KEY (id);
alter table users add constraint users_pkey PRIMARY KEY (id);
alter table species add constraint species_name_key UNIQUE (name);
alter table users add constraint users_username_key UNIQUE (username);
alter table users add constraint users_email_key UNIQUE (email);
alter table animal_health_records add constraint animal_health_records_animal_id_fkey FOREIGN KEY (animal_id) REFERENCES animals(id) ON DELETE CASCADE;
alter table animal_weights add constraint animal_weights_animal_id_fkey FOREIGN KEY (animal_id) REFERENCES animals(id) ON DELETE CASCADE;
alter table animals add constraint animals_dam_id_fkey FOREIGN KEY (dam_id) REFERENCES animals(id) ON DELETE SET NULL;
alter table animals add constraint animals_ring_id_fkey FOREIGN KEY (ring_id) REFERENCES farms(id) ON DELETE CASCADE;
alter table animals add constraint animals_sire_id_fkey FOREIGN KEY (sire_id) REFERENCES animals(id) ON DELETE SET NULL;
alter table farms add constraint farms_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES users(id);
alter table user_licenses add constraint user_licenses_tier_code_fkey FOREIGN KEY (tier_code) REFERENCES license_tiers(code);
alter table user_licenses add constraint user_licenses_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id);
alter table varieties add constraint varieties_breed_id_fkey FOREIGN KEY (breed_id) REFERENCES breeds(id) ON DELETE CASCADE;
CREATE OR REPLACE FUNCTION public.create_animal_with_weight(p_ring_id uuid, p_name text, p_tattoo text, p_species text, p_breed text, p_variety text, p_sex text, p_status text, p_dob date, p_registration text, p_gc text, p_weight numeric)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  new_animal_id uuid;
BEGIN
  -- Insert animal
  INSERT INTO public.animals (
    ring_id,
    name,
    tattoo,
    species,
    breed,
    variety,
    sex,
    status,
    dob,
    registration_number,
    grand_champion_number
  ) VALUES (
    p_ring_id,
    p_name,
    p_tattoo,
    p_species,
    p_breed,
    p_variety,
    p_sex,
    p_status,
    p_dob,
    p_registration,
    p_gc
  )
  RETURNING id INTO new_animal_id;

  -- Insert weight ONLY if provided
  IF p_weight IS NOT NULL THEN
    INSERT INTO public.animal_weights (
      animal_id,
      weight
    ) VALUES (
      new_animal_id,
      p_weight
    );
  END IF;

  RETURN new_animal_id;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.create_animal_with_weight(p_ring_id uuid, p_name text, p_tattoo text, p_species text, p_breed text, p_variety text, p_sex text, p_status text, p_dob date, p_registration text, p_gc text, p_sire_id uuid, p_dam_id uuid, p_weight numeric)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
declare
  new_animal_id uuid;
begin
  insert into animals (
    ring_id,
    name,
    tattoo,
    species,
    breed,
    variety,
    sex,
    status,
    dob,
    registration_number,
    grand_champion_number,
    sire_id,
    dam_id
  )
  values (
    p_ring_id,
    p_name,
    p_tattoo,
    p_species,
    p_breed,
    p_variety,
    p_sex,
    p_status,
    p_dob,
    p_registration,
    p_gc,
    p_sire_id,
    p_dam_id
  )
  returning id into new_animal_id;

  if p_weight is not null then
    insert into animal_weights (animal_id, weight)
    values (new_animal_id, p_weight);
  end if;

  return new_animal_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.get_full_pedigree(p_animal_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  a record;
  s record;
  d record;
  ss record;
  sd record;
  ds record;
  dd record;
begin
  select * into a from animals where id = p_animal_id;

  if a.id is null then
    return '{}'::jsonb;
  end if;

  select * into s from animals where id = a.sire_id;
  select * into d from animals where id = a.dam_id;

  select * into ss from animals where id = s.sire_id;
  select * into sd from animals where id = s.dam_id;
  select * into ds from animals where id = d.sire_id;
  select * into dd from animals where id = d.dam_id;

  return jsonb_build_object(
    'animal', to_jsonb(a),
    'sire', to_jsonb(s),
    'dam', to_jsonb(d),
    'sire_sire', to_jsonb(ss),
    'sire_dam', to_jsonb(sd),
    'dam_sire', to_jsonb(ds),
    'dam_dam', to_jsonb(dd)
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.get_parent_candidates(p_ring_id uuid, p_species text, p_sex text)
 RETURNS TABLE(id uuid, name text)
 LANGUAGE sql
 STABLE
AS $function$
  select id, name
  from animals
  where ring_id = p_ring_id
    and species = p_species
    and sex = p_sex
    and status != 'deceased'
  order by name;
$function$
;
CREATE OR REPLACE FUNCTION public.get_pedigree_snapshot(p_animal_id uuid)
 RETURNS TABLE(id uuid, name text, tattoo text, sex text, sire_id uuid, dam_id uuid)
 LANGUAGE sql
AS $function$
  select
    a.id,
    a.name,
    a.tattoo,
    a.sex,
    a.sire_id,
    a.dam_id
  from animals a
  where a.id = p_animal_id;
$function$
;
CREATE OR REPLACE FUNCTION public.prevent_duplicate_animals()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.animals
    WHERE ring_id = NEW.ring_id
      AND dedupe_hash = NEW.dedupe_hash
      AND created_at > now() - interval '5 seconds'
  ) THEN
    RAISE EXCEPTION 'Duplicate insert blocked';
  END IF;

  RETURN NEW;
END;
$function$
;
CREATE TRIGGER animal_dedupe_trigger BEFORE INSERT ON public.animals FOR EACH ROW EXECUTE FUNCTION prevent_duplicate_animals();
create policy "Allow delete health records" on public.animal_health_records for DELETE to public using ((auth.role() = 'authenticated'::text));
create policy "Allow insert health records" on public.animal_health_records for INSERT to public with check ((auth.role() = 'authenticated'::text));
create policy "Allow insert own health records" on public.animal_health_records for INSERT to public with check (true);
create policy "Allow read health records" on public.animal_health_records for SELECT to public using ((auth.role() = 'authenticated'::text));
create policy "Allow update health records" on public.animal_health_records for UPDATE to public using ((auth.role() = 'authenticated'::text));
create policy "Users can delete health records" on public.animal_health_records for DELETE to authenticated using (true);
create policy "Users can insert health records" on public.animal_health_records for INSERT to authenticated with check (true);
create policy "Users can manage health records" on public.animal_health_records for ALL to public using ((EXISTS ( SELECT 1
   FROM (animals
     JOIN farms ON ((farms.id = animals.ring_id)))
  WHERE ((animals.id = animal_health_records.animal_id) AND (farms.owner_id = (auth.uid())::text))))) with check ((EXISTS ( SELECT 1
   FROM (animals
     JOIN farms ON ((farms.id = animals.ring_id)))
  WHERE ((animals.id = animal_health_records.animal_id) AND (farms.owner_id = (auth.uid())::text)))));
create policy "Users can read health records" on public.animal_health_records for SELECT to authenticated using (true);
create policy "Users can update health records" on public.animal_health_records for UPDATE to authenticated using (true);
create policy "allow delete health records" on public.animal_health_records for DELETE to public using ((auth.role() = 'authenticated'::text));
create policy "allow insert health records" on public.animal_health_records for INSERT to public with check ((auth.role() = 'authenticated'::text));
create policy "allow read health records" on public.animal_health_records for SELECT to public using ((auth.role() = 'authenticated'::text));
create policy "allow update health records" on public.animal_health_records for UPDATE to public using ((auth.role() = 'authenticated'::text));
create policy "Users can insert farms" on public.farms for INSERT to public with check ((owner_id = (auth.uid())::text));
create policy "Users can view their farms" on public.farms for SELECT to public using ((owner_id = (auth.uid())::text));
create policy "Users can insert animals into their farms" on public.animals for INSERT to public with check ((EXISTS ( SELECT 1
   FROM farms
  WHERE ((farms.id = animals.ring_id) AND (farms.owner_id = (auth.uid())::text)))));
create policy "Users can view animals in their farms" on public.animals for SELECT to public using ((EXISTS ( SELECT 1
   FROM farms
  WHERE ((farms.id = animals.ring_id) AND (farms.owner_id = (auth.uid())::text)))));
create policy "Users can manage weights" on public.animal_weights for ALL to public using ((EXISTS ( SELECT 1
   FROM (animals
     JOIN farms ON ((farms.id = animals.ring_id)))
  WHERE ((animals.id = animal_weights.animal_id) AND (farms.owner_id = (auth.uid())::text))))) with check ((EXISTS ( SELECT 1
   FROM (animals
     JOIN farms ON ((farms.id = animals.ring_id)))
  WHERE ((animals.id = animal_weights.animal_id) AND (farms.owner_id = (auth.uid())::text)))));
create policy "Allow authenticated reads 1xud9al_0" on storage.objects for SELECT to authenticated using ((bucket_id = 'health_attachments'::text));
create policy "Allow authenticated uploads 1xud9al_0" on storage.objects for INSERT to authenticated with check ((bucket_id = 'health_attachments'::text));
create policy "Allow downloads" on storage.objects for SELECT to public using ((bucket_id = 'health_attachments'::text));
create policy "Allow read" on storage.objects for SELECT to public using (true);
create policy "Allow uploads" on storage.objects for INSERT to public with check ((bucket_id = 'health_attachments'::text));
create policy "Users can delete health attachments" on storage.objects for DELETE to authenticated using ((bucket_id = 'health_attachments'::text));
create policy "Users can read attachments" on storage.objects for SELECT to public using ((bucket_id = 'health_attachments'::text));
create policy "Users can read health attachments" on storage.objects for SELECT to authenticated using ((bucket_id = 'health_attachments'::text));
create policy "Users can upload attachments" on storage.objects for INSERT to public with check (((bucket_id = 'health_attachments'::text) AND (auth.role() = 'authenticated'::text)));
create policy "Users can upload health attachments" on storage.objects for INSERT to authenticated with check ((bucket_id = 'health_attachments'::text));
create policy "allow read health attachments" on storage.objects for SELECT to public using ((bucket_id = 'health_attachments'::text));
create policy "allow upload health attachments" on storage.objects for INSERT to public with check (((bucket_id = 'health_attachments'::text) AND (auth.role() = 'authenticated'::text)));
create policy "limit health attachment size" on storage.objects for INSERT to authenticated with check (((bucket_id = 'health_attachments'::text) AND (((metadata ->> 'size'::text))::integer <= 10485760)));
alter table public.animal_health_records enable row level security;
alter table public.farms enable row level security;
alter table public.animals enable row level security;
alter table public.animal_weights enable row level security;

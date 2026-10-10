-- Show is the source for recognition; custom names remain shared.
create or replace function public.catalog_key(value text) returns text
language sql immutable strict set search_path='' as $$
 select lower(regexp_replace(trim(value), '\s+', ' ', 'g'))
$$;
alter table public.breeds add column catalog_key text generated always as (public.catalog_key(name)) stored;
alter table public.varieties add column catalog_key text generated always as (public.catalog_key(name)) stored;
create unique index breeds_catalog_identity on public.breeds(species,catalog_key);
create unique index varieties_catalog_identity on public.varieties(breed_id,catalog_key);
alter table public.breeds add column show_id uuid;
alter table public.varieties add column show_id uuid;
-- Existing seed entries are retained, but only Show matches become recognized.
update public.breeds set is_recognized=false;
update public.varieties set is_recognized=false;
create or replace function breeder_private.catalog_animal() returns trigger
language plpgsql security definer set search_path='' as $$
declare b public.breeds; v public.varieties;
begin
 if nullif(trim(new.breed),'') is null then return new; end if;
 if length(new.breed)>100 or length(new.variety)>100 then raise exception 'Breed and variety names must be 100 characters or fewer'; end if;
 insert into public.breeds(species,name,is_recognized)
 values(lower(new.species),initcap(public.catalog_key(new.breed)),false)
 on conflict (species,catalog_key) do nothing;
 select * into strict b from public.breeds where species=lower(new.species) and catalog_key=public.catalog_key(new.breed);
 new.breed:=b.name;
 if nullif(trim(new.variety),'') is not null then
 insert into public.varieties(breed_id,name,is_recognized)
 values(b.id,initcap(public.catalog_key(new.variety)),false)
 on conflict (breed_id,catalog_key) do nothing;
 select * into strict v from public.varieties where breed_id=b.id and catalog_key=public.catalog_key(new.variety);
 new.variety:=v.name;
 end if;
 return new;
end $$;
revoke all on function breeder_private.catalog_animal() from public,anon,authenticated;
create trigger catalog_animal before insert or update of breed,variety,species on public.animals for each row execute function breeder_private.catalog_animal();

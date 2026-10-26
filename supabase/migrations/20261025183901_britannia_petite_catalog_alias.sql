-- Normalize the reviewed source spelling before catalog resolution. Retain all
-- existing breed/variety rows and the current trigger permissions and checks.
create or replace function breeder_private.catalog_animal() returns trigger
language plpgsql security definer set search_path='' as $$
declare b public.breeds; v public.varieties;
begin
 if nullif(trim(new.breed),'') is null then return new; end if;
 if length(new.breed)>100 or length(new.variety)>100 then raise exception 'Breed and variety names must be 100 characters or fewer'; end if;
 if lower(new.species)='rabbit' and public.catalog_key(new.breed)='britannia petit' then
  new.breed:='Britannia Petite';
 end if;
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

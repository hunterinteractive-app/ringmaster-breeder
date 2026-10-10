-- Canonical identity is independent of COD display labels, accents, punctuation
-- typography and reviewed legacy spelling mistakes. Never use fuzzy matching to merge.
create or replace function public.catalog_key(value text) returns text
language sql immutable strict set search_path='' as $$
 with folded as (
 select lower(regexp_replace(normalize(trim(value),NFKD),U&'[\0300-\036f]','','g')) as v
 ), cleaned as (
 select trim(regexp_replace(regexp_replace(translate(v,'’‘‐‑–—','''''----'),'\s*\(\s*cod\s*\)\s*$','','i'),'\s+',' ','g')) as v from folded
 ) select case v when 'champagne d''argente' then 'champagne d''argent'
 when 'peruvian stain' then 'peruvian satin' else v end from cleaned
$$;
-- Keep the source-linked record, preserving its exact display spelling and COD label.
-- Fail rather than combine genuinely distinct Show records with conflicting identities.
do $$ begin
 if exists(select 1 from public.breeds where show_id is not null group by species,public.catalog_key(name) having count(distinct show_id)>1) then
 raise exception 'Conflicting Show identities require review'; end if;
end $$;
drop index public.breeds_catalog_identity;
drop index public.varieties_catalog_identity;
drop index public.varieties_breed_name_idx;
create temporary table breed_merge on commit drop as
select id,first_value(id) over(partition by species,public.catalog_key(name) order by (show_id is not null) desc,is_recognized desc,created_at,id) keeper from public.breeds;
update public.varieties v set breed_id=m.keeper from breed_merge m where v.breed_id=m.id and m.id<>m.keeper;
delete from public.breeds b using breed_merge m where b.id=m.id and m.id<>m.keeper;
do $$ begin
 if exists(select 1 from public.varieties where show_id is not null group by breed_id,public.catalog_key(name) having count(distinct show_id)>1) then
 raise exception 'Conflicting Show variety identities require review'; end if;
end $$;
create temporary table variety_merge on commit drop as
select id,row_number() over(partition by breed_id,public.catalog_key(name) order by (show_id is not null) desc,is_recognized desc,created_at,id) rank from public.varieties;
delete from public.varieties v using variety_merge m where v.id=m.id and m.rank>1;
-- Recompute stored keys after changing their normalization function.
update public.breeds set name=name;
update public.varieties set name=name;
create unique index breeds_catalog_identity on public.breeds(species,catalog_key);
create unique index varieties_catalog_identity on public.varieties(breed_id,catalog_key);
create unique index breeds_show_identity on public.breeds(show_id) where show_id is not null;
create unique index varieties_show_identity on public.varieties(show_id) where show_id is not null;

create unique index varieties_breed_name_idx on public.varieties(breed_id,lower(name));

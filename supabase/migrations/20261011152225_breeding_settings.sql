create table public.breeding_settings (
 ring_id uuid not null references public.farms(id) on delete restrict,
 species text not null check(species in ('rabbit','cavy')),
 gestation_min integer not null check(gestation_min between 1 and 365),
 gestation_max integer not null check(gestation_max between gestation_min and 365),
 palpation_min integer not null check(palpation_min between 1 and 365),
 palpation_max integer not null check(palpation_max between palpation_min and 365),
 nesting_day integer check(nesting_day between 1 and 365),
 weaning_min integer not null check(weaning_min between 1 and 52),
 weaning_max integer not null check(weaning_max between weaning_min and 52),
 primary key(ring_id,species),
 check(species<>'cavy' or nesting_day is null)
);
alter table public.breeding_settings enable row level security;
revoke all on public.breeding_settings from anon,authenticated;
grant select,insert,update on public.breeding_settings to authenticated;
create policy family_breeding_settings on public.breeding_settings for all to authenticated
 using(exists(select 1 from public.farms f where f.id=ring_id and breeder_private.has_access(f.owner_id) and not coalesce(f.is_demo,false)))
 with check(exists(select 1 from public.farms f where f.id=ring_id and breeder_private.has_access(f.owner_id) and not coalesce(f.is_demo,false)));

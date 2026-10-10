create table public.breeding_records (
 id uuid primary key default gen_random_uuid(),
 sire_id uuid not null references public.animals(id) on delete restrict,
 dam_id uuid not null references public.animals(id) on delete restrict,
 breeding_date date not null,
 notes text not null default '' check (char_length(notes) <= 4000),
 status text not null default 'active' check (status in ('active','completed','cancelled')),
 created_at timestamptz not null default now(),
 check (sire_id <> dam_id),
 unique (sire_id,dam_id,breeding_date)
);
create index breeding_records_dam_date on public.breeding_records(dam_id,breeding_date desc);
alter table public.breeding_records enable row level security;
grant select,insert on public.breeding_records to authenticated;
create policy family_breeding_read on public.breeding_records for select to authenticated
 using (breeder_private.animal_access(sire_id) and breeder_private.animal_access(dam_id));
create policy family_breeding_insert on public.breeding_records for insert to authenticated
 with check (
 status='active' and breeder_private.animal_access(sire_id) and breeder_private.animal_access(dam_id)
 and exists (
 select 1 from public.animals s join public.animals d on d.id=breeding_records.dam_id
 where s.id=breeding_records.sire_id and s.ring_id=d.ring_id and s.species=d.species
 and lower(s.sex) in ('m','male','buck','boar') and lower(d.sex) in ('f','female','doe','sow')
 and s.status='active' and d.status='active'
 and not coalesce(s.pedigree_only,false) and not coalesce(d.pedigree_only,false)
 ));

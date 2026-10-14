-- Preserve historical source records separately from the active breeding workflow.
alter table public.global_pedigree_import_drafts add column history jsonb not null default '[]' check(jsonb_typeof(history)='array' and jsonb_array_length(history)<=20000);
alter table public.global_pedigree_import_drafts add column history_complete boolean not null default false;
create table public.global_pedigree_history (
 id uuid primary key default gen_random_uuid(),
 ring_id uuid not null references public.farms(id) on delete cascade,
 source_account text not null check(length(source_account)<=200),
 kind text not null check(kind in ('litter','weight','show')),
 source_id text not null check(length(source_id) between 1 and 200),
 animal_id uuid not null references public.animals(id) on delete cascade,
 sire_id uuid references public.animals(id) on delete set null,
 record jsonb not null check(jsonb_typeof(record)='object' and octet_length(record::text)<=50000),
 imported_at timestamptz not null default now(),
 unique(ring_id,source_account,kind,source_id)
);
create index global_pedigree_history_animal on public.global_pedigree_history(animal_id);
create index global_pedigree_history_sire on public.global_pedigree_history(sire_id);
alter table public.global_pedigree_history enable row level security;
revoke all on public.global_pedigree_history from public,anon,authenticated;
grant select,insert on public.global_pedigree_history to authenticated;
create policy own_global_pedigree_history_read on public.global_pedigree_history for select to authenticated
 using(exists(select 1 from public.farms f where f.id=global_pedigree_history.ring_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false)));
create policy own_global_pedigree_history_insert on public.global_pedigree_history for insert to authenticated
 with check(exists(select 1 from public.farms f join public.animals a on a.ring_id=f.id where f.id=global_pedigree_history.ring_id and a.id=global_pedigree_history.animal_id and breeder_private.owns(f.owner_id) and not coalesce(f.is_demo,false))
 and (global_pedigree_history.sire_id is null or exists(select 1 from public.animals a where a.id=global_pedigree_history.sire_id and a.ring_id=global_pedigree_history.ring_id)));
create function public.import_global_pedigree_with_history(p_ring uuid,p_account text,p_animals jsonb,p_history jsonb default '[]',p_history_complete boolean default false,p_commit boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb; animals jsonb; r jsonb; aid uuid; sid uuid; wid uuid; dt date; warnings jsonb:='[]'; keys text[]:='{}'; k text; n integer:=0; f jsonb;
begin
 p_commit:=coalesce(p_commit,false);
 perform 1 from public.farms farm where farm.id=p_ring and breeder_private.owns(farm.owner_id) and not coalesce(farm.is_demo,false) for update;
 if not found then raise exception 'Select a herd you own'; end if;
 if jsonb_typeof(p_history) is distinct from 'array' or jsonb_array_length(p_history)>20000 then raise exception 'Invalid history records'; end if;
 -- Validate every record before calling the animal commit. Any later failure rolls back the entire RPC.
 for r in select value from jsonb_array_elements(p_history) loop
  if jsonb_typeof(r) is distinct from 'object' or octet_length(r::text)>50000 or coalesce(r->>'kind','') not in ('litter','weight','show') or length(coalesce(r->>'source_id','')) not between 1 and 200 then raise exception 'Invalid history record'; end if;
  k:=(r->>'kind')||':'||(r->>'source_id');
  if k=any(keys) then raise exception 'Duplicate history source ID'; end if; keys:=array_append(keys,k);
  if not exists(select 1 from jsonb_array_elements(p_animals) a where a->>'source_id'=r->>'animal_source_id') then raise exception 'History animal is missing'; end if;
  if r->>'kind'='litter' and not exists(select 1 from jsonb_array_elements(p_animals) a where a->>'source_id'=r->>'sire_source_id') then raise exception 'History sire is missing'; end if;
  if r->>'kind'='weight' then
   begin dt:=(r->>'recorded_date')::date; exception when others then raise exception 'Invalid history weight date'; end;
   if dt is null or dt>current_date or coalesce((r->>'weight')::numeric,0)<=0 or (r->>'weight')::numeric>=1000 then raise exception 'Invalid historical weight'; end if;
  elsif r->>'kind'='litter' then
   f:=coalesce(r->'fields','{}');
   for k in select key from jsonb_each_text(f) where key in ('Date Bred','Date Kindled','Date Weaned') loop
    if nullif(f->>k,'') is null then continue; end if;
    begin
     dt:=to_date(f->>k,'MM/DD/YYYY');
     if to_char(dt,'MM/DD/YYYY')<>f->>k or dt>current_date or dt<date '1980-01-01' then warnings:=warnings||jsonb_build_array('Litter '||(r->>'source_id')||' has a questionable '||k||': '||(f->>k)||'. Preserved as recorded.'); end if;
    exception when others then warnings:=warnings||jsonb_build_array('Litter '||(r->>'source_id')||' has an unreadable '||k||'. Preserved as recorded.'); end;
   end loop;
  end if;
 end loop;
 -- The old snapshot weight has no source date. Complete histories replace that snapshot on new imports.
 select jsonb_agg(case when coalesce(p_history_complete,false) then a-'weight' else a end) into animals from jsonb_array_elements(p_animals) a;
 result:=public.import_global_pedigree(p_ring,p_account,animals,p_commit);
 if result->>'status'='preview' then
  -- Retain original raw data for review/resume, including the animal snapshot.
  update public.global_pedigree_import_drafts set animals=p_animals,history=p_history,history_complete=coalesce(p_history_complete,false) where auth_user_id=auth.uid() and ring_id=p_ring;
 else
  for r in select value from jsonb_array_elements(p_history) loop
   if exists(select 1 from public.global_pedigree_history h where h.ring_id=p_ring and h.source_account=p_account and h.kind=r->>'kind' and h.source_id=r->>'source_id') then continue; end if;
   select g.animal_id into aid from public.global_pedigree_animals g where g.ring_id=p_ring and g.source_account=p_account and g.source_id=r->>'animal_source_id';
   sid:=null; wid:=null;
   if r->>'kind'='litter' then select g.animal_id into sid from public.global_pedigree_animals g where g.ring_id=p_ring and g.source_account=p_account and g.source_id=r->>'sire_source_id'; end if;
   insert into public.global_pedigree_history(ring_id,source_account,kind,source_id,animal_id,sire_id,record)
    values(p_ring,p_account,r->>'kind',r->>'source_id',aid,sid,r);
   if r->>'kind'='weight' then
    insert into public.animal_weights(animal_id,weight,recorded_at) values(aid,(r->>'weight')::numeric,((r->>'recorded_date')||'T12:00:00Z')::timestamptz);
   end if;
   n:=n+1;
  end loop;
 end if;
 return result||jsonb_build_object('history_count',jsonb_array_length(p_history),'history_added',n,'history_warnings',warnings,'history_complete',coalesce(p_history_complete,false),'show_results_available',false);
end $$;
revoke all on function public.import_global_pedigree_with_history(uuid,text,jsonb,jsonb,boolean,boolean) from public,anon;
grant execute on function public.import_global_pedigree_with_history(uuid,text,jsonb,jsonb,boolean,boolean) to authenticated;

-- Imported dated weights are allowed for locked historical animals only when
-- an owner-accessible source history row records exactly the same values.
create or replace function breeder_private.validate_weight() returns trigger
language plpgsql set search_path='' as $$ begin
 if exists(select 1 from public.animals where id=new.animal_id and status in ('sold','deceased'))
 and not exists(select 1 from public.global_pedigree_history h join public.animals a on a.id=h.animal_id join public.farms f on f.id=a.ring_id
 where h.animal_id=new.animal_id and h.kind='weight' and breeder_private.owns(f.owner_id)
 and h.record->>'recorded_date'=to_char(new.recorded_at at time zone 'UTC','YYYY-MM-DD')
 and (h.record->>'recorded_date')::date<=current_date and (h.record->>'weight')::numeric=new.weight)
 then raise exception 'Historical animal is locked'; end if;
 return new;
end; $$;

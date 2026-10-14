create or replace function public.import_global_pedigree_with_history(p_ring uuid,p_account text,p_animals jsonb,p_history jsonb default '[]',p_history_complete boolean default false,p_commit boolean default false)
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
 -- Dated source records replace undated profile snapshots only for the same resolved rabbit. Ancestor profile weights without accessible dates remain available.
 select jsonb_agg(case when coalesce(p_history_complete,false) and exists(select 1 from jsonb_array_elements(p_history) h join jsonb_array_elements(p_animals) original on original->>'source_id'=h->>'animal_source_id' where h->>'kind'='weight' and coalesce(original->>'same_as',original->>'source_id')=coalesce(a->>'same_as',a->>'source_id')) then a-'weight' else a end) into animals from jsonb_array_elements(p_animals) a;
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

-- Phase 1 protocol. Every data action still executes as the signed-in caller;
-- existing table RLS, column grants, quota checks and business triggers apply.
create table public.breeder_offline_receipts (
 actor uuid not null default auth.uid() references auth.users(id) on delete cascade,
 operation_id uuid not null,
 payload_hash text not null,
 result jsonb not null,
 created_at timestamptz not null default now(),
 primary key(actor,operation_id)
);
alter table public.breeder_offline_receipts enable row level security;
revoke all on public.breeder_offline_receipts from public,anon,authenticated;
grant select,insert on public.breeder_offline_receipts to authenticated;
create policy own_offline_receipts on public.breeder_offline_receipts to authenticated
 using(actor=(select auth.uid())) with check(actor=(select auth.uid()));

-- Coarse table versions avoid re-downloading unchanged tables. When a version
-- changes, replace the complete RLS-filtered table, including its deletions.
create table breeder_private.offline_versions(name text primary key,version bigint not null default 1);
revoke all on breeder_private.offline_versions from public,anon,authenticated;
grant select on breeder_private.offline_versions to authenticated;
create function breeder_private.offline_changed() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 insert into breeder_private.offline_versions(name,version) values(tg_table_name,1)
 on conflict(name) do update set version=breeder_private.offline_versions.version+1;
 return null;
end $$;
revoke all on function breeder_private.offline_changed() from public,anon,authenticated;
do $$ declare t text; begin
 foreach t in array array['users','farms','animals','animal_weights','animal_health_records','breeding_settings','breeding_records','breeding_tracking','breeding_offspring','pedigree_drafts','animal_sales','animal_sale_payments','animal_sale_history','breeds','varieties','species','user_licenses','license_tiers','breeder_exhibitor_profiles','breeder_imported_animals','breeder_show_history','global_pedigree_animals','global_pedigree_history','global_pedigree_import_drafts','account_deletions','breeder_legal_acceptances'] loop
  if to_regclass('public.'||t) is not null then
   insert into breeder_private.offline_versions(name) values(t);
   execute format('create trigger breeder_offline_changed after insert or update or delete or truncate on public.%I for each statement execute function breeder_private.offline_changed()',t);
  end if;
 end loop;
end $$;

create function public.breeder_offline_snapshot(p_versions jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare membership jsonb; scope text; v record; rows jsonb; tables jsonb='{}'; versions jsonb='{}'; counts jsonb='{}'; files jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Sign in to download records'; end if;
 if exists(select 1 from public.account_deletions) then raise exception 'Finish the pending account deletion before preparing offline access'; end if;
 membership=public.breeder_family_access('list',null,null);
 scope=md5(membership::text);
 for v in select * from breeder_private.offline_versions order by name loop
  versions=versions||jsonb_build_object(v.name,v.version);
  if p_versions->>'_scope' is distinct from scope or p_versions->>v.name is distinct from v.version::text then
   if v.name='breeder_offline_jobs' then
    execute 'select coalesce(jsonb_agg((to_jsonb(t)-''payload'')||jsonb_build_object(''payload'',t.payload-''pdf''-''approved_snapshot''-''p_animals''-''p_history'')),''[]''::jsonb) from public.breeder_offline_jobs t' into rows;
   else execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from public.%I t',v.name) into rows;end if;
   tables=tables||jsonb_build_object(v.name,rows);
   counts=counts||jsonb_build_object(v.name,jsonb_array_length(rows));
  end if;
 end loop;
 select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket_id,'path',name,'size',coalesce(metadata->>'size','0'),'updated_at',updated_at)),'[]') into files
 from storage.objects where bucket_id in ('animal_photos','health_attachments');
 return jsonb_build_object('protocol',1,'membership',membership,'admin',public.breeder_is_super_admin(),'tables',tables,'versions',versions||jsonb_build_object('_scope',scope),'counts',counts,'files',files);
end $$;
revoke all on function public.breeder_offline_snapshot(jsonb) from public,anon;
grant execute on function public.breeder_offline_snapshot(jsonb) to authenticated;

-- Stable IDs for RPC-created records. Ordinary online calls keep random IDs.
-- The seed is scoped to this transaction and reset on each receipt attempt.
create function breeder_private.next_offline_id() returns uuid
language plpgsql volatile security invoker set search_path='' as $$
declare seed text=current_setting('breeder.offline_seed',true); n integer;
begin
 if coalesce(seed,'')='' then return gen_random_uuid(); end if;
 n=coalesce(nullif(current_setting('breeder.offline_seq',true),''),'0')::integer+1;
 perform set_config('breeder.offline_seq',n::text,true);
 return left(encode(extensions.digest(seed||':'||n::text,'sha256'),'hex'),32)::uuid;
end $$;
revoke all on function breeder_private.next_offline_id() from public,anon;
grant execute on function breeder_private.next_offline_id() to authenticated;
-- Preserve the current validated implementations rather than duplicating their
-- business rules in a second server API. Only generated IDs are supplied.
do $$ declare f record; definition text; replacement text; begin
 for f in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='public' and p.proname in ('create_animal_with_color_details','save_pedigree_draft','record_breeding_with_parents','create_litter_animals'))
 or (n.nspname='breeder_private' and p.proname='create_ring') loop
  definition=pg_get_functiondef(f.oid);
  replacement=regexp_replace(definition,
   '(insert into public\.(?:animals|animal_weights|farms|breeding_records)\s*\()([^;]+?\)\s*values\s*\()',
   '\1id,\2breeder_private.next_offline_id(),','gi');
  if replacement=definition then raise exception 'Unable to adapt offline IDs for %',f.oid::regprocedure; end if;
  execute replacement;
 end loop;
end $$;
-- Draft ownership is still the auth.uid() default, checked by existing RLS.
grant insert(id) on public.pedigree_drafts to authenticated;

create function public.breeder_offline_apply(p_operation jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare oid uuid; request jsonb; m jsonb; e jsonb; actual jsonb; compared jsonb; current_rows jsonb='[]'; conflict boolean=false;
 t text; action text; value jsonb; fields text; assignments text; result jsonb; saved public.breeder_offline_receipts;
 f record; arg record; arguments text=''; matched integer; allowed text[]; k text; target text; fingerprint text;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Sign in to sync'; end if;
 oid=(p_operation->>'id')::uuid;request=p_operation->'request';
 if pg_column_size(p_operation)>(case when request->>'type'='rpc' and request->>'target'='import_global_pedigree_with_sales' then 16000000 else 2000000 end) then raise exception 'This record operation is too large'; end if;
 fingerprint=encode(extensions.digest(p_operation::text,'sha256'),'hex');
 if oid is null or jsonb_typeof(request)<>'object' then raise exception 'Invalid offline operation'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':'||oid::text,0));
 select * into saved from public.breeder_offline_receipts where actor=auth.uid() and operation_id=oid;
 if found then
  if saved.payload_hash<>fingerprint then raise exception 'A different operation already uses this ID'; end if;
  return saved.result;
 end if;
 if exists(select 1 from public.account_deletions) then raise exception 'Account deletion is pending. Your draft is retained.'; end if;
 target=request->>'target';
 if request->>'type'='table' then
  if target is null or target not in ('farms','users','animals','animal_weights','animal_health_records','breeding_settings','pedigree_drafts','global_pedigree_import_drafts','animal_sales','animal_sale_payments')
   or request->>'method' is null or request->>'method' not in ('POST','PATCH','DELETE') then raise exception 'Unsupported offline table action'; end if;
  if request->>'method'='DELETE' and target not in ('animal_health_records','pedigree_drafts','global_pedigree_import_drafts') then raise exception 'This deletion requires a connection'; end if;
 elsif request->>'type'='rpc' then
  if target is null or target not in ('create_animal_with_color_details','create_breeder_ring','record_breeding_with_parents','save_breeding_tracking','create_litter_animals','save_pedigree_draft','import_global_pedigree_with_sales') then raise exception 'Unsupported offline action'; end if;
 else raise exception 'Unsupported offline action type'; end if;

 for e in select item.value from jsonb_array_elements(coalesce(p_operation->'expects','[]')) item loop
  t=e->>'table';
  if t not in ('farms','users','animals','animal_weights','animal_health_records','breeding_settings','breeding_records','breeding_tracking','pedigree_drafts','global_pedigree_import_drafts','animal_sales') then raise exception 'Unsupported conflict check'; end if;
  execute format('select to_jsonb(t) from public.%I t where to_jsonb(t) @> $1 for update',t) into actual using e->'key';
  current_rows=current_rows||jsonb_build_array(jsonb_build_object('table',t,'key',e->'key','row',actual));
  if actual is null then conflict=true;
  else
   -- Normalize typed timestamps/numerics exactly as the real table does; a
   -- provisional ISO timestamp may use Z where Postgres returns +00:00.
   execute format('select to_jsonb(x) from jsonb_populate_record(null::public.%I,$1) x',t) into compared using e->'before';
   for k in select jsonb_object_keys(e->'before') loop
    -- A retry with the same final value is already satisfied.
    if coalesce(actual->k,'null') is distinct from compared->k
    and not exists(select 1 from jsonb_array_elements(coalesce(p_operation->'mutations','[]')) x
     where x->>'table'=t and x->'row' @> (e->'key') and x->'row' ? k and x->'row'->k=actual->k) then conflict=true; end if;
   end loop;
  end if;
 end loop;
 if conflict then return jsonb_build_object('state','conflict','current',current_rows); end if;
 perform set_config('breeder.offline_seed',coalesce(p_operation->>'seed',oid::text),true);
 perform set_config('breeder.offline_seq','0',true);
 if request->>'type'='rpc' then
  select p.oid,p.proargnames,p.proargtypes,p.pronargs into strict f from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=target;
  for arg in select u.name,u.type from unnest(f.proargnames,f.proargtypes::oid[]) as u(name,type) loop
   if request->'body' ? arg.name then
    if arguments<>'' then arguments=arguments||','; end if;
    if arg.type='jsonb'::regtype then arguments=arguments||format('%I := ($1->''body''->%L)::jsonb',arg.name,arg.name);
    else arguments=arguments||format('%I := ($1->''body''->>%L)::%s',arg.name,arg.name,format_type(arg.type,null));end if;
   end if;
  end loop;
  if exists(select 1 from jsonb_object_keys(request->'body') x where not(x=any(f.proargnames))) then raise exception 'Unsupported action argument';end if;
  execute format('select to_jsonb(public.%I(%s))',target,arguments) into result using request;
 else
  result='[]';
  for m in select item.value from jsonb_array_elements(p_operation->'mutations') item loop
   if coalesce((m->>'derived')::boolean,false) then continue;end if;
   t=m->>'table';action=m->>'action';
   if t<>target then raise exception 'The saved request contains unrelated table changes';end if;
   if action not in ('insert','update','delete') then raise exception 'Unsupported saved mutation';end if;
   -- The original request's field list governs server writes; display defaults
   -- in provisional rows cannot grant access to protected columns.
   if jsonb_typeof(request->'body')='array' then
    select coalesce(jsonb_object_agg(kv.k,kv.v),'{}') into e from jsonb_each(m->'row') kv(k,v)
    where kv.k=any(case t when 'breeding_settings' then array['ring_id','species'] when 'global_pedigree_import_drafts' then array['auth_user_id','ring_id'] else array['id'] end);
    select x into strict value from jsonb_array_elements(request->'body') x where x @> e;
   else value=request->'body';end if;
   if action='insert' then
    value=coalesce(value,'{}')||jsonb_build_object('id',m->'row'->'id');
    if not(m->'row' ? 'id') then value=value-'id';end if;
    select string_agg(format('%I',name),',') into fields from jsonb_object_keys(value) name;
    execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I,$1) returning to_jsonb(%I.*)',t,fields,fields,t,t) into actual using value;
   else
    select coalesce(jsonb_object_agg(kv.k,kv.v),'{}') into e from jsonb_each(m->'row') kv(k,v)
     where kv.k=any(case t when 'global_pedigree_import_drafts' then array['auth_user_id','ring_id'] when 'breeding_settings' then array['ring_id','species'] when 'breeding_tracking' then array['breeding_id'] else array['id'] end);
    if e='{}' then raise exception 'Missing saved record identity';end if;
    if action='delete' then
     if request->>'method'<>'DELETE' then raise exception 'Unexpected deletion';end if;
     execute format('delete from public.%I t where to_jsonb(t) @> $1 returning to_jsonb(t)',t) into actual using e;
    else
     select string_agg(format('%I=(jsonb_populate_record(null::public.%I,$1)).%I',name,t,name),',') into assignments from jsonb_object_keys(value) name;
     execute format('update public.%I t set %s where to_jsonb(t) @> $2 returning to_jsonb(t)',t,assignments) into actual using value,e;
    end if;
    if actual is null then raise insufficient_privilege using message='Access ended or the record is no longer editable';end if;
   end if;
   result=result||jsonb_build_array(actual);
  end loop;
 end if;
 result=jsonb_build_object('state','applied','result',result);
 insert into public.breeder_offline_receipts(actor,operation_id,payload_hash,result) values(auth.uid(),oid,fingerprint,result);
 return result;
end $$;
revoke all on function public.breeder_offline_apply(jsonb) from public,anon;
grant execute on function public.breeder_offline_apply(jsonb) to authenticated;

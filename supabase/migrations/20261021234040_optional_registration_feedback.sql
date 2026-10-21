-- Optional survey answers are private to the member and super administrators.
create table breeder_private.registration_settings (
 singleton boolean primary key default true check(singleton),
 launched_at timestamptz not null default now()
);
insert into breeder_private.registration_settings(singleton) values(true);
create table public.breeder_registration_feedback (
 owner_id text primary key references public.users(id) on delete cascade,
 referral_code text not null unique default ('RM-'||upper(encode(extensions.gen_random_bytes(6),'hex'))),
 herd_tracking text not null default '' check(length(herd_tracking)<=1000),
 referred_by text not null default '' check(length(referred_by)<=254),
 referrer_owner_id text references public.users(id) on delete set null,
 requested_features text not null default '' check(length(requested_features)<=4000),
 onboarding_seen_at timestamptz,
 answered_at timestamptz,
 updated_at timestamptz not null default now(),
 check(referrer_owner_id is null or referrer_owner_id<>owner_id)
);
create index breeder_registration_referrer on public.breeder_registration_feedback(referrer_owner_id) where referrer_owner_id is not null;
create index breeder_registration_recent on public.breeder_registration_feedback(updated_at desc,owner_id);
alter table breeder_private.registration_settings enable row level security;
alter table public.breeder_registration_feedback enable row level security;
revoke all on breeder_private.registration_settings,public.breeder_registration_feedback from public,anon,authenticated;
grant all on breeder_private.registration_settings,public.breeder_registration_feedback to service_role;

create function breeder_private.registration_feedback(p_action text,p_answers jsonb,p_offset integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor text; r public.breeder_registration_feedback; referral text; matched text; rows jsonb;
begin
 actor:=breeder_private.ensure_identity();
 if p_action='admin-list' then
  if not public.breeder_is_super_admin() then raise exception 'Administrator access required'; end if;
  if p_offset is null or p_offset<0 or p_offset>1000000 then raise exception 'Invalid page'; end if;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into rows from (
   select f.owner_id,u.display_name,u.email,u.created_at as joined_at,f.herd_tracking,f.referred_by,
    f.requested_features,f.answered_at,f.updated_at,f.referral_code,
    ref.display_name as referrer_name,ref.email as referrer_email,
    (select count(*) from public.breeder_registration_feedback f2 join public.users u2 on u2.id=f2.owner_id where f2.referrer_owner_id=f.owner_id and u2.is_active) as referred_signups
   from public.breeder_registration_feedback f join public.users u on u.id=f.owner_id
   left join public.users ref on ref.id=f.referrer_owner_id
   where f.answered_at is not null order by f.updated_at desc,f.owner_id limit 50 offset p_offset
  ) x;
  insert into breeder_private.support_audit(actor_id,target_owner_id,action) values(auth.uid(),'all-registration-responses','registration_insights');
  return jsonb_build_object('responses',rows,'more',jsonb_array_length(rows)=50);
 end if;
 if p_action is null or p_action not in ('status','save','skip') then raise exception 'Unknown feedback action'; end if;
 insert into public.breeder_registration_feedback(owner_id) values(actor) on conflict(owner_id) do nothing;
 select * into strict r from public.breeder_registration_feedback where owner_id=actor for update;
 if p_action='save' then
  if p_answers is null or jsonb_typeof(p_answers)<>'object' then raise exception 'Invalid answers'; end if;
  if length(coalesce(p_answers->>'herd_tracking',''))>1000 or length(coalesce(p_answers->>'referred_by',''))>254 or length(coalesce(p_answers->>'requested_features',''))>4000 then raise exception 'Please shorten your answers'; end if;
  referral:=btrim(coalesce(p_answers->>'referred_by',''));
  -- A self-reported referral is not a reward. Freeze attribution after it is supplied.
  if r.referred_by<>'' and referral<>r.referred_by then raise exception 'Your original referral is already recorded. Contact support to correct it.'; end if;
  if r.referred_by='' and referral<>'' then
   select u.id into matched from public.users u join auth.users au on au.id=u.auth_user_id
   left join public.breeder_registration_feedback f on f.owner_id=u.id
   where u.id<>actor and u.is_active and au.email_confirmed_at is not null and au.deleted_at is null
    and (lower(btrim(au.email))=lower(referral) or upper(f.referral_code)=upper(referral)) limit 1;
  else matched:=r.referrer_owner_id; end if;
  update public.breeder_registration_feedback set herd_tracking=btrim(coalesce(p_answers->>'herd_tracking','')),
   referred_by=referral,referrer_owner_id=matched,requested_features=btrim(coalesce(p_answers->>'requested_features','')),
   onboarding_seen_at=coalesce(onboarding_seen_at,now()),answered_at=now(),updated_at=now()
   where owner_id=actor returning * into r;
 elsif p_action='skip' then
  update public.breeder_registration_feedback set onboarding_seen_at=coalesce(onboarding_seen_at,now()) where owner_id=actor returning * into r;
 end if;
 return jsonb_build_object('herd_tracking',r.herd_tracking,'referred_by',r.referred_by,'requested_features',r.requested_features,
  'referral_code',r.referral_code,'referral_recorded',r.referred_by<>'',
  'referred_signups',(select count(*) from public.breeder_registration_feedback f join public.users u on u.id=f.owner_id where f.referrer_owner_id=actor and u.is_active),
  'show_onboarding',r.onboarding_seen_at is null and exists(select 1 from public.users u cross join breeder_private.registration_settings s where u.id=actor and u.created_at>=s.launched_at));
end $$;
revoke all on function breeder_private.registration_feedback(text,jsonb,integer) from public,anon;
grant execute on function breeder_private.registration_feedback(text,jsonb,integer) to authenticated,service_role;
create function public.breeder_registration_feedback(p_action text default 'status',p_answers jsonb default '{}'::jsonb,p_offset integer default 0) returns jsonb
language sql security invoker set search_path='' as $$select breeder_private.registration_feedback(p_action,p_answers,p_offset)$$;
revoke all on function public.breeder_registration_feedback(text,jsonb,integer) from public,anon;
grant execute on function public.breeder_registration_feedback(text,jsonb,integer) to authenticated,service_role;

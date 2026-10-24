-- Restrict inherited Supabase default EXECUTE grants as well as PUBLIC grants.
-- The functions continue to run as the caller under the existing table RLS.
revoke all on function public.save_breeding_tracking(uuid,jsonb,integer),
 public.create_litter_animals(uuid,jsonb) from public,anon;
grant execute on function public.save_breeding_tracking(uuid,jsonb,integer),
 public.create_litter_animals(uuid,jsonb) to authenticated;

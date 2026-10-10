revoke all on public.pedigree_drafts from public,anon,authenticated;
grant select,delete on public.pedigree_drafts to authenticated;
grant insert(ring_id,data),update(data,updated_at) on public.pedigree_drafts to authenticated;

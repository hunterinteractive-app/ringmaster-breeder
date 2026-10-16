-- Add a monotonic revision without changing existing fields or permissions.
-- Clients compare the revision they originally loaded in the UPDATE predicate.
alter table public.animals add column revision bigint not null default 1;
create function breeder_private.advance_animal_revision() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if tg_op='INSERT' then new.revision:=1;
  else new.revision:=old.revision+1;
  end if;
  return new;
end;
$$;
revoke all on function breeder_private.advance_animal_revision() from public,anon,authenticated;
create trigger animal_revision before insert or update on public.animals
for each row execute function breeder_private.advance_animal_revision();

grant update(weight) on public.animal_weights to authenticated;
create policy family_weights_edit_latest on public.animal_weights
for update to authenticated
using (
 breeder_private.animal_access(animal_id)
 and exists (select 1 from public.animals a where a.id=animal_id and a.status not in ('sold','deceased'))
 and id=(select w.id from public.animal_weights w where w.animal_id=animal_weights.animal_id order by w.recorded_at desc,w.id desc limit 1)
)
with check (breeder_private.animal_access(animal_id) and weight > 0 and weight <> 'NaN'::numeric);

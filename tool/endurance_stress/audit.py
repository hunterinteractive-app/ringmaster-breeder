#!/usr/bin/env python3
"""Independent post-run SQL audit of retry saves and fixture integrity."""
import json
from common import ROOT,evidence,sql

def scalar(query):return int(sql(query).stdout.strip())
isolation=json.loads((ROOT/'deliverables/scaling-fixes/multiuser-isolation-results.json').read_text())
ids=[key for row in isolation['results'] for key in row['ids']]
audit={
 'logical_duplicate_weight_groups':scalar("select count(*) from (select animal_id,recorded_at,weight from public.animal_weights where weight in (4.75,4.8) group by animal_id,recorded_at,weight having count(*)>1) d;"),
 'remaining_temporary_future_rows':scalar("select count(*) from public.animal_health_records where id in (select md5('rmb-future-feed-boundary-'||i)::uuid from generate_series(1,14000) i) or id=md5('rmb-next-calendar-sentinel')::uuid;"),
 'invalid_animal_revisions':scalar('select count(*) from public.animals where revision<1 or revision is null;'),
 'unauthorized_or_partial_weight_rows':scalar("select count(*) from public.animal_weights where id in ('"+"','".join(ids)+"');"),
 'animals':scalar('select count(*) from public.animals;'),
 'health_records':scalar('select count(*) from public.animal_health_records;'),
 'breeding_records':scalar('select count(*) from public.breeding_records;'),
 'weight_records':scalar('select count(*) from public.animal_weights;'),
}
audit['passed']=(all(audit[key]==0 for key in ['logical_duplicate_weight_groups','remaining_temporary_future_rows','invalid_animal_revisions','unauthorized_or_partial_weight_rows'])
 and audit['animals']==50000 and audit['health_records']==496000 and audit['breeding_records']==118000 and audit['weight_records']>=376000)
evidence('endurance-data-audit.json',audit)
print(json.dumps(audit),flush=True)
assert audit['passed'],audit

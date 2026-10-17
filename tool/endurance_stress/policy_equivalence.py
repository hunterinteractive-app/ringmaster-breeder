#!/usr/bin/env python3
"""Compare the old and cached access predicates for every synthetic animal/identity."""
import json
from common import evidence,sql

actors=sql("select id from auth.users where email like '%@example.invalid' order by id;").stdout.splitlines()
actors.append(None)
comparisons=0
for index,actor in enumerate(actors):
 value=actor or ''
 data=sql("begin; select set_config('request.jwt.claim.sub','"+value+"',true); select count(*)||','||count(*) filter(where breeder_private.animal_access(a.id) is distinct from (a.ring_id=any(array(select breeder_private.accessible_rings())))) from public.animals a; rollback;").stdout.strip().splitlines()[-1]
 count,different=map(int,data.split(','))
 assert different==0,(index,different)
 comparisons+=count
 print(json.dumps({'identities_checked':index+1,'animal_identity_comparisons':comparisons,'differences':0}),flush=True)
evidence('policy-equivalence-results.json',{'passed':True,'identities_including_unauthenticated':len(actors),'animal_identity_comparisons':comparisons,'differences':0,
 'method':'Compare original animal_access(uuid) with cached-ring membership over all 50000 synthetic animals for each identity; request identity changes before each statement.'})

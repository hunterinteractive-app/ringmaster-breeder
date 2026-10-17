#!/usr/bin/env python3
"""Verify every synthetic family denies foreign reads and atomic mixed-family writes."""
import concurrent.futures
import json
from pathlib import Path
import uuid
from common import evidence, login, request, sql

identities=json.loads(Path('/private/tmp/rmb-next-stress/multi-identities.json').read_text())


def check(identity):
    token=login(identity['email'])
    foreign=identities[(identity['index']+1)%len(identities)]
    status,rows,_,_=request('/rest/v1/animals?select=id&ring_id=eq.'+foreign['ring']+'&limit=1',token)
    assert status==200 and rows==[], (identity['label'],status,rows)
    first,second=str(uuid.uuid4()),str(uuid.uuid4())
    status,error,_,_=request('/rest/v1/animal_weights',token,method='POST',body=[
        {'id':first,'animal_id':identity['animal'],'weight':4.7},
        {'id':second,'animal_id':foreign['animal'],'weight':4.7}])
    assert status==403 and error['code']=='42501',(status,error)
    return {'breeder':identity['label'],'foreign_reads':0,'mixed_family_insert_status':status,'ids':[first,second]}


with concurrent.futures.ThreadPoolExecutor(8) as pool:
    results=list(pool.map(check,identities))
ids=[i for result in results for i in result['ids']]
count=int(sql("select count(*) from animal_weights where id in ("+','.join("'"+i+"'" for i in ids)+");").stdout)
assert count==0, 'Unauthorized or partial mixed-family writes persisted'
output={'passed':True,'families':len(results),'foreign_rows_exposed':0,'partial_or_unauthorized_writes':count,
        'rejected_weight_rows':len(ids),'results':results}
evidence('multiuser-isolation-results.json',output)
print(json.dumps({k:v for k,v in output.items() if k!='results'}),flush=True)

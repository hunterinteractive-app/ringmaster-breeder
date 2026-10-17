#!/usr/bin/env python3
"""Exercise the fixed feed in real oneshot workers with the unchanged 2s CPU limit."""
import hashlib
import json
from pathlib import Path
from icalendar import Calendar
from common import ROOT,evidence,request,sql,uid

copy=Path('/private/tmp/rmb-next-stress/supabase/functions/calendar-feed/calendar.mjs')
source=(ROOT/'supabase/functions/calendar-feed/calendar.mjs').read_text()
assert copy.read_text()==source, 'Local function copy differs from tested source'
animal=uid('rmb-scale-animal-1')
ids="md5('rmb-future-feed-boundary-'||i)::uuid"
sql("begin; select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000001',true); insert into animal_health_records(id,animal_id,record_type,title,administered_date,readminister_date,retention) select "+ids+",'"+animal+"','health','Synthetic distant future capacity '||i,'1999-01-01','2035-12-01','never' from generate_series(1,14000) i; commit;")
results=[]
try:
 link=json.loads(Path('/private/tmp/rmb-next-stress/test-subscription.json').read_text())['token']
 for attempt in range(3):
  status,raw,_,ms=request('/functions/v1/calendar-feed?token='+link,timeout=90)
  result={'implementation':'fixed_function','attempt':attempt+1,'worker_policy':'oneshot','cpu_hard_limit_ms':2000,
   'status':status,'milliseconds':ms,'response_bytes':len(raw.encode()) if isinstance(raw,str) else len(json.dumps(raw)),
   'error':raw if status!=200 else None}
  results.append(result)
  if status==200:
   rows=Calendar.from_ical(raw).walk('VEVENT')
   assert len(rows)>20000
   assert all(e.decoded('DTSTART').isoformat()>='2026-09-01' for e in rows)
   count=sum(str(e.get('SUMMARY','')).startswith('Follow-up due • Synthetic distant future capacity ') for e in rows)
   assert count==14000,count
   maximum=max(len(l.encode()) for l in raw.split('\r\n'))
   assert maximum<=75
   keys=[str(e['UID']) for e in rows]
   assert len(keys)==len(set(keys))
   result.update({'events':len(rows),'future_fixture_events':count,'old_history_excluded':True,
     'future_2035_retained':True,'max_line_bytes':maximum,'unique_uids':True})
  evidence('calendar-large-feed-results.json',{'future_fixture_rows':14000,'attempts':results,
   'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'passed':all(r['status']==200 for r in results)})
  print(json.dumps(result),flush=True)
  assert status==200,(status,raw)
finally:
 sql("delete from animal_health_records where id in (select "+ids+" from generate_series(1,14000) i);")

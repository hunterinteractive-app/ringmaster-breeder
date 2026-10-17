#!/usr/bin/env python3
"""EXPLAIN the actual API calendar query under the real authenticated role; local only."""
from datetime import date,timedelta
from urllib.parse import urlencode
from common import RING,STATUS,evidence,login,request,sql

sql("alter role authenticator set pgrst.db_plan_enabled=true; notify pgrst,'reload config';")
today=date.today().replace(day=1)
start=(today-timedelta(days=1)).replace(day=1)
end=date(today.year+(today.month+1)//12,(today.month+1)%12+1,1)
token=login('scale-owner@example.invalid')
plans=[]
try:
 for label,actor,upper in [('app_authenticated',token,end),('feed_service_role',STATUS['SERVICE_ROLE_KEY'],None)]:
  dates=[]
  for field in ['administered_date','readminister_date','expires_date']:
   dates.append(f'and({field}.gte.{start},{field}.lt.{upper})' if upper else f'{field}.gte.{start}')
  params={'select':('*,animal:animals!inner(id,name,tattoo,ring_id)' if upper else 'id,title,record_type,administered_date,readminister_date,expires_date,animal:animals!inner(id,name,tattoo,ring_id)'),
    'animal.ring_id':'eq.'+RING,'or':'('+','.join(dates)+')','order':'id.asc','offset':0,'limit':500}
  status,data,_,ms=request('/rest/v1/animal_health_records?'+urlencode(params),actor,
    headers={'Accept':'application/vnd.pgrst.plan+json; options=analyze|buffers|verbose'})
  assert status==200,(status,data)
  plans.append({'test':label,'wall_ms':ms,'plan':data})
  print({'test':label,'wall_ms':ms,'execution_ms':data[0].get('Execution Time')},flush=True)
 params={'select':'*,dam:animals!breeding_records_dam_id_fkey!inner(*),sire:animals!breeding_records_sire_id_fkey(*),tracking:breeding_tracking(*),offspring:breeding_offspring(*)',
  'dam.ring_id':'eq.'+RING,'breeding_date':'gte.'+str(start-timedelta(days=72)),
  'and':'(breeding_date.lt.'+str(end)+')','order':'id.asc','offset':0,'limit':500}
 status,data,_,ms=request('/rest/v1/breeding_records?'+urlencode(params),token,
  headers={'Accept':'application/vnd.pgrst.plan+json; options=analyze|buffers|verbose'})
 assert status==200,(status,data)
 plans.append({'test':'app_breeding_authenticated','wall_ms':ms,'plan':data})
 print({'test':'app_breeding_authenticated','wall_ms':ms,'execution_ms':data[0].get('Execution Time')},flush=True)
 evidence('calendar-api-query-plans.json',plans)
finally:
 sql("alter role authenticator reset pgrst.db_plan_enabled; notify pgrst,'reload config';")

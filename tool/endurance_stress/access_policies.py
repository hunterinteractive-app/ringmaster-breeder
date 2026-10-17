#!/usr/bin/env python3
"""HTTP regression checks for cached family scope; every mutation stays in the disposable fixture."""
import json
from pathlib import Path
import uuid
from common import RING,evidence,login,request,sql,uid

identities=json.loads(Path('/private/tmp/rmb-next-stress/multi-identities.json').read_text())
owner=login('scale-owner@example.invalid')
member=login('scale-member@example.invalid')
outsider=login('scale-outsider@example.invalid')
other=identities[-1]
other_token=login(other['email'])
animal=uid('rmb-scale-animal-1')
foreign=other['animal']
health=sql("select id from public.animal_health_records where animal_id='"+animal+"' limit 1;").stdout.strip()
results=[]

def read(table,token,field,value,visible):
 status,data,_,_=request('/rest/v1/'+table+'?select=*&'+field+'=eq.'+value+'&limit=1',token)
 assert status==200,(table,status,data)
 assert bool(data)==visible,(table,visible,data)

def access(token,visible):
 for table,field,value in [('animals','id',animal),('animal_weights','animal_id',animal),
                           ('animal_health_records','animal_id',animal),('breeding_records','dam_id',animal)]:
  # The first animal is a sire; use a known dam for the breeding check.
  if table=='breeding_records':
   value=sql("select b.dam_id from public.breeding_records b join public.animals a on a.id=b.dam_id where a.ring_id='"+RING+"' limit 1;").stdout.strip()
  read(table,token,field,value,visible)

access(owner,True);access(member,True);access(outsider,False)
results.append('owner and accepted member can read; outsider cannot read animals, weights, health, or breeding')
sql("update breeder_private.invitations set revoked_at=now() where member_user_id='e1000000-0000-4000-8000-000000000002';")
try: access(member,False)
finally: sql("update breeder_private.invitations set revoked_at=null where member_user_id='e1000000-0000-4000-8000-000000000002';")
results.append('revoked membership takes effect on the next request')
sql("update breeder_private.invitations set accepted_at=null where member_user_id='e1000000-0000-4000-8000-000000000002';")
try: access(member,False)
finally: sql("update breeder_private.invitations set accepted_at=now() where member_user_id='e1000000-0000-4000-8000-000000000002';")
results.append('unaccepted membership grants no access')
for toggle,restore in [
 ("update public.users set is_active=false where id=(select owner_id from public.farms where id='"+other['ring']+"');",
  "update public.users set is_active=true where id=(select owner_id from public.farms where id='"+other['ring']+"');"),
 ("update public.farms set is_demo=true where id='"+other['ring']+"';",
  "update public.farms set is_demo=false where id='"+other['ring']+"';")]:
 sql(toggle)
 try:
  for table,field in [('animals','id'),('animal_weights','animal_id'),('animal_health_records','animal_id')]:
   read(table,other_token,field,foreign,False)
 finally: sql(restore)
results.append('inactive owners and demo herds grant no animal or history access')
status,data,_,_=request('/rest/v1/animal_health_records?id=eq.'+health,owner,method='PATCH',body={'animal_id':foreign})
assert status==403 and data['code']=='42501',(status,data)
assert sql("select animal_id from public.animal_health_records where id='"+health+"';").stdout.strip()==animal
results.append('moving a health record into another family is rejected without changing it')
ids=[str(uuid.uuid4()),str(uuid.uuid4())]
status,data,_,_=request('/rest/v1/animal_health_records',owner,method='POST',body=[
 {'id':key,'animal_id':a,'title':'Synthetic atomic scope test','record_type':'health','administered_date':'2026-10-01','retention':'never'}
 for key,a in zip(ids,[animal,foreign])])
assert status==403 and data['code']=='42501',(status,data)
assert sql("select count(*) from public.animal_health_records where id in ('"+"','".join(ids)+"');").stdout.strip()=='0'
results.append('mixed-family health writes fail atomically')
status,data,_,_=request('/rest/v1/animals?id=eq.'+animal,owner,method='PATCH',body={'ring_id':other['ring']})
assert status==403 and data['code']=='42501',(status,data)
assert sql("select ring_id from public.animals where id='"+animal+"';").stdout.strip()==RING
results.append('moving an animal into another family is rejected')
temporary=str(uuid.uuid4())
try:
 status,data,_,_=request('/rest/v1/animal_health_records',member,method='POST',body={
  'id':temporary,'animal_id':animal,'title':'Synthetic member write','record_type':'health',
  'administered_date':'2010-01-01','retention':'never'})
 assert status==201,(status,data)
 status,data,_,_=request('/rest/v1/animal_health_records?id=eq.'+temporary,member,method='PATCH',body={'title':'Synthetic member edit'})
 assert status==204,(status,data)
 read('animal_health_records',owner,'id',temporary,True)
 assert sql("select title from public.animal_health_records where id='"+temporary+"';").stdout.strip()=='Synthetic member edit'
 status,data,_,_=request('/rest/v1/animal_health_records?id=eq.'+temporary,member,method='DELETE')
 assert status==204,(status,data)
 read('animal_health_records',owner,'id',temporary,False)
finally:
 sql("delete from public.animal_health_records where id='"+temporary+"';")
results.append('accepted members can create, update and delete their family health records')
cross=str(uuid.uuid4())
invitation=str(uuid.uuid4())
dam=sql("select b.dam_id from public.breeding_records b join public.animals a on a.id=b.dam_id where a.ring_id='"+RING+"' limit 1;").stdout.strip()
try:
 sql("insert into public.breeding_records(id,sire_id,dam_id,breeding_date) values('"+cross+"','"+foreign+"','"+dam+"','2035-12-01');")
 for actor in [owner,member,other_token]:
  read('breeding_records',actor,'id',cross,False)
 sql("insert into breeder_private.invitations(id,owner_id,email,member_user_id,accepted_at) select '"+invitation+"',owner_id,'scale-member@example.invalid','e1000000-0000-4000-8000-000000000002',now() from public.farms where id='"+other['ring']+"';")
 read('animals',member,'id',animal,True)
 read('animals',member,'id',foreign,True)
 read('breeding_records',member,'id',cross,True)
 sql("update breeder_private.invitations set revoked_at=now() where id='"+invitation+"';")
 read('animals',member,'id',animal,True)
 read('animals',member,'id',foreign,False)
 read('breeding_records',member,'id',cross,False)
finally:
 sql("delete from public.breeding_records where id='"+cross+"'; delete from breeder_private.invitations where id='"+invitation+"';")
results.append('breeding reads require access to both parents; multiple-family scope refreshes after revocation')
attributes=sql("select prosecdef and provolatile='s' and proconfig @> array['search_path=\"\"'] and not has_function_privilege('anon',oid,'execute') and has_function_privilege('authenticated',oid,'execute') from pg_proc where oid='breeder_private.accessible_rings()'::regprocedure;").stdout.strip()
assert attributes=='t',attributes
assert sql("select count(*) from pg_class where oid in ('public.animals'::regclass,'public.animal_weights'::regclass,'public.animal_health_records'::regclass,'public.breeding_records'::regclass) and relrowsecurity;").stdout.strip()=='4'
results.append('helper is private, stable, fixed-search-path; anonymous execution denied; RLS remains enabled')
evidence('access-policy-results.json',{'passed':True,'checks':results})
print(json.dumps({'passed':True,'checks':results}),flush=True)

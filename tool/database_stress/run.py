#!/usr/bin/env python3
"""Real Postgres/API checks against the explicitly named disposable local stack.
No production URLs, tokens, or passwords are accepted by this runner.
"""
import concurrent.futures
import hashlib
import hmac
import json
import base64
from pathlib import Path
import subprocess
import time
import urllib.request
import urllib.error

CONTAINER = 'ringmaster-breeder-scale-test-20261016'
API = 'http://127.0.0.1:56433'
OWNER = 'e1000000-0000-4000-8000-000000000001'
MEMBER = 'e1000000-0000-4000-8000-000000000002'
OUTSIDER = 'e1000000-0000-4000-8000-000000000003'
RING = 'e1000000-0000-4000-8000-000000000010'
SALE = 'e1000000-0000-4000-8000-000000000020'
SECRET = b'ringmaster-breeder-local-scale-test-secret-only-2026'
RESULTS = []

def sql(query, check=True):
    r = subprocess.run(['docker','exec','-i','--env','PGPASSWORD=local-synthetic-test-only',CONTAINER,'psql','-h','127.0.0.1','-X','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1','-Atq'],input=query,text=True,capture_output=True,timeout=90)
    if check and r.returncode:
        raise AssertionError(r.stderr[-1600:])
    return r

def token(actor):
    encode=lambda b:base64.urlsafe_b64encode(b).decode().rstrip('=')
    head=encode(b'{"alg":"HS256","typ":"JWT"}')
    payload=encode(json.dumps({'role':'authenticated','sub':actor,'exp':int(time.time())+3600}).encode())
    message=f'{head}.{payload}'
    return message+'.'+encode(hmac.new(SECRET,message.encode(),hashlib.sha256).digest())

def request(path, actor=OWNER, method='GET', body=None, prefer=None, timeout=45):
    headers={'Authorization':'Bearer '+token(actor),'Content-Type':'application/json'}
    if prefer: headers['Prefer']=prefer
    req=urllib.request.Request(API+path,data=json.dumps(body).encode() if body is not None else None,headers=headers,method=method)
    try:
        with urllib.request.urlopen(req,timeout=timeout) as r:
            text=r.read().decode();return r.status,json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        return e.code,json.loads(e.read().decode())

def check(name, fn):
    start=time.monotonic()
    try:
        detail=fn()
        record={'test':name,'passed':True,'seconds':round(time.monotonic()-start,3),'detail':detail}
    except Exception as error:
        record={'test':name,'passed':False,'seconds':round(time.monotonic()-start,3),'error':str(error)}
    RESULTS.append(record); print(json.dumps(record),flush=True)

def uid(label):
    import uuid
    return str(uuid.UUID(hashlib.md5(label.encode()).hexdigest()))

def setup_extra():
    sql("""begin;
    select set_config('request.jwt.claim.sub','"""+OWNER+"""',true);
    insert into public.animals(id,ring_id,name,tattoo,species,sex,status,pedigree_only)
    select md5('rmb-scale-archive-'||i)::uuid,'"""+RING+"""','Synthetic archived '||i,'ARCHIVE-'||i,'rabbit','Doe','retired',false from generate_series(1,100) i on conflict do nothing;
    commit;""")

def counts():
    r=sql("select json_build_object('animals',(select count(*) from animals where ring_id='"+RING+"'),'weights',(select count(*) from animal_weights),'health',(select count(*) from animal_health_records),'breedings',(select count(*) from breeding_records));")
    values=json.loads(r.stdout.strip());assert values=={'animals':1100,'weights':180000,'health':300000,'breedings':20000},values
    return values

def animals_pages():
    status,first=request('/animals?select=id&ring_id=eq.'+RING+'&order=created_at.desc,id.desc')
    assert status==200 and len(first)==1000,(status,first)
    rows=[];pages=0
    while True:
        status,batch=request('/animals?select=id&ring_id=eq.'+RING+'&order=created_at.desc,id.desc&limit=500&offset='+str(len(rows)))
        assert status==200,(status,batch)
        pages+=1
        if not batch:break
        rows.extend(batch)
    assert len(rows)==1100 and len({r['id'] for r in rows})==1100
    return {'unpaginated_count':len(first),'paginated_count':len(rows),'requests':pages}

def history_isolation():
    timings={}
    for actor,name,expected in [(OWNER,'owner',300),(MEMBER,'member',300),(OUTSIDER,'outsider',0)]:
        start=time.monotonic()
        status,rows=request('/animal_health_records?select=id&animal_id=eq.'+uid('rmb-scale-animal-1')+'&order=administered_date.desc,id.desc',actor)
        assert status==200 and len(rows)==expected,(name,status,rows)
        timings[name]=round((time.monotonic()-start)*1000,1)
    status,rows=request('/animals?select=id&ring_id=eq.'+RING,OUTSIDER)
    assert status==200 and rows==[]
    return {'record_counts':'owner 300 / member 300 / outsider 0','milliseconds':timings}

def invalid_bulk_atomicity():
    before=int(sql("select count(*) from animal_weights where animal_id='"+uid('rmb-scale-animal-1')+"';").stdout)
    body=[{'animal_id':uid('rmb-scale-animal-1'),'weight':4.5},{'animal_id':uid('rmb-scale-animal-1'),'weight':-1}]
    status,data=request('/animal_weights',method='POST',body=body)
    assert status>=400,(status,data)
    after=int(sql("select count(*) from animal_weights where animal_id='"+uid('rmb-scale-animal-1')+"';").stdout)
    assert before==after
    return {'rejected_status':status,'partial_rows':after-before}

def competing_litter_edits():
    bid=uid('rmb-scale-breeding-1')
    def edit(label):return request('/rpc/save_breeding_tracking',method='POST',body={'p_id':bid,'p_data':{'status':'active','check_result':'Not checked','notes':label},'p_revision':0})
    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        results=list(pool.map(edit,['editor A','editor B']))
    assert sum(s==200 or s==204 for s,_ in results)==1,results
    assert sum(s>=400 for s,_ in results)==1,results
    status,rows=request('/breeding_tracking?select=revision&breeding_id=eq.'+bid)
    assert status==200 and rows==[{'revision':1}],(status,rows)
    return {'statuses':[s for s,_ in results],'revision':1}

def competing_sale_edits():
    def edit(label):return request('/animal_sales?id=eq.'+SALE+'&version=eq.1&select=id,version',method='PATCH',body={'notes':label},prefer='return=representation')
    with concurrent.futures.ThreadPoolExecutor(2) as pool:results=list(pool.map(edit,['sale A','sale B']))
    assert all(s==200 for s,_ in results),results
    assert sorted(len(data) for _,data in results)==[0,1],results
    status,rows=request('/animal_sales?id=eq.'+SALE+'&select=version')
    assert rows==[{'version':2}],rows
    return {'updated_rows':[len(data) for _,data in results],'version':2}

def competing_payments():
    def pay(label):return request('/animal_sale_payments',method='POST',body={'id':uid(label),'sale_id':SALE,'kind':'payment','amount_cents':6000})
    with concurrent.futures.ThreadPoolExecutor(2) as pool:results=list(pool.map(pay,['scale-pay-a','scale-pay-b']))
    assert sum(s==201 for s,_ in results)==1,results
    assert sum(s>=400 for s,_ in results)==1,results
    status,rows=request('/animal_sale_payments?sale_id=eq.'+SALE+'&select=amount_cents')
    assert status==200 and rows==[{'amount_cents':6000}],rows
    return {'statuses':[s for s,_ in results],'paid_cents':6000,'price_cents':10000}

def replay_payment():
    status,rows=request('/animal_sale_payments?sale_id=eq.'+SALE+'&select=id,amount_cents')
    existing=rows[0]
    status,data=request('/animal_sale_payments',method='POST',body={**existing,'sale_id':SALE,'kind':'payment'})
    assert status>=400,(status,data)
    status,rows=request('/animal_sale_payments?sale_id=eq.'+SALE+'&select=id')
    assert len(rows)==1
    return {'receipts_after_retry':len(rows)}

def lost_bulk_acknowledgement():
    animal=uid('rmb-scale-animal-4')
    timestamp='2026-10-16T00:17:53.123456Z'
    body=[{'id':uid('rmb-stable-weight-retry'),'animal_id':animal,'weight':4.5,'recorded_at':timestamp}]
    first=request('/animal_weights',method='POST',body=body)
    # Model a committed request whose success acknowledgement never reached the UI.
    # The new UI retains this row ID; the service confirms the existing row.
    second=request('/animal_weights',method='POST',body=body)
    assert first[0]==201 and second[0]==409,(first,second)
    status,rows=request('/animal_weights?animal_id=eq.'+animal+'&recorded_at=eq.'+timestamp+'&select=id')
    count=len(rows)
    # Keep the large-history fixture count unchanged for the remaining checks.
    sql("delete from animal_weights where animal_id='"+animal+"' and recorded_at='"+timestamp+"';")
    assert count==1, f'Lost-ack retry created {count} records for one logical weight entry; expected 1'
    return {'records_after_retry':count}

def competing_animal_edits():
    animal=uid('rmb-scale-animal-3')
    status,snapshot=request('/animals?id=eq.'+animal+'&select=revision')
    revision=snapshot[0]['revision']
    def edit(label):return request('/animals?id=eq.'+animal+'&revision=eq.'+str(revision)+'&select=name',method='PATCH',body={'name':label},prefer='return=representation')
    with concurrent.futures.ThreadPoolExecutor(2) as pool:results=list(pool.map(edit,['Concurrent editor A','Concurrent editor B']))
    successes=sum(status==200 and len(rows)==1 for status,rows in results)
    status,final=request('/animals?id=eq.'+animal+'&select=name')
    sql("update animals set name='Synthetic animal 3' where id='"+animal+"';")
    assert successes==1, f'Both animal edits succeeded ({successes}); final name {final[0]["name"]!r}. Earlier edit was silently overwritten.'
    return {'successful_edits':successes}

def interruption_rollback():
    # A write starts, but the database backend is terminated before COMMIT.
    marker='e1000000-0000-4000-8000-000000000099'
    cmd=['docker','exec','-i','--env','PGPASSWORD=local-synthetic-test-only',CONTAINER,'psql','-h','127.0.0.1','-X','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1','-Atq']
    process=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    process.stdin.write("set application_name='rmb_interrupted_write'; begin; select set_config('request.jwt.claim.sub','"+OWNER+"',true); set local role authenticated; insert into animal_weights(id,animal_id,weight) values('"+marker+"','"+uid('rmb-scale-animal-1')+"',4.5); select pg_sleep(30); commit;");process.stdin.close()
    deadline=time.monotonic()+10;pid=None
    while time.monotonic()<deadline:
        found=sql("select pid from pg_stat_activity where application_name='rmb_interrupted_write' and wait_event='PgSleep';").stdout.strip()
        if found:pid=int(found);break
        time.sleep(.1)
    assert pid is not None,'Write did not enter the controlled interruption point'
    sql('select pg_terminate_backend('+str(pid)+');')
    process.wait(timeout=10)
    assert int(sql("select count(*) from animal_weights where id='"+marker+"';").stdout)==0
    return {'backend_terminated_before_commit':True,'partial_rows':0}

if __name__=='__main__':
    try:
        setup_extra()
        for name,fn in [('seeded_counts',counts),('pagination_beyond_1000',animals_pages),('family_isolation',history_isolation),('invalid_bulk_atomicity',invalid_bulk_atomicity),('simultaneous_litter_edits',competing_litter_edits),('simultaneous_sale_edits',competing_sale_edits),('simultaneous_payments',competing_payments),('payment_retry',replay_payment),('interrupted_write',interruption_rollback),('lost_bulk_acknowledgement',lost_bulk_acknowledgement),('simultaneous_animal_edits',competing_animal_edits)]:
            check(name,fn)
    finally:
        output=Path('deliverables/database-stress-results.json');output.parent.mkdir(exist_ok=True)
        output.write_text(json.dumps(RESULTS,indent=2)+'\n')

    if any(not row['passed'] for row in RESULTS):
        raise SystemExit(1)

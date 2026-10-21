"""Concurrency checks for the explicitly named disposable LOCAL license database."""
from concurrent.futures import ThreadPoolExecutor
import subprocess

CONTAINER = 'supabase_db_ringmaster-show-full-e2e-convention'
DATABASE = 'rmb_license_test_20261021'
OWNER = 'e6102100-0000-4000-8000-000000000090'
HERD = 'e6102100-0000-4000-8000-000000000091'

def sql(query, check=True):
    result = subprocess.run(['docker','exec','-i',CONTAINER,'psql','-U','postgres','-d',DATABASE,'-v','ON_ERROR_STOP=1','-Atq'],input=query,text=True,capture_output=True,timeout=45)
    if check and result.returncode:
        raise AssertionError(result.stderr)
    return result

enrollment = sql("select enabled from breeder_private.testing_access where singleton").stdout.strip() == "t"
sql(f"""begin;
update breeder_private.testing_access set enabled=false where singleton;
insert into auth.users(id,email,email_confirmed_at) values('{OWNER}','parallel-quota@example.test',now());
insert into public.users(id,username,email,auth_user_id) values('{OWNER}','parallel_quota','parallel-quota@example.test','{OWNER}');
insert into public.user_licenses(user_id,tier_code,status) values('{OWNER}','HOBBY','active');
insert into public.farms(id,name,owner_id,is_demo) values('{HERD}','Parallel quota','{OWNER}',false);
commit;""")
try:
    def grow(batch):
        return sql(f"""begin;
        set local role authenticated;
        select set_config('request.jwt.claim.sub','{OWNER}',true);
        insert into public.animals(ring_id,name,species,status)
        select '{HERD}','Parallel {batch} '||i,'rabbit','active' from generate_series(1,25) i;
        commit;""")
    with ThreadPoolExecutor(2) as pool:
        list(pool.map(grow,range(2)))
    result = sql(f"select active_count,(select count(*) from public.animals where ring_id='{HERD}'),limit_reached_at is not null from public.breeder_license_usage where owner_id='{OWNER}'").stdout.strip()
    assert result == '50|50|t',result
    sql(f"update public.breeder_license_usage set limit_reached_at=now()-interval '31 days' where owner_id='{OWNER}'")
    def denied(i):
        # Even a privileged server import cannot bypass the database trigger.
        result=sql(f"insert into public.animals(ring_id,name,species,status) values('{HERD}','Denied {i}','rabbit','active')",check=False)
        assert result.returncode != 0 and 'grace period has ended' in result.stderr,result.stderr
    with ThreadPoolExecutor(4) as pool:
        list(pool.map(denied,range(4)))
    result=sql(f"select active_count,(select count(*) from public.animals where ring_id='{HERD}') from public.breeder_license_usage where owner_id='{OWNER}'").stdout.strip()
    assert result=='50|50',result
    print('PASS: concurrent counts remain exact; all expired-grace writes rejected, including privileged import path.')
finally:
    sql("update breeder_private.testing_access set enabled="+("true" if enrollment else "false")+" where singleton")
    sql(f"delete from public.animals where ring_id='{HERD}';delete from public.farms where id='{HERD}';delete from public.user_licenses where user_id='{OWNER}';delete from public.users where id='{OWNER}';delete from auth.users where id='{OWNER}';")

#!/usr/bin/env python3
"""Add 49 independent synthetic breeders, each with 1000 animals and 10000 history rows."""
import json
from pathlib import Path
from common import RING,sql,uid

sql("""begin;
do $$ declare n integer; actor uuid; herd uuid; owner text; begin
 for n in 1..49 loop
  actor:=md5('rmb-multi-user-'||n)::uuid; herd:=md5('rmb-multi-herd-'||n)::uuid;
  owner:='multi-breeder-'||n;
  insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,
    confirmation_token,recovery_token,email_change_token_new,email_change,email_change_token_current,reauthentication_token,phone_change_token,raw_app_meta_data,raw_user_meta_data)
  values(actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',owner||'@example.invalid',
    extensions.crypt('Synthetic-stress-only-2026!',extensions.gen_salt('bf')),now(),now(),now(),'','','','','','','','{}','{}');
  insert into auth.identities(id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
  values(actor,actor,actor::text,jsonb_build_object('sub',actor,'email',owner||'@example.invalid'),'email',now(),now(),now());
  insert into public.users(id,auth_user_id,username,email) values(owner,actor,owner,owner||'@example.invalid');
  insert into public.farms(id,name,owner_id) values(herd,'Synthetic independent herd '||n,owner);
  perform set_config('request.jwt.claim.sub',actor::text,true);
  insert into public.animals(id,ring_id,name,tattoo,species,sex,status,pedigree_only)
  select md5('rmb-multi-animal-'||n||'-'||i)::uuid,herd,'Synthetic breeder '||n||' animal '||i,'MULTI-'||n||'-'||i,
    'rabbit',case when i%2=1 then 'Buck' else 'Doe' end,'active',false from generate_series(1,1000) i;
  insert into public.animal_weights(id,animal_id,weight,recorded_at)
  select md5('rmb-multi-weight-'||n||'-'||i)::uuid,md5('rmb-multi-animal-'||n||'-'||(1+(i-1)%1000))::uuid,
    4.5,now()-((1+(i-1)/1000)||' days')::interval from generate_series(1,4000) i;
  insert into public.animal_health_records(id,animal_id,record_type,title,administered_date,readminister_date,retention)
  select md5('rmb-multi-health-'||n||'-'||i)::uuid,md5('rmb-multi-animal-'||n||'-'||(1+(i-1)%1000))::uuid,
    'health','Synthetic multi health '||i,current_date-(i%730),case when i%20=0 then current_date+(i%180) end,'never'
    from generate_series(1,4000) i;
  insert into public.breeding_records(id,sire_id,dam_id,breeding_date,status)
  select md5('rmb-multi-breeding-'||n||'-'||i)::uuid,
    md5('rmb-multi-animal-'||n||'-'||(1+2*((i-1)%500)))::uuid,
    md5('rmb-multi-animal-'||n||'-'||(2+2*((i-1)%500)))::uuid,
    current_date-(i%730),'completed' from generate_series(1,2000) i;
 end loop;
end $$;
commit;
analyze public.animals; analyze public.animal_weights; analyze public.animal_health_records; analyze public.breeding_records;
""")
print('Seeded 50 independent breeders: 50000 animals, 990000 historical records.', flush=True)
identities=[{'index':0,'label':'large-history-owner','email':'scale-owner@example.invalid',
 'ring':RING,'animal':uid('rmb-scale-animal-5'),'min_weights':180,'min_health':300}]
for n in range(1,50):
 identities.append({'index':n,'label':'breeder-'+str(n),'email':'multi-breeder-'+str(n)+'@example.invalid',
  'ring':uid('rmb-multi-herd-'+str(n)),'animal':uid('rmb-multi-animal-'+str(n)+'-5'),
  'min_weights':4,'min_health':4})
Path('/private/tmp/rmb-next-stress/multi-identities.json').write_text(json.dumps(identities))

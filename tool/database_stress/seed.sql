-- Run ONLY against a disposable clone: all identities and records are synthetic.
\set ON_ERROR_STOP on
begin;
set local statement_timeout='0';
insert into auth.users(id,email,email_confirmed_at) values
 ('e1000000-0000-4000-8000-000000000001','scale-owner@example.invalid',now()),
 ('e1000000-0000-4000-8000-000000000002','scale-member@example.invalid',now()),
 ('e1000000-0000-4000-8000-000000000003','scale-outsider@example.invalid',now());
insert into public.users(id,auth_user_id,username,email) values
 ('scale-owner','e1000000-0000-4000-8000-000000000001','scale-owner','scale-owner@example.invalid'),
 ('scale-outsider','e1000000-0000-4000-8000-000000000003','scale-outsider','scale-outsider@example.invalid');
insert into public.farms(id,name,owner_id) values
 ('e1000000-0000-4000-8000-000000000010','Synthetic 1000 animal herd','scale-owner'),
 ('e1000000-0000-4000-8000-000000000011','Synthetic outsider herd','scale-outsider');
insert into breeder_private.invitations(owner_id,email,member_user_id,accepted_at) values
 ('scale-owner','scale-member@example.invalid','e1000000-0000-4000-8000-000000000002',now());
select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000001',true);
insert into public.animals(id,ring_id,name,tattoo,species,sex,status,pedigree_only)
select md5('rmb-scale-animal-'||i)::uuid,'e1000000-0000-4000-8000-000000000010','Synthetic animal '||i,'SCALE-'||i,'rabbit',case when i%2=1 then 'Buck' else 'Doe' end,'active',false from generate_series(1,1000) i;
insert into public.animal_weights(id,animal_id,weight,recorded_at)
select md5('rmb-scale-weight-'||i)::uuid,md5('rmb-scale-animal-'||(1+(i-1)%1000))::uuid,4+(i%30)/10.0,now()-((1+(i-1)/1000)||' days')::interval from generate_series(1,180000) i;
insert into public.animal_health_records(id,animal_id,record_type,title,administered_date,readminister_date,expires_date,retention)
select md5('rmb-scale-health-'||i)::uuid,md5('rmb-scale-animal-'||(1+(i-1)%1000))::uuid,'health','Synthetic history '||i,
 current_date-(i%7300),case when i%100=0 then current_date+(i%180) end,case when i%200=0 then current_date+365+(i%180) end,'never' from generate_series(1,300000) i;
insert into public.breeding_records(id,sire_id,dam_id,breeding_date,status)
select md5('rmb-scale-breeding-'||i)::uuid,md5('rmb-scale-animal-'||(1+2*((i-1)%500)))::uuid,
 md5('rmb-scale-animal-'||(2+2*((i-1)%500)))::uuid,current_date-60-(i%7300),'completed' from generate_series(1,20000) i;
update public.breeding_records set status='active' where id=md5('rmb-scale-breeding-1')::uuid;
insert into public.animal_sales(id,animal_id,ring_id,animal_name,asking_cents,sale_cents)
values('e1000000-0000-4000-8000-000000000020',md5('rmb-scale-animal-2')::uuid,'e1000000-0000-4000-8000-000000000010','',10000,10000);
commit;
analyze public.animals;
analyze public.animal_weights;
analyze public.animal_health_records;
analyze public.breeding_records;

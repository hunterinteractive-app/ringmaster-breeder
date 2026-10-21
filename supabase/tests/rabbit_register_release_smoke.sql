begin;
insert into auth.users(id,email,email_confirmed_at) values
('ca350000-0000-4000-8000-000000000001','rr-release-owner@example.test',now()),
('ca350000-0000-4000-8000-000000000002','rr-release-outsider@example.test',now());
insert into public.users(id,username,email,auth_user_id) values
('rr-release-smoke-owner','rr_release_smoke_owner','rr-release-owner@example.test','ca350000-0000-4000-8000-000000000001'),
('rr-release-smoke-outsider','rr_release_smoke_outsider','rr-release-outsider@example.test','ca350000-0000-4000-8000-000000000002');
insert into public.user_licenses(user_id,tier_code,status,started_at,expires_at) values('rr-release-smoke-owner','HOBBY','active',now(),now()+interval '1 day');
insert into public.farms(id,name,owner_id) values('ca350000-0000-4000-8000-000000000003','Synthetic release test','rr-release-smoke-owner');
set local role authenticated;
select set_config('request.jwt.claim.sub','ca350000-0000-4000-8000-000000000001',true);
do $$
declare p jsonb; r jsonb; rabbit uuid; litter uuid; before_weights integer; settings jsonb;
begin
 p:='{"filename":"Synthetic.XML","original_file_base64":"PEV4cG9ydGVkRGF0YS8+","header":{"ProgramVersion":"15.synthetic"},"warnings_acknowledged":true,"animals":[{"source_id":"1","name":"Synthetic buck","tattoo":"RR-RELEASE-B","breed":"Dutch","sex":"Buck","status":"active","raw":{"CID":"1","Name":"Synthetic buck"}},{"source_id":"2","name":"Synthetic doe","tattoo":"RR-RELEASE-D","breed":"Dutch","sex":"Doe","status":"active","raw":{"CID":"2","Name":"Synthetic doe"}}],"records":[{"kind":"contact","source_id":"1","raw":{"ID":"1","FirstName":"Synthetic breeder","Rabbitry":"Test rabbitry"}},{"kind":"litter","source_id":"1","animal_source_id":"2","sire_source_id":"1","raw":{"ID":"1","DATEBRED":"2026-01-01","NUMBERBORN":"5","CAGE":"T1","ADDED":"1","INSTALLNESTBOXCOMPLETE":"True"}},{"kind":"show","source_id":"1","animal_source_id":"1","raw":{"ID":"1","ShowName":"Synthetic show","ShowDate":"2026-03-01","Judge":"Synthetic judge","RankInClass":"1","IsALeg":"True"}},{"kind":"weight","source_id":"1","animal_source_id":"1","weight":4,"recorded_date":"2026-03-01","raw":{"ID":"1","FEEDWT":"4535.92"}},{"kind":"litter_weight","source_id":"1","litter_source_id":"1","raw":{"ID":"1","LITTERKEY":"1","WEIGHINGDATE":"2026-03-01","LITTERWT":"1814.368","FEEDWT":"4535.92"}},{"kind":"wool","source_id":"1","animal_source_id":"1","raw":{"WID":"1","CID":"1","SHEARDATE":"2026-03-01","PRIME":"20","CF":"95"}},{"kind":"wool","source_id":"2","raw":{"WID":"2","CID":"-1","SHEARDATE":"0100-01-03","XMLDATA":"<JudgingInfo><Judge>Synthetic judge</Judge></JudgingInfo>"}}]}';
 p:=jsonb_set(p,'{animals}',(p->'animals')||(select jsonb_agg(jsonb_build_object('source_id',(100+g)::text,'name','Synthetic archived '||g,'breed','Dutch','sex','Buck','status','archived','raw',jsonb_build_object('CID',(100+g)::text))) from generate_series(1,51) g));
 r:=public.import_rabbit_register('ca350000-0000-4000-8000-000000000003','release-smoke',p,false);
 if r->'issues'<>'[]'::jsonb then raise exception 'Import preview issues: %',r->'issues';end if;
 r:=public.import_rabbit_register('ca350000-0000-4000-8000-000000000003','release-smoke',p,true);
 if r->>'status'<>'imported' or (r->>'animals_added')::int<>53 then raise exception 'Import commit failed: %',r;end if;
 select animal_id into rabbit from public.rabbit_register_animals where ring_id='ca350000-0000-4000-8000-000000000003' and source='release-smoke' and source_id='1';
 select id into litter from public.breeding_records where import_ring_id='ca350000-0000-4000-8000-000000000003' and import_source='release-smoke';
 if not exists(select 1 from public.breeding_tracking where breeding_id=litter and cage='T1' and added=1 and nest_installed) then raise exception 'Litter details missing';end if;
 perform public.save_breeding_tracking(litter,'{"cage":"T2","nest_removed":true}'::jsonb,1);
 settings:='{"unit":"oz","metric":"adjusted","period":"lifetime","factors":{"PRIME":100,"GRADE2":75,"COMBINGS":25,"FELTEDSTAINED":25},"show_on_pedigree":true,"update_body_weight":true}';
 perform public.save_wool_settings(rabbit,settings,0);
 select count(*) into before_weights from public.animal_weights where animal_id=rabbit;
 perform public.save_production_measurement('wool','ca350000-0000-4000-8000-000000000004',rabbit,'{"recorded_date":"2026-04-01","fleece_grams":40,"measurements":{"PRIME":20,"GRADE2":20,"BODYWT":1814.368,"CF":99,"SD":2}}',0);
 perform public.save_production_measurement('wool','ca350000-0000-4000-8000-000000000004',rabbit,'{"recorded_date":"2026-04-01","fleece_grams":40,"measurements":{"PRIME":20,"GRADE2":20,"BODYWT":1814.368,"CF":99,"SD":2}}',0);
 if (select count(*) from public.animal_weights where animal_id=rabbit)<>before_weights+1 then raise exception 'Wool retry created duplicate chart records';end if;
 perform public.save_production_measurement('animal_feed','ca350000-0000-4000-8000-000000000005',rabbit,'{"recorded_date":"2026-04-02","feed_weight":12}',0);
 if not exists(select 1 from public.animal_feed_weights where id='ca350000-0000-4000-8000-000000000005' and weight is null) then raise exception 'Feed-only save failed';end if;
 perform public.link_rabbit_register_wool('ca350000-0000-4000-8000-000000000003','release-smoke','2',rabbit);
 if (select count(*) from public.animal_wool_records where animal_id=rabbit)<>3 then raise exception 'Wool link missing';end if;
 r:=public.import_rabbit_register('ca350000-0000-4000-8000-000000000003','release-smoke',p,true);
 if (r->>'animals_added')::int<>0 then raise exception 'Import retry duplicated animals';end if;
 if not exists(select 1 from public.breeding_tracking where breeding_id=litter and cage='T2' and nest_removed) then raise exception 'Retry overwrote litter edits';end if;
 if (select count(*) from public.rabbit_register_files where ring_id='ca350000-0000-4000-8000-000000000003')<>1 then raise exception 'Original XML retry duplicated archive';end if;
end $$;
select set_config('request.jwt.claim.sub','ca350000-0000-4000-8000-000000000002',true);
do $$ begin
 if exists(select 1 from public.herd_contacts) or exists(select 1 from public.animal_feed_weights) or exists(select 1 from public.animal_wool_records) or exists(select 1 from public.wool_settings) or exists(select 1 from public.rabbit_register_files) then raise exception 'Other-owner records leaked';end if;
 begin perform public.save_wool_settings('ca350000-0000-4000-8000-000000000004','{}',0);raise exception 'Access bypass';exception when raise_exception then if sqlerrm='Access bypass' then raise;end if;end;
end $$;
reset role;
rollback;
select 'Rabbit Register authenticated import, ongoing tracking, retries and owner isolation passed; synthetic changes rolled back.' as result;

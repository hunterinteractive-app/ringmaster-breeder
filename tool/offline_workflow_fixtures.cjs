/* Synthetic, deterministic workflows for the isolated Postgres test. */
const fs=require('node:fs');
globalThis.crypto ||= require('node:crypto').webcrypto;
const A=require('../web/offline_actions.js'),Q=require('../web/offline_query.js');
const ring='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',actor='11111111-1111-4111-8111-111111111111';
(async()=>{
 let tables=Object.fromEntries(['users','farms','animals','animal_weights','animal_health_records','breeding_records','breeding_tracking','breeding_settings','breeding_offspring','pedigree_drafts','animal_sales','animal_sale_payments','animal_sale_history','global_pedigree_import_drafts','global_pedigree_animals','global_pedigree_history'].map(t=>[t,[]]));
 tables.users=[{id:'legacy-owner',auth_user_id:actor,display_name:null}];tables.farms=[{id:ring,name:'Fixture herd',owner_id:'legacy-owner',is_demo:false}];
 tables.license_tiers=[{code:'FIXTURE',max_active_animals:1000,max_rings:10,annual_price_cents:0}];
 tables.user_licenses=[{user_id:'legacy-owner',tier_code:'FIXTURE',status:'active'}];tables.breeder_license_usage=[];
 const workflows=[];
 async function apply(request,label){
  const id=crypto.randomUUID(),prepared=await A.prepare(tables,request,id,'2026-03-01T10:00:00Z',actor);
  workflows.push({label,operation:{id,seed:id,request,expects:prepared.expects,mutations:prepared.mutations},expected:prepared.result});
  tables=Q.project(tables,[prepared]);return prepared.result;
 }
 const doe=await apply({type:'rpc',target:'create_animal_with_color_details',body:{p_ring_id:ring,p_name:'Workflow doe',p_tattoo:'FLOWDOE',p_species:'rabbit',p_breed:'Dutch',p_variety:'Black',p_sex:'Doe',p_status:'active',p_dob:null,p_registration:'',p_gc:'',p_sire_id:null,p_dam_id:null,p_weight:4,p_color_details:{}}},'new doe with weight');
 await apply({type:'rpc',target:'record_breeding_with_parents',body:{p_ring:ring,p_parents:[{id:'new_sire',name:'Workflow sire',tattoo:'FLOWSIRE',species:'rabbit',breed:'Dutch',variety:'Black',sex:'Buck',dob:null,weight:4,registration_number:'',grand_champion_number:'',color_details:{}}],p_records:[{sire_id:'new_sire',dam_id:doe,breeding_date:'2026-01-01',notes:''}]}},'breeding with new parent');
 const breeding=tables.breeding_records[0].id;
 await apply({type:'rpc',target:'save_breeding_tracking',body:{p_id:breeding,p_revision:0,p_data:{due_date:'2026-02-01',check_date:null,check_result:'Not checked',birth_date:'2026-02-01',born_alive:2,born_dead:0,wean_date:'2026-03-01',weaned:2,weaned_males:1,weaned_females:1,status:'active',notes:''}}},'tracking');
 await apply({type:'rpc',target:'create_litter_animals',body:{p_id:breeding,p_young:[{name:'Workflow young M',tattoo:'FLOWM',breed:'Dutch',variety:'Black',sex:'M'},{name:'Workflow young F',tattoo:'FLOWF',breed:'Dutch',variety:'Black',sex:'F'}]}},'offspring stable IDs');
 const draft=await apply({type:'table',target:'pedigree_drafts',method:'POST',body:{ring_id:ring,data:{species:'rabbit',root:'new0',nodes:{new0:{name:'Workflow pedigree',tattoo:'FLOWPED',sex:'Doe',breed:'Dutch',variety:'Black',sire:'new1',dam:'existing'},new1:{name:'Workflow ancestor',tattoo:'FLOWANC',sex:'Buck',breed:'Dutch',variety:'Black',weight:4},existing:{existing_id:doe}}}}},'pedigree draft');
 await apply({type:'table',target:'pedigree_drafts',method:'PATCH',query:[['id','eq.'+draft[0].id]],body:{data:draft[0].data,updated_at:'2026-03-02T10:00:00Z'}},'save draft again before syncing');
 await apply({type:'rpc',target:'save_pedigree_draft',body:{p_draft:draft[0].id}},'pedigree stable graph IDs');
 const settings=['rabbit','cavy'].map(species=>({ring_id:ring,species,gestation_min:species==='rabbit'?28:59,gestation_max:species==='rabbit'?32:72,palpation_min:14,palpation_max:28,nesting_day:species==='rabbit'?26:null,weaning_min:4,weaning_max:8}));
 await apply({type:'table',target:'breeding_settings',method:'POST',upsert:true,body:settings},'composite key insert');
 await apply({type:'table',target:'breeding_settings',method:'POST',upsert:true,body:settings.map(s=>({...s,palpation_max:29}))},'composite key update');
 await apply({type:'table',target:'users',method:'PATCH',query:[['id','eq.legacy-owner']],body:{display_name:'Offline Owner'}},'profile');
 const sale=await apply({type:'table',target:'animal_sales',method:'POST',body:{animal_id:doe,ring_id:ring,animal_name:'',asking_cents:5000}},'list animal');
 await apply({type:'table',target:'animal_sales',method:'PATCH',query:[['id','eq.'+sale[0].id]],body:{buyer_name:'Offline buyer',sale_cents:5000,buyer_email:'buyer@example.test'}},'reserve animal');
 await apply({type:'table',target:'animal_sale_payments',method:'POST',body:{sale_id:sale[0].id,kind:'payment',amount_cents:5000,paid_on:'2026-03-01',method:'cash'}},'complete sale by payment');
 const empty=await apply({type:'rpc',target:'create_breeder_ring',body:{p_name:'Empty workflow herd',p_owner_id:'legacy-owner'}},'create herd');
 await apply({type:'table',target:'farms',method:'PATCH',query:[['id','eq.'+empty]],body:{name:'Renamed workflow herd'}},'rename herd');
 await apply({type:'rpc',target:'delete_empty_breeder_ring',body:{p_ring:empty}},'delete empty herd');
 fs.writeFileSync(process.argv[2],JSON.stringify(workflows));
})();

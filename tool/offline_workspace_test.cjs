/* Pure repository checks. No network or live database is contacted. */
const {test}=require('node:test');
const assert=require('node:assert/strict');
globalThis.crypto ||= require('node:crypto').webcrypto;
const Q=require('../web/offline_query.js');
const A=require('../web/offline_actions.js');
const W=require('../web/offline_workspace.js');
const ring='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',animal='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const actor='11111111-1111-4111-8111-111111111111';
const now=Date.parse('2026-10-17T10:00:00Z');
function tables(){return {
  farms:[{id:ring,name:'Fixture',owner_id:'legacy-owner',is_demo:false}],
  users:[{id:'legacy-owner',display_name:'Owner'}],
  animals:[{id:animal,ring_id:ring,name:'Willow',tattoo:'W1',species:'rabbit',sex:'Doe',status:'active',revision:1,pedigree_only:false,dob:null,sire_id:null,dam_id:null}],
  animal_weights:[],animal_health_records:[],breeding_settings:[],breeding_records:[],breeding_tracking:[],breeding_offspring:[],pedigree_drafts:[],
  global_pedigree_import_drafts:[],global_pedigree_animals:[],global_pedigree_history:[],
  animal_sales:[],animal_sale_payments:[],animal_sale_history:[],breeds:[],varieties:[],user_licenses:[],license_tiers:[],account_deletions:[],breeder_legal_acceptances:[],
};}
function memory(){const rows=new Map(),reads=[],scans=[];return{
  rows,reads,scans,
  async read(key){reads.push(key);return JSON.stringify(rows.get(key)||null);},
  async scan(prefix){scans.push(prefix);return JSON.stringify([...rows.values()].filter(d=>d.key.startsWith(prefix)));},
  async commit(encoded){const{expected,puts,deletes}=JSON.parse(encoded);
    if(Object.entries(expected).some(([k,v])=>(rows.get(k)?.version??null)!==v))return false;
    for(const[k,v]of Object.entries(puts))rows.set(k,{key:k,version:(rows.get(k)?.version||0)+1,value:Q.clone(v)});
    deletes.forEach(k=>rows.delete(k));return true;
  },
};}
async function fixture(extra={}){
  const api=memory(),calls=[],receipts=new Map();let source=tables();
  const fetch=async(url,options)=>{
    calls.push({url,options});
    if(extra.fetch){const response=await extra.fetch(url,options);if(response!==undefined)return response;}
    if(url.includes('/auth/v1/user'))return Response.json({id:actor});
    if(url.includes('breeder_offline_snapshot'))return Response.json({protocol:1,tables:source,versions:{animals:1,_scope:'owner'},counts:{animals:source.animals.length},files:[],membership:{households:[{owner_user_id:'legacy-owner',is_owner:true}],invitations:[]}});
    if(url.includes('breeder_offline_apply')){
      const op=JSON.parse(options.body).p_operation;
      if(!receipts.has(op.id)){source=Q.project(source,[op]);receipts.set(op.id,{state:'applied',result:null});}
      return Response.json(receipts.get(op.id));
    }
    throw new Error('Unexpected request: '+url);
  };
  const workspace=W.create(api,{fetch,now:()=>now});
  const token='e30.'+Buffer.from(JSON.stringify({sub:actor})).toString('base64url')+'.fixture';
  await workspace.setup({account:actor,token,apiKey:'fixture',url:'https://fixture.invalid',expires:9999999999});
  await workspace.refresh();return{workspace,api,calls,source,receipts,token};
}
test('queries filter on omitted columns and retain pagination order',()=>{
  const data=tables();data.animals.push({...data.animals[0],id:'other',name:'Alice'});
  const p=new URLSearchParams({select:'id,name',ring_id:'eq.'+ring,order:'name.asc',offset:'1',limit:'1'});
  assert.deepEqual(Q.query(data,'animals',p),{rows:[{id:animal,name:'Willow'}],count:2});
});
test('SQL null filters do not equate null to empty or false',()=>{
  assert.equal(Q.compare(null,'eq.null'),false);assert.equal(Q.compare(null,'is.null'),true);
  assert.equal(Q.compare(false,'eq.false'),true);assert.equal(Q.compare(null,'neq.active'),false);
});
test('nested joins include tracking, parents, offspring, and their animal',()=>{
  const d=tables();d.breeding_records=[{id:'b',dam_id:animal,sire_id:null}];d.breeding_tracking=[{breeding_id:'b',status:'active'}];
  d.breeding_offspring=[{breeding_id:'b',animal_id:animal}];
  const p=new URLSearchParams({select:'*,dam:animals!inner(*),tracking:breeding_tracking(*),offspring:breeding_offspring(*,animal:animals(*))','dam.ring_id':'eq.'+ring});
  const result=Q.query(d,'breeding_records',p).rows[0];
  assert.equal(result.dam.name,'Willow');assert.equal(result.tracking.status,'active');assert.equal(result.offspring[0].animal.id,animal);
});
test('any calendar month filters downloaded source dates with nested OR/AND',()=>{
  const d=tables();d.animal_health_records=[{id:'h',animal_id:animal,title:'Vaccine',administered_date:'2025-01-10',readminister_date:'2027-12-20'}];
  const p=new URLSearchParams({select:'*,animal:animals!inner(*)','animal.ring_id':'eq.'+ring,or:'(and(administered_date.gte.2027-12-01,administered_date.lt.2028-01-01),and(readminister_date.gte.2027-12-01,readminister_date.lt.2028-01-01))'});
  assert.equal(Q.query(d,'animal_health_records',p).rows.length,1);
});
test('embedded weight limit does not limit root animals',()=>{
  const d=tables();d.animal_weights=[{id:'w1',animal_id:animal,recorded_at:'2026-01-01',weight:3},{id:'w2',animal_id:animal,recorded_at:'2026-02-01',weight:4}];
  const p=new URLSearchParams({select:'*,animal_weights(*)','animal_weights.order':'recorded_at.desc','animal_weights.limit':'1'});
  assert.equal(Q.query(d,'animals',p).rows[0].animal_weights[0].weight,4);
});
test('missing tables and unsupported relationships fail explicitly',()=>{
  assert.throws(()=>Q.query(tables(),'missing'),/not been downloaded/);
  assert.throws(()=>Q.query(tables(),'animals',new URLSearchParams({select:'other:unknown(*)'})),/Relationship/);
});
test('pending edits, insertions, and deletions project into local queries',()=>{
  const d=tables();d.animal_health_records=[{id:'h',animal_id:animal,title:'Old'}];
  const result=Q.project(d,[{mutations:[{table:'animals',action:'update',row:{id:animal,name:'Offline'}},{table:'animal_health_records',action:'delete',row:{id:'h'}}]}]);
  assert.equal(result.animals[0].name,'Offline');assert.equal(result.animal_health_records.length,0);assert.equal(d.animals[0].name,'Willow');
});
test('deterministic RPC IDs survive retries and include the initial weight',async()=>{
  const r={type:'rpc',target:'create_animal_with_color_details',body:{p_ring_id:ring,p_name:'New',p_tattoo:'NEW',p_species:'rabbit',p_breed:'Dutch',p_variety:'Black',p_sex:'Buck',p_status:'active',p_dob:null,p_registration:'',p_gc:'',p_sire_id:null,p_dam_id:animal,p_weight:4,p_color_details:{}}};
  const first=await A.prepare(tables(),Q.clone(r),'aaaaaaaa-1111-4111-8111-111111111111',new Date(now).toISOString());
  const retry=await A.prepare(tables(),Q.clone(r),'aaaaaaaa-1111-4111-8111-111111111111',new Date(now).toISOString());
  assert.deepEqual(first,retry);assert.equal(first.mutations.length,2);assert.equal(first.mutations[1].row.animal_id,first.result);
});
test('pedigree local IDs preserve shared ancestors and server node order',async()=>{
  const d=tables();d.pedigree_drafts=[{id:'draft',ring_id:ring,data:{species:'rabbit',root:'new0',nodes:{new0:{name:'New',sex:'Doe',sire:'new1',dam:'new2'},new1:{name:'Sire',sex:'Buck'},new2:{existing_id:animal}}}}];
  const p=await A.prepare(d,{type:'rpc',target:'save_pedigree_draft',body:{p_draft:'draft'}},'aaaaaaaa-1111-4111-8111-111111111111',new Date(now).toISOString());
  const projected=Q.project(d,[p]);const root=projected.animals.find(a=>a.id===p.result);
  assert.equal(root.dam_id,animal);assert.equal(projected.animals.find(a=>a.id===root.sire_id).name,'Sire');assert.equal(projected.pedigree_drafts[0].saved_animal_id,p.result);
});
test('pedigree cycles fail before creating any queued records',async()=>{
  const d=tables();d.pedigree_drafts=[{id:'draft',ring_id:ring,data:{species:'rabbit',root:'n',nodes:{n:{name:'Cycle',sex:'Doe',sire:'n'}}}}];
  await assert.rejects(A.prepare(d,{type:'rpc',target:'save_pedigree_draft',body:{p_draft:'draft'}},W.uuid(),new Date(now).toISOString()),/cycles/);
});
test('identity/status fields participate in the same conflict check',()=>{
  const d=tables().animals[0],m=A.patchMutation('animals',d,{dob:'2026-01-01'});
  assert.equal(m.before.sex,'Doe');assert.equal(m.before.status,'active');
  assert.deepEqual(A.patchMutation('animals',d,{name:'New'}).before,{name:'Willow'});
});
test('protected fields, online administration, and unknown RPCs cannot queue',()=>{
  assert.throws(()=>A.validate({type:'table',target:'users',method:'PATCH',body:{role:'admin'}}),/fields/);
  assert.throws(()=>A.validate({type:'table',target:'user_licenses',method:'POST',body:{}}),/connection/);
  assert.throws(()=>A.validate({type:'rpc',target:'purge_account_data',body:{}}),/connection/);
});
test('complete download stores all tables and credentials outside recovery namespace',async()=>{
  const f=await fixture();const status=await f.workspace.status();assert.equal(status.ready,true);assert.equal(status.counts.animals,1);
  const exportRows=JSON.parse(await f.api.scan('v1:'+actor+':'));
  assert.equal(JSON.stringify(exportRows).includes(f.token),false);
  assert.equal((await f.workspace.tables()).animals[0].name,'Willow');
});
test('a local mutation is durable before returning, then survives reopen',async()=>{
  const f=await fixture();
  await f.workspace.queue({type:'table',target:'animal_health_records',method:'POST',body:{animal_id:animal,title:'Vaccine',record_type:'health',administered_date:'2026-10-17'}});
  assert.equal((await f.workspace.operations()).length,1);
  const reopened=W.create(f.api);await reopened.loadConfiguration();
  assert.equal((await reopened.tables()).animal_health_records[0].title,'Vaccine');
});
test('independent animal creations do not depend on a shared herd ID',async()=>{
  const f=await fixture();
  for(const name of ['First','Second'])await f.workspace.queue({type:'table',target:'animals',method:'POST',body:{name,ring_id:ring,species:'rabbit',sex:'Buck'}});
  assert.deepEqual((await f.workspace.operations()).map(o=>o.requires),[[],[]]);
});
test('a weight for a provisional animal waits for its creation',async()=>{
  const f=await fixture();
  const [created]=await f.workspace.queue({type:'table',target:'animals',method:'POST',body:{name:'New',ring_id:ring,species:'rabbit',sex:'Buck'}});
  await f.workspace.queue({type:'table',target:'animal_weights',method:'POST',body:{animal_id:created.id,weight:4}});
  const ops=await f.workspace.operations();assert.deepEqual(ops[1].requires,[ops[0].id]);
});
test('expired access keeps reads and prevents another edit',async()=>{
  const f=await fixture();const k='v1:'+actor+':access';
  await f.api.commit(JSON.stringify({expected:{},puts:{[k]:{verified_at:'2026-10-01T00:00:00Z'}},deletes:[]}));
  await assert.rejects(f.workspace.queue({type:'table',target:'animals',method:'PATCH',query:[['id','eq.'+animal]],body:{name:'Changed'}}),/Reconnect/);
  assert.equal((await f.workspace.tables()).animals[0].name,'Willow');
});
test('receipt replay acknowledges a lost response without duplicating a record',async()=>{
  const f=await fixture();await f.workspace.queue({type:'table',target:'animal_health_records',method:'POST',body:{animal_id:animal,title:'Vaccine',record_type:'health',administered_date:'2026-10-17'}});
  const op=(await f.workspace.operations())[0];await Promise.all([f.workspace.push(op),f.workspace.push(op)]);
  assert.equal(f.receipts.size,1);assert.equal((await f.workspace.operations()).length,0);assert.equal((await f.workspace.tables()).animal_health_records.length,1);
});
test('wrong-account requests cannot read a downloaded account',async()=>{
  const f=await fixture();const request=new Request('https://fixture.invalid/rest/v1/animals',{headers:{Authorization:'Bearer e30.'+Buffer.from('{"sub":"other"}').toString('base64url')+'.fixture'}});
  assert.equal(await f.workspace.handle(request),null);
});
test('a cached list exposes newly created records without network requests',async()=>{
  const f=await fixture();const before=f.calls.length;
  await f.workspace.queue({type:'table',target:'animals',method:'POST',body:{name:'Offline new animal',ring_id:ring,species:'rabbit',sex:'Buck'}});
  const response=await f.workspace.handle(new Request('https://fixture.invalid/rest/v1/animals?select=id,name&order=name',{headers:{Authorization:'Bearer '+f.token}}));
  assert.equal((await response.json()).length,2);assert.equal(f.calls.length,before);
});
test('profile reads avoid scanning unrelated herd history tables',async()=>{
  const f=await fixture();f.api.reads.length=0;f.api.scans.length=0;
  const response=await f.workspace.handle(new Request('https://fixture.invalid/rest/v1/users?select=id,display_name',{headers:{Authorization:'Bearer '+f.token}}));
  assert.equal((await response.json())[0].display_name,'Owner');
  assert.equal(f.api.reads.some(k=>k.endsWith('table:animal_weights')),false);
  assert.equal(f.api.scans.some(k=>k.endsWith('cache:table:')),false);
});
test('missing server rows retain the full unsynced local draft',()=>{
  const a=tables().animals[0],mutation=A.patchMutation('animals',a,{name:'My pending name'});
  const d=tables();d.animals=[];
  const result=Q.project(d,[{mutations:[mutation]}]).animals[0];
  assert.equal(result.name,'My pending name');assert.equal(result.species,'rabbit');assert.equal(result.tattoo,'W1');
});
test('bulk records have independent durable outcomes for different animals',async()=>{
  const f=await fixture();
  const [newAnimal]=await f.workspace.queue({type:'table',target:'animals',method:'POST',body:{name:'Second',ring_id:ring,species:'rabbit',sex:'Buck'}});
  await f.workspace.queue({type:'table',target:'animal_health_records',method:'POST',body:[{animal_id:animal,title:'First',record_type:'health',administered_date:'2026-10-17'},{animal_id:newAnimal.id,title:'Second',record_type:'health',administered_date:'2026-10-17'}]});
  const ops=await f.workspace.operations(),health=ops.filter(o=>o.request.target==='animal_health_records');
  assert.equal(health.length,2);assert.notEqual(health[0].animal_id,health[1].animal_id);
  const first=health.find(o=>o.request.body.animal_id===animal),second=health.find(o=>o.request.body.animal_id===newAnimal.id);
  assert.equal(first.requires.includes(second.id),false);assert.equal(second.requires.includes(ops.find(o=>o.request.target==='animals').id),true);
});
test('automatic sale completion and animal status appear locally after payment',async()=>{
  const d=tables();d.animal_sales=[{id:'sale',animal_id:animal,ring_id:ring,status:'reserved',sale_cents:5000,asking_cents:5000,buyer_name:'Buyer',animal_name:'Willow',version:2}];
  const request={type:'table',target:'animal_sale_payments',method:'POST',body:{sale_id:'sale',kind:'payment',amount_cents:5000,paid_on:'2026-10-17'}};
  const p=await A.prepare(d,request,W.uuid(),new Date(now).toISOString()),result=Q.project(d,[p]);
  assert.equal(result.animal_sales[0].status,'sold');assert.equal(result.animals[0].status,'sold');assert.equal(result.animal_sale_history.length,1);
  assert.equal(p.mutations.find(m=>m.table==='animal_sales').derived,true);
});
test('an overpayment or excessive refund cannot be saved as a valid local payment',async()=>{
  const d=tables();d.animal_sales=[{id:'sale',animal_id:animal,ring_id:ring,status:'reserved',sale_cents:5000,asking_cents:5000,buyer_name:'Buyer',version:2}];
  for(const body of [{kind:'payment',amount_cents:5001},{kind:'refund',amount_cents:1}]){
    await assert.rejects(A.prepare(d,{type:'table',target:'animal_sale_payments',method:'POST',body:{sale_id:'sale',...body}},W.uuid(),new Date(now).toISOString()),/balance/);
  }
});
test('breeding, tracking, and offspring project a complete local family',async()=>{
  let d=tables();d.animals.push({...d.animals[0],id:'sire',name:'Sire',sex:'Buck'});
  const breeding=await A.prepare(d,{type:'rpc',target:'record_breeding_with_parents',body:{p_ring:ring,p_parents:[],p_records:[{sire_id:'sire',dam_id:animal,breeding_date:'2026-08-01',notes:''}]}},W.uuid(),new Date(now).toISOString());d=Q.project(d,[breeding]);
  const bid=d.breeding_records[0].id;
  const tracking=await A.prepare(d,{type:'rpc',target:'save_breeding_tracking',body:{p_id:bid,p_revision:0,p_data:{birth_date:'2026-09-01',wean_date:'2026-10-15',weaned:1,born_alive:1,born_dead:0,status:'active',notes:''}}},W.uuid(),new Date(now).toISOString());d=Q.project(d,[tracking]);
  const offspring=await A.prepare(d,{type:'rpc',target:'create_litter_animals',body:{p_id:bid,p_young:[{name:'Kit',tattoo:'K1',sex:'F',breed:'Dutch',variety:'Black'}]}},W.uuid(),new Date(now).toISOString());d=Q.project(d,[offspring]);
  const kit=d.animals.find(a=>a.name==='Kit');assert.equal(kit.dam_id,animal);assert.equal(kit.sire_id,'sire');assert.equal(kit.sex,'Doe');assert.equal(d.breeding_tracking[0].status,'completed');
});
test('full attachment bytes are kept outside the frequently scanned outbox',async()=>{
  const f=await fixture(),content=Buffer.alloc(1024*1024,42).toString('base64');
  await f.workspace.queue({type:'file',bucket:'animal_photos',path:animal+'/photo.jpg',base64:content,content_type:'image/jpeg'});
  const ops=await f.workspace.operations();assert.ok(JSON.stringify(ops).length<3000);
  assert.equal(typeof ops[0].request.asset_ref,'string');assert.equal(ops[0].request.base64,undefined);
  assert.equal((await f.workspace.file('animal_photos',animal+'/photo.jpg')).base64,content);
});
test('PDF snapshots use durable references without entering job statistics',async()=>{
  const f=await fixture();
  await f.workspace.queue({type:'external',target:'email-buyer-pedigree',body:{action:'send',request_id:W.uuid(),animal_id:animal,recipient:'buyer@example.invalid',pdf:Buffer.from('fixture-pdf').toString('base64'),approved_snapshot:{animal:{name:'Willow'}}}});
  const op=(await f.workspace.operations())[0];assert.equal(op.request.body.pdf,undefined);assert.match(op.request.body.pdf_asset_ref,/pending-file/);
  const saved=JSON.parse(await f.api.read('v1:'+actor+':'+op.request.body.pdf_asset_ref));assert.equal(saved.value.type,'application/pdf');
});
test('missing/corrupt attachment bytes cannot be sent or acknowledged',async()=>{
  const f=await fixture();await f.workspace.queue({type:'file',bucket:'health_attachments',path:animal+'/record.pdf',base64:Buffer.from('original').toString('base64'),content_type:'application/pdf'});
  const op=(await f.workspace.operations())[0],k='v1:'+actor+':'+op.request.asset_ref;
  const d=JSON.parse(await f.api.read(k));d.value.base64=Buffer.from('corrupted').toString('base64');
  await f.api.commit(JSON.stringify({expected:{},puts:{[k]:d.value},deletes:[]}));
  const before=f.calls.length;await assert.rejects(f.workspace.push(op),/missing or damaged/);
  assert.equal(f.calls.length,before);assert.equal((await f.workspace.operations()).length,1);
});
test('storage failure cannot report that an attachment was durably saved',async()=>{
  const f=await fixture(),commit=f.api.commit;
  f.api.commit=async encoded=>{if(Object.keys(JSON.parse(encoded).puts).some(k=>k.includes(':op:')))throw Error('Storage full');return commit(encoded);};
  await assert.rejects(f.workspace.queue({type:'file',bucket:'animal_photos',path:animal+'/photo.jpg',base64:'YWJj',content_type:'image/jpeg'}),/Storage full/);
  assert.equal((await f.workspace.operations()).length,0);assert.equal(JSON.parse(await f.api.scan('v1:'+actor+':cache:pending-file:')).length,0);
});
test('a delivered change invalidates its table version before a fresh pull',async()=>{
  const f=await fixture();await f.workspace.queue({type:'table',target:'animals',method:'PATCH',query:[['id','eq.'+animal]],body:{name:'Changed'}});
  await f.workspace.push((await f.workspace.operations())[0]);
  assert.equal((await f.workspace.meta()).versions.animals,null);
});
test('logout cannot pause an in-flight upload; a completed pause stops new sends',async()=>{
  let release;const gate=new Promise(resolve=>release=resolve);
  const f=await fixture({fetch:async url=>url.includes('breeder_offline_apply')?await gate:undefined});
  await f.workspace.queue({type:'table',target:'animals',method:'PATCH',query:[['id','eq.'+animal]],body:{name:'Changed'}});
  const running=f.workspace.push((await f.workspace.operations())[0]);
  while(!(await f.workspace.status()).busy)await new Promise(resolve=>setTimeout(resolve,1));
  assert.equal(await f.workspace.pause(true),false);
  release(Response.json({state:'applied',result:null}));await running;
  assert.equal(await f.workspace.pause(true),true);
  await f.workspace.queue({type:'table',target:'animals',method:'PATCH',query:[['id','eq.'+animal]],body:{name:'Another change'}});
  const before=f.calls.length;await assert.rejects(f.workspace.push((await f.workspace.operations())[0]),/paused/);assert.equal(f.calls.length,before);assert.equal((await f.workspace.operations()).length,1);
  await f.workspace.pause(false);
});
test('a changed access snapshot replaces deleted server rows',async()=>{
  const f=await fixture();f.source.animals.splice(0,1);await f.workspace.refresh();
  assert.equal((await f.workspace.tables()).animals.length,0);
});
test('an authoritative access rejection does not renew the offline lease',async()=>{
  let fail=false;
  const f=await fixture({fetch:async url=>fail&&url.includes('snapshot')?Response.json({message:'Access denied'},{status:403}):undefined});
  const before=JSON.parse(await f.api.read('v1:'+actor+':access'));
  fail=true;await assert.rejects(f.workspace.refresh(),/Access denied/);
  assert.deepEqual(JSON.parse(await f.api.read('v1:'+actor+':access')),before);
});
test('unsupported credential-bearing retrieval cannot enter any exportable document',async()=>{
  const f=await fixture();await assert.rejects(f.workspace.queue({type:'external',target:'global-pedigree',body:{username:'fixture',password:'never-store-this'}}),/Credentials/);
  assert.equal((await f.workspace.operations()).length,0);
  assert.equal(JSON.stringify([...f.api.rows.values()]).includes('never-store-this'),false);
});
if(process.argv.includes('--fixtures')){
  const fs=require('node:fs'),destination=process.argv[process.argv.indexOf('--fixtures')+1];
  (async()=>{const seed='aaaaaaaa-1111-4111-8111-111111111111';
    const request={type:'rpc',target:'create_animal_with_color_details',body:{p_ring_id:ring,p_name:'Receipt animal',p_tattoo:'RECEIPT',p_species:'rabbit',p_breed:'Dutch',p_variety:'Black',p_sex:'Buck',p_status:'active',p_dob:null,p_registration:'',p_gc:'',p_sire_id:null,p_dam_id:null,p_weight:4.25,p_color_details:{}}};
    const prepared=await A.prepare(tables(),request,seed,new Date(now).toISOString());
    fs.writeFileSync(destination,JSON.stringify({id:seed,seed,request,expects:prepared.expects,mutations:prepared.mutations,expected_id:prepared.result}));
  })();
}

test('a herd containing records cannot be deleted offline',async()=>{
  await assert.rejects(A.prepare(tables(),{type:'rpc',target:'delete_empty_breeder_ring',body:{p_ring:ring}},W.uuid(),new Date(now).toISOString()),/contains records/);
  const d=tables();d.animals=[];
  const change=await A.prepare(d,{type:'rpc',target:'delete_empty_breeder_ring',body:{p_ring:ring}},W.uuid(),new Date(now).toISOString());
  assert.equal(Q.project(d,[change]).farms.length,0);
});
test('a download racing an acknowledged write retries its snapshot',async()=>{
  let downloads=0,workspace,api;
  const f=await fixture({fetch:async url=>{
    if(workspace&&url.includes('snapshot')){
      downloads++;
      if(downloads===1)await api.commit(JSON.stringify({puts:{['v1:'+actor+':queue-version']:{}},expected:{},deletes:[]}));
    }
  }});
  ({workspace,api}=f);await workspace.refresh();assert.equal(downloads,2);
});

test('choosing the server version updates the local view atomically',async()=>{
  const f=await fixture();await f.workspace.queue({type:'table',target:'animals',method:'PATCH',query:[['id','eq.'+animal]],body:{name:'Mine'}});
  const op=(await f.workspace.operations())[0],k='v1:'+actor+':op:'+op.id;
  const server={...tables().animals[0],name:'Family edit',revision:2};
  await f.api.commit(JSON.stringify({expected:{},puts:{[k]:{...op,state:'conflict',server:{current:[{table:'animals',key:{id:animal},row:server}]}}},deletes:[]}));
  await f.workspace.resolve(op.id,false);
  assert.equal((await f.workspace.tables()).animals[0].name,'Family edit');assert.equal((await f.workspace.operations()).length,0);
});
test('keeping a conflict rewires dependent actions and preserves stable create IDs',async()=>{
  const f=await fixture();await f.workspace.queue({type:'table',target:'animals',method:'PATCH',query:[['id','eq.'+animal]],body:{name:'Mine'}});
  await f.workspace.queue({type:'table',target:'animal_weights',method:'POST',body:{animal_id:animal,weight:4}});
  const [op,child]=await f.workspace.operations(),k='v1:'+actor+':op:'+op.id;
  await f.api.commit(JSON.stringify({expected:{},puts:{[k]:{...op,state:'conflict',server:{current:[{table:'animals',key:{id:animal},row:{...tables().animals[0],name:'Family edit',registration_number:'Other field'}}]}}},deletes:[]}));
  await f.workspace.resolve(op.id,true);const [replacement,dependent]=await f.workspace.operations();
  assert.notEqual(replacement.id,op.id);assert.equal(replacement.seed,op.id);assert.deepEqual(dependent.requires,[replacement.id]);
  assert.equal((await f.workspace.tables()).animals[0].registration_number,'Other field');
});

test('large relationship queries index each child table once',()=>{
  let reads=0;const data={animals:Array.from({length:1000},(_,i)=>({id:'a'+i})),animal_weights:Array.from({length:10000},(_,i)=>({id:'w'+i,get animal_id(){reads++;return 'a'+(i%1000);},weight:4}))};
  const rows=Q.query(data,'animals',new URLSearchParams({select:'id,animal_weights(*)'})).rows;
  assert.equal(rows.reduce((n,r)=>n+r.animal_weights.length,0),10000);
  assert.ok(reads<=20000,'Child table was scanned repeatedly for each animal');
});

test('Rabbit Register preview and commit require network and refresh only after commit', async()=>{
  const f=await fixture({fetch:async(input)=>{
    const url=typeof input==='string'?input:input.url;
    if(url.includes('/rpc/import_rabbit_register')){
      const body=await input.clone().json();
      return Response.json({status:body.p_commit?'imported':'preview',issues:[]});
    }
  }});
  const request=(commit)=>new Request('https://fixture.invalid/rest/v1/rpc/import_rabbit_register',{
    method:'POST',headers:{Authorization:'Bearer '+f.token,'Content-Type':'application/json'},
    body:JSON.stringify({p_ring:ring,p_source:'fixture',p_data:{animals:[],records:[]},p_commit:commit}),
  });
  const snapshots=()=>f.calls.filter(c=>typeof c.url==='string'&&c.url.includes('breeder_offline_snapshot')).length;
  const before=snapshots();
  assert.equal((await (await f.workspace.handle(request(false))).json()).status,'preview');
  assert.equal(snapshots(),before);
  assert.equal((await (await f.workspace.handle(request(true))).json()).status,'imported');
  assert.equal(snapshots(),before+1);
  assert.equal((await f.workspace.operations()).length,0);
});

test('Kintraks preview and commit require network and refresh only after commit', async()=>{
  const f=await fixture({fetch:async(input)=>{
    const url=typeof input==='string'?input:input.url;
    if(url.includes('/rpc/import_kintraks')){
      const body=await input.clone().json();
      return Response.json({status:body.p_commit?'imported':'preview',issues:[]});
    }
  }});
  const request=(commit)=>new Request('https://fixture.invalid/rest/v1/rpc/import_kintraks',{
    method:'POST',headers:{Authorization:'Bearer '+f.token,'Content-Type':'application/json'},
    body:JSON.stringify({p_ring:ring,p_source:'fixture',p_data:{animals:[],records:[]},p_commit:commit}),
  });
  const snapshots=()=>f.calls.filter(c=>typeof c.url==='string'&&c.url.includes('breeder_offline_snapshot')).length;
  const before=snapshots();
  assert.equal((await (await f.workspace.handle(request(false))).json()).status,'preview');
  assert.equal(snapshots(),before);
  assert.equal((await (await f.workspace.handle(request(true))).json()).status,'imported');
  assert.equal(snapshots(),before+1);
  assert.equal((await f.workspace.operations()).length,0);
});

// Local-only authenticated mixed workload. Uses the actual phone/app query helper.
import {createClient} from 'npm:@supabase/supabase-js@2.110.2';
import {allPages,calendarRecords} from '../../supabase/functions/_shared/calendar-records.mjs';
const status=JSON.parse(await Deno.readTextFile('/private/tmp/rmb-next-stress/local-status.json'));
if(status.API_URL!=='http://127.0.0.1:56431')throw Error('Refusing a non-local API');
const API=status.API_URL;
// Deterministic fixture IDs are supplied by the Python fixture generator.
const identities=JSON.parse(await Deno.readTextFile('/private/tmp/rmb-next-stress/multi-identities.json'));
const samples:any[]=[];
const stages:any[]=[];
let currentStage=0,inflight=0,maxInflight=0;
function assert(ok:unknown,message:string){if(!ok)throw Error(message);}
const clients:any[]=[];
for(const identity of identities){
 const auth=await fetch(API+'/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:status.ANON_KEY,'Content-Type':'application/json'},body:JSON.stringify({email:identity.email,password:'Synthetic-stress-only-2026!'})});
 assert(auth.ok,'Synthetic login failed '+identity.email);
 const session=await auth.json();
 const client=createClient(API,status.ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:'Bearer '+session.access_token},fetch:async(input:RequestInfo|URL,init?:RequestInit)=>{
   const url=String(input);assert(url.startsWith(API+'/'),'Refusing external request');
   const start=performance.now(),stage=currentStage;let response:Response|undefined,error:string|undefined;
   inflight++;maxInflight=Math.max(maxInflight,inflight);
   try{
    response=await fetch(input,{...init,signal:AbortSignal.timeout(30000)});
    if(!response.ok)error=(await response.clone().text()).slice(0,800);
    return response;
   }
   catch(e){error=String(e);throw e;}
   finally{inflight--;samples.push({stage,breeder:identity.label,route:new URL(url).pathname,milliseconds:Math.round(performance.now()-start),status:response?.status??0,error});}
 }}});
 clients.push({...identity,client});
}
const date=(d:Date)=>d.toISOString().slice(0,10);
const now=new Date(),start=date(new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth()-1,1))),end=date(new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth()+2,1)));
const percentile=(xs:number[],p:number)=>xs.length?xs.toSorted((a,b)=>a-b)[Math.min(xs.length-1,Math.ceil(p*xs.length)-1)]:null;
function summary(rows:any[]){const ms=rows.map(r=>r.milliseconds);return {requests:rows.length,p50_ms:percentile(ms,.5),p95_ms:percentile(ms,.95),max_ms:ms.length?Math.max(...ms):null,unexpected_http_errors:rows.filter(r=>r.status<200||r.status>=300).length};}
async function session(user:any,round:number){
 const db=user.client,t=performance.now();
 const animals=await allPages((a:number,b:number)=>db.from('animals').select().eq('ring_id',user.ring).eq('pedigree_only',false).order('created_at').order('id').range(a,b));
 assert(animals.length===1000,user.label+': herd incomplete');
 assert(animals.every((a:any)=>a.ring_id===user.ring),user.label+': foreign animals');
 const queries=await Promise.allSettled([
  allPages((a:number,b:number)=>db.from('animal_weights').select().eq('animal_id',user.animal).order('recorded_at',{ascending:false}).order('id').range(a,b)),
  allPages((a:number,b:number)=>db.from('animal_health_records').select().eq('animal_id',user.animal).order('administered_date',{ascending:false}).order('id').range(a,b)),
  calendarRecords(db,user.ring,start,end),
 ]);
 const failed=queries.find(r=>r.status==='rejected');
 if(failed?.status==='rejected')throw failed.reason;
 const [weights,health,calendar]=queries.map(r=>(r as PromiseFulfilledResult<any>).value);
 assert(weights.length>=user.min_weights&&health.length>=user.min_health,user.label+': history truncated');
 assert(calendar.health.every((h:any)=>h.animal.ring_id===user.ring),user.label+': calendar isolation failed');
 const foreign=clients[(user.index+1)%clients.length];
 const denied=await db.from('animals').select('id').eq('ring_id',foreign.ring).limit(1);
 assert(!denied.error&&denied.data.length===0,user.label+': another family exposed');
 const id=crypto.randomUUID();
 const inserted=await db.from('animal_weights').insert({id,animal_id:user.animal,weight:4.6,recorded_at:new Date().toISOString()});
 assert(!inserted.error,user.label+': save failed '+JSON.stringify(inserted.error));
 const saved=await db.from('animal_weights').select('id,weight').eq('id',id);
 assert(!saved.error&&saved.data.length===1&&saved.data[0].weight===4.6,user.label+': saved record mismatch');
 return {breeder:user.label,round,animals:animals.length,weights:weights.length,health:health.length,calendar_health:calendar.health.length,milliseconds:Math.round(performance.now()-t),saved_id:id};
}
const baselineOnly=Deno.args.includes('--baseline-only');
const output=baselineOnly?'deliverables/scaling-fixes/multiuser-baseline-results.json':'deliverables/scaling-fixes/multiuser-load-results.json';
for(const concurrency of baselineOnly?[1]:[1,10,25,50]){
 currentStage=concurrency;maxInflight=0;const outcomes:any[]=[];
 const started=performance.now(),before=samples.length;
 for(let round=0;round<3;round++){
  await Promise.all(clients.slice(0,concurrency).map(async(user:any)=>{
   try{outcomes.push({passed:true,...await session(user,round)});}
   catch(e){outcomes.push({breeder:user.label,round,passed:false,error:e instanceof Error?String(e):JSON.stringify(e)});}
  }));
 }
 const rows=samples.slice(before);
 const routes=Object.fromEntries([...new Set(rows.map(r=>r.route))].map(route=>[route,summary(rows.filter(r=>r.route===route))]));
 const stage={concurrent_breeders:concurrency,rounds:3,seconds:Math.round((performance.now()-started)/1000),sessions:outcomes.length,failed_sessions:outcomes.filter(r=>!r.passed).length,max_inflight_requests:maxInflight,...summary(rows),routes,outcomes};
 stages.push(stage);
 console.log(JSON.stringify({...stage,outcomes:undefined}));
 await Deno.writeTextFile(output,JSON.stringify({environment:'isolated local Supabase; not a production hosting capacity result',breeders:50,animals:50000,history_rows:990000,stages,samples},null,2)+'\n');
}
if(stages.some(s=>s.failed_sessions||s.unexpected_http_errors))Deno.exit(1);

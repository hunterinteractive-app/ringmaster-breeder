// Uses the real production calendar query/render helpers against localhost only.
import {createClient} from 'npm:@supabase/supabase-js@2.110.2';
import {calendarRecords} from '../../supabase/functions/_shared/calendar-records.mjs';
import {calendarEvents,subscriptionWindow,upcomingEvents} from '../../supabase/functions/calendar-feed/calendar.mjs';
const API='http://127.0.0.1:56433';
const RING='e1000000-0000-4000-8000-000000000010';
const OWNER='e1000000-0000-4000-8000-000000000001';
const MEMBER='e1000000-0000-4000-8000-000000000002';
const OUTSIDER='e1000000-0000-4000-8000-000000000003';
const encoder=new TextEncoder();
const b64=(s:Uint8Array)=>btoa(String.fromCharCode(...s)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
const header=b64(encoder.encode(JSON.stringify({alg:'HS256',typ:'JWT'})));
const key=await crypto.subtle.importKey('raw',encoder.encode('ringmaster-breeder-local-scale-test-secret-only-2026'),{name:'HMAC',hash:'SHA-256'},false,['sign']);
let calls=0, rowsTransferred=0;
async function client(actor:string) {
 const payload=b64(encoder.encode(JSON.stringify({role:'authenticated',sub:actor,exp:Math.floor(Date.now()/1000)+3600})));
 const body=header+'.'+payload;
 const token=body+'.'+b64(new Uint8Array(await crypto.subtle.sign('HMAC',key,encoder.encode(body))));
 return createClient(API,'local-fixture',{auth:{persistSession:false},global:{headers:{Authorization:'Bearer '+token},fetch:async(input,init)=>{
   const url=String(input).replace('/rest/v1/','/');
   if(!url.startsWith(API+'/'))throw Error('This test only permits localhost');
   calls++;
   const r=await fetch(url,init);
   if(r.ok){const data=await r.clone().json();if(Array.isArray(data))rowsTransferred+=data.length;}
   return r;
 }}});
}
function assert(test:unknown,message:string){if(!test)throw Error(message);}
const day=(d:Date)=>d.toISOString().slice(0,10);
const now=new Date(), today=day(now), month=now.getUTCMonth(), year=now.getUTCFullYear();
const start=day(new Date(Date.UTC(year,month-1,1))),end=day(new Date(Date.UTC(year,month+2,1)));
const db=await client(OWNER);
const results=[];
for(const [label,from,to] of [['app_three_months',start,end],['phone_last_month_onward',subscriptionWindow(now,'UTC').start,null]] as const){
 const beforeCalls=calls,beforeRows=rowsTransferred,t0=performance.now();
 const records=await calendarRecords(db,RING,from,to);
 const all=calendarEvents(records.breedings,Object.fromEntries(records.settings.map((s:any)=>[s.species,s])),records.health,[]);
 const events=upcomingEvents(all,{start:from,end:to});
 const elapsed=Math.round(performance.now()-t0);
 // Independently compute every health date from the 300000 source fixtures.
 let expected=0;
 const add=(n:number)=>day(new Date(new Date(today+'T12:00:00Z').getTime()+n*86400000));
 for(let i=1;i<=300000;i++){
   const dates=[add(-(i%7300)),...(i%100===0?[add(i%180)]:[]),...(i%200===0?[add(365+i%180)]:[])];
   expected+=dates.filter(d=>d>=from&&(!to||d<to)).length;
 }
 const healthCount=events.filter((e:any)=>e.id.startsWith('health-')).length;
 assert(healthCount===expected,`${label}: health event mismatch ${healthCount} != ${expected}`);
 assert(events.every((e:any)=>e.date>=from&&(!to||e.date<to)),label+': event outside window');
 assert(records.health.length<300000,label+': downloaded all historical health records');
 if(to===null)assert(events.some((e:any)=>e.date>=day(new Date(Date.UTC(year+1,month,1)))),'future events were cut off');
 results.push({test:label,passed:true,milliseconds:elapsed,api_requests:calls-beforeCalls,source_rows_transferred:rowsTransferred-beforeRows,health_records_loaded:records.health.length,retained_events:events.length,expected_health_events:expected});
}
const member=await client(MEMBER),outsider=await client(OUTSIDER);
const family=await calendarRecords(member,RING,start,end);
const foreign=await calendarRecords(outsider,RING,start,end);
assert(family.health.length>1000,'family history was truncated');
assert(foreign.health.length===0&&foreign.breedings.length===0,'calendar leaked another family');
results.push({test:'calendar_family_isolation',passed:true,member_health_records:family.health.length,outsider_health_records:foreign.health.length});
await Deno.writeTextFile('deliverables/database-calendar-results.json',JSON.stringify(results,null,2)+'\n');
for(const r of results)console.log(JSON.stringify(r));

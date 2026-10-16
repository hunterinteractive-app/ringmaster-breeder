import { createClient } from 'npm:@supabase/supabase-js@2.110.2';
import { calendarEvents, renderCalendar, subscriptionWindow, upcomingEvents } from './calendar.mjs';
import {calendarRecords, showInWindow} from '../_shared/calendar-records.mjs';
const headers={'Cache-Control':'private, no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff'};
const options={auth:{persistSession:false},global:{fetch:(input:RequestInfo|URL,init?:RequestInit)=>fetch(input,{...init,signal:AbortSignal.timeout(20000)})}};
Deno.serve(async req=>{
 if(!['GET','HEAD'].includes(req.method))return new Response('Method not allowed',{status:405,headers});
 try{
  const token=new URL(req.url).searchParams.get('token')??'';
  if(!/^[a-f0-9]{64}$/.test(token))return new Response('Calendar unavailable',{status:404,headers});
  const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,options);
  const lookup=await admin.rpc('resolve_calendar_subscription',{p_token:token});
  if(lookup.error)throw lookup.error;
  const sub=lookup.data;
  if(!sub)return new Response('Calendar unavailable',{status:404,headers});
  const feedHeaders={...headers,'Content-Type':'text/calendar; charset=utf-8','Content-Disposition':'inline; filename="ringmaster-herd.ics"'};
  if(req.method==='HEAD')return new Response(null,{headers:feedHeaders});
  const now=new Date(), window=subscriptionWindow(now,sub.timezone);
  const [records,link]=await Promise.all([
   calendarRecords(admin,sub.ring_id,window.start,window.end),
   admin.from('show_connections').select('show_user_id,user_id').eq('user_id',sub.owner_auth_id).maybeSingle(),
  ]);
  if(link.error)throw link.error;
  const shows:any[]=[];
  if(link.data){
   const showUrl=Deno.env.get('SHOW_SUPABASE_URL'),showKey=Deno.env.get('SHOW_SUPABASE_SERVICE_ROLE_KEY');
   if(!showUrl||!showKey)throw Error('Show integration unavailable');
   const show=createClient(showUrl,showKey,options);
   const [owner,remote]=await Promise.all([admin.auth.admin.getUserById(link.data.user_id),show.auth.admin.getUserById(link.data.show_user_id)]);
   if(owner.error||remote.error)throw Error('Show identity unavailable');
   // A broken identity link must stop exporting its Show records.
   if(owner.data.user?.email_confirmed_at&&remote.data.user?.email_confirmed_at&&owner.data.user.email?.trim().toLowerCase()===remote.data.user.email?.trim().toLowerCase()){
    let after:string|null=null;
    for(;;){const page:any=await show.rpc('breeder_calendar_export',{p_owner:link.data.show_user_id,p_after:after});if(page.error)throw page.error;const rows:any[]=page.data??[];shows.push(...rows.map((r:any)=>r.payload).filter((s:any)=>showInWindow(s,window.start,window.end)));if(rows.length===0)break;after=rows[rows.length-1].id;}
   }
  }
  // Recheck revocation after loading records so a link disabled during this request stops here.
  const current=await admin.rpc('resolve_calendar_subscription',{p_token:token});
  if(current.error)throw current.error;
  if(!current.data||current.data.id!==sub.id||current.data.owner_id!==sub.owner_id)return new Response('Calendar unavailable',{status:404,headers});
  const events=upcomingEvents(calendarEvents(records.breedings,Object.fromEntries(records.settings.map((s:any)=>[s.species,s])),records.health,shows,sub.timezone),window);
  return new Response(renderCalendar(sub.name,events),{headers:feedHeaders});
 }catch(error){
  // Never log the private subscription URL or token.
  console.error('calendar-feed failed',{code:(error as any)?.code??'request_failed'});
  return new Response('Calendar temporarily unavailable. Please retry.',{status:503,headers:{...headers,'Retry-After':'300'}});
 }
});

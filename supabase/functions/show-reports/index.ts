import { createClient } from 'npm:@supabase/supabase-js@2.110.2';
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
const reply = (data:unknown,status=200) => new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json'}});
const options = {auth:{persistSession:false},global:{fetch:(input:RequestInfo|URL,init?:RequestInit)=>fetch(input,{...init,signal:AbortSignal.timeout(20000)})}};
async function exported(show:any, owner:string, kind:string) {
 const all:any[]=[]; let after:string|null=null;
 for (;;) {
  const result=await show.rpc('breeder_report_export',{p_owner:owner,p_kind:kind,p_after:after});
  if(result.error)throw result.error;
  const page=result.data??[];
  all.push(...page.map((r:any)=>r.payload));
  if(all.length>10000)throw Error('Report limit exceeded');
  if(page.length<500)return all;
  after=page[page.length-1].id;
 }
}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return reply({});
 if(req.method!=='POST')return reply({error:'Method not allowed'},405);
 let admin:any, connection:any, action='';
 try {
  const body=await req.json(); action=body.action;
  if(!['enable','disable','refresh','download'].includes(action))return reply({error:'Unknown action'},400);
  const url=Deno.env.get('SUPABASE_URL')!;
  const token=(req.headers.get('Authorization')??'').replace(/^Bearer /i,'');
  admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,options);
  const auth=await admin.auth.getUser(token);const user=auth.data.user;
  if(auth.error||!user?.email_confirmed_at)return reply({error:'Sign in to Breeder again.'},401);
  const own=await admin.from('users').select('id').eq('auth_user_id',user.id).single();if(own.error)throw own.error;
  const owner=body.owner_id??own.data.id;
  if(owner!==own.data.id){
   if(action==='enable'||action==='disable')return reply({error:'Only the account owner can change report receiving.'},403);
   const scoped=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{...options,global:{...options.global,headers:{Authorization:`Bearer ${token}`}}});
   const access=await scoped.rpc('breeder_family_access',{p_action:'list'});
   if(access.error||!access.data?.households?.some((h:any)=>h.owner_user_id===owner))return reply({error:'Family access denied.'},403);
  }
  const identity=await admin.from('users').select('auth_user_id').eq('id',owner).eq('is_active',true).single();if(identity.error)throw identity.error;
  const found=await admin.from('show_connections').select('*').eq('user_id',identity.data.auth_user_id).maybeSingle();if(found.error)throw found.error;connection=found.data;
  if(!connection)return action==='refresh'?reply({skipped:true}):reply({error:'Connect RingMaster Show first.'},409);
  if(action==='enable'||action==='disable'){
   const updated=await admin.from('show_connections').update({reports_enabled:action==='enable',reports_changed_at:new Date().toISOString(),last_reports_error:null}).eq('id',connection.id);
   if(updated.error)throw updated.error;
   return reply({enabled:action==='enable'});
  }
  if(action==='refresh'&&!connection.reports_enabled)return reply({skipped:true});
  const showUrl=Deno.env.get('SHOW_SUPABASE_URL'),showKey=Deno.env.get('SHOW_SUPABASE_SERVICE_ROLE_KEY');
  if(!showUrl||!showKey)return reply({error:'Show report receiving is not configured.'},503);
  const show=createClient(showUrl,showKey,options);
  const [ownerAuth,showAuth]=await Promise.all([admin.auth.admin.getUserById(connection.user_id),show.auth.admin.getUserById(connection.show_user_id)]);
  if(ownerAuth.error||showAuth.error||!ownerAuth.data.user?.email_confirmed_at||!showAuth.data.user?.email_confirmed_at||ownerAuth.data.user.email?.trim().toLowerCase()!==showAuth.data.user.email?.trim().toLowerCase())return reply({error:'Both connected accounts must use the same verified email.'},409);
  const started=new Date().toISOString();
  const reports=await exported(show,connection.show_user_id,'reports');
  if(action==='download'){
   const saved=await admin.from('connected_show_reports').select('id').eq('id',body.report_id).eq('connection_id',connection.id).maybeSingle();if(saved.error)throw saved.error;
   const report=saved.data&&reports.find((r:any)=>r.id===body.report_id);
   if(!report)return reply({error:'This report is no longer available from Show. Refresh the report list.'},404);
   const signed=await show.storage.from(report.storage_bucket).createSignedUrl(report.storage_path,120,{download:report.file_name??'report.pdf'});
   if(signed.error)throw signed.error;
   return reply({url:signed.data.signedUrl});
  }
  const results=await exported(show,connection.show_user_id,'results');
  const saved=await admin.rpc('apply_connected_show_reports',{p_connection:connection.id,p_version:connection.reports_changed_at,p_started:started,p_reports:reports,p_results:results});
  if(saved.error)throw saved.error;
  return reply(saved.data);
 }catch(error){
  console.error('show-reports failed',{action,code:(error as any)?.code??'request_failed'});
  if(connection&&admin&&action==='refresh')await admin.from('show_connections').update({last_reports_error:'Unable to refresh show reports. Previously received reports are still available.'}).eq('id',connection.id);
  return reply({error:action==='download'?'Unable to open this report. Please retry.':'Unable to update show reports. Previously received reports are still available.'},503);
 }
});

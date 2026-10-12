import { createClient } from 'npm:@supabase/supabase-js@2.110.2';
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json'}});
const options={auth:{persistSession:false},global:{fetch:(input:RequestInfo|URL,init?:RequestInit)=>fetch(input,{...init,signal:AbortSignal.timeout(20000)})}};
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return reply({});
 if(req.method!=='POST')return reply({error:'Method not allowed'},405);
 try {
  const token=(req.headers.get('Authorization')??'').replace(/^Bearer /i,'');
  const url=Deno.env.get('SUPABASE_URL')!;
  const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,options);
  const auth=await admin.auth.getUser(token);
  if(auth.error||!auth.data.user?.email_confirmed_at)return reply({error:'Sign in to Breeder again.'},401);
  const body=await req.json();
  if(typeof body.ring_id!=='string')return reply({error:'Choose a herd.'},400);
  // Resolve ownership through the caller's RLS scope, never trust a supplied owner ID.
  const scoped=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{...options,global:{...options.global,headers:{Authorization:`Bearer ${token}`}}});
  const herd=await scoped.from('farms').select('owner_id').eq('id',body.ring_id).maybeSingle();
  if(herd.error||!herd.data)return reply({error:'Herd access denied.'},403);
  const owner=await admin.from('users').select('auth_user_id').eq('id',herd.data.owner_id).eq('is_active',true).single();
  if(owner.error)return reply({error:'Account unavailable.'},403);
  const found=await admin.from('show_connections').select('show_user_id,user_id').eq('user_id',owner.data.auth_user_id).maybeSingle();
  if(found.error)throw found.error;
  if(!found.data)return reply({connected:false,shows:[]});
  const showUrl=Deno.env.get('SHOW_SUPABASE_URL'),showKey=Deno.env.get('SHOW_SUPABASE_SERVICE_ROLE_KEY');
  if(!showUrl||!showKey)throw Error('Integration unavailable');
  const show=createClient(showUrl,showKey,options);
  const [breederAuth,showAuth]=await Promise.all([admin.auth.admin.getUserById(found.data.user_id),show.auth.admin.getUserById(found.data.show_user_id)]);
  const b=breederAuth.data.user,s=showAuth.data.user;
  if(breederAuth.error||showAuth.error||!b?.email_confirmed_at||!s?.email_confirmed_at||b.email?.trim().toLowerCase()!==s.email?.trim().toLowerCase())return reply({error:'Reconnect Show using the same verified email.'},409);
  const shows:any[]=[];let after:string|null=null;
  for(;;){
   const page=await show.rpc('breeder_calendar_export',{p_owner:found.data.show_user_id,p_after:after});
   if(page.error)throw page.error;
   const rows=page.data??[];shows.push(...rows.map((r:any)=>r.payload));
   if(shows.length>10000)throw Error('Calendar limit exceeded');
   if(rows.length<500)break;
   after=rows[rows.length-1].id;
  }
  return reply({connected:true,shows,refreshed_at:new Date().toISOString()});
 }catch(error){
  console.error('show-calendar failed',{code:(error as any)?.code??'request_failed'});
  return reply({error:'Unable to refresh entered shows. Please retry.'},503);
 }
});

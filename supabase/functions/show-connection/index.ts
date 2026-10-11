import { createClient } from 'npm:@supabase/supabase-js@2.110.2';
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...headers,'Content-Type':'application/json'}});
const options={auth:{persistSession:false},global:{fetch:(input:RequestInfo|URL,init?:RequestInit)=>fetch(input,{...init,signal:AbortSignal.timeout(20000)})}};
async function rows(query:(a:number,b:number)=>PromiseLike<{data:any,error:any}>) { const out:any[]=[];for(let a=0;;a+=500){const r=await query(a,a+499);if(r.error)throw r.error;out.push(...r.data);if(r.data.length<500)return out;if(out.length>=10000)throw Error('Herd exceeds connection limit');} }
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return reply({});
 if(req.method!=='POST')return reply({error:'Method not allowed'},405);
 let admin:any,connection:any;
 let settingsSaved=false;
 try{
  const body=await req.json();
  if(!['status','connect','save','disconnect','sync','pull'].includes(body.action))return reply({error:'Unknown action'},400);
  const showUrl=Deno.env.get('SHOW_SUPABASE_URL'),showKey=Deno.env.get('SHOW_SUPABASE_SERVICE_ROLE_KEY');
  if(!showUrl||!showKey)return reply({error:'Show connection is not configured'},503);
  admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,options);
  const show=createClient(showUrl,showKey,options);
  const token=(req.headers.get('Authorization')??'').replace(/^Bearer /i,'');
  let user:any,herds:any[]=[];
  if(body.action==='pull'){
   const verified=await show.auth.getUser(token);user=verified.data.user;
   if(verified.error||!user?.email_confirmed_at)return reply({error:'Sign in to Show again'},401);
   const owner=body.owner_id??user.id;
   if(owner!==user.id){
    const scoped=createClient(showUrl,showKey,{...options,global:{...options.global,headers:{Authorization:`Bearer ${token}`}}});
    const access=await scoped.rpc('household_access',{p_action:'list'});
    if(access.error||!access.data?.households?.some((h:any)=>h.owner_user_id===owner))return reply({error:'Household access denied'},403);
   }
   const found=await admin.from('show_connections').select('*').eq('show_user_id',owner).maybeSingle();if(found.error)throw found.error;connection=found.data;
   if(!connection)return reply({connected:false,count:0});
  }else{
   const verified=await admin.auth.getUser(token);user=verified.data.user;
   if(verified.error||!user?.email_confirmed_at)return reply({error:'Sign in to Breeder again'},401);
   const identity=await admin.from('users').select('id').eq('auth_user_id',user.id).single();if(identity.error)throw identity.error;
   herds=await rows((a,b)=>admin.from('farms').select('id,name').eq('owner_id',identity.data.id).eq('is_demo',false).order('id').range(a,b));
   const found=await admin.from('show_connections').select('*').eq('user_id',user.id).maybeSingle();if(found.error)throw found.error;connection=found.data;
   const deleting=await admin.from('account_deletions').select('user_id').eq('user_id',user.id).maybeSingle();if(deleting.error)throw deleting.error;
   if(deleting.data)return reply({error:'Account deletion is in progress.'},409);
   if(body.action==='status')return reply({connection,herds});
   if(body.action==='connect'){
    const match=await show.rpc('breeder_verified_account',{p_email:user.email});if(match.error)throw match.error;
    if(!match.data)return reply({error:'Sign in to RingMaster Show with the same verified email first.'},409);
    if(connection&&connection.show_user_id!==match.data)return reply({error:'The linked Show account differs. Contact support before relinking.'},409);
    if(!connection){const created=await admin.from('show_connections').insert({user_id:user.id,show_user_id:match.data}).select().single();if(created.error)throw created.error;connection=created.data;}
    return reply({connection,herds});
   }
   if(!connection)return reply({error:'Connect your Show account first'},409);
   if(body.action==='save'||body.action==='disconnect'){
    const ids=body.action==='disconnect'?[]:body.herd_ids;
    if(!Array.isArray(ids)||ids.some(id=>!herds.some(h=>h.id===id)))return reply({error:'Choose only herds you own'},403);
    const saved=await admin.from('show_connections').update({herd_ids:[...new Set(ids)],enabled:body.action!=='disconnect'&&ids.length>0,updated_at:new Date().toISOString()}).eq('id',connection.id).select().single();if(saved.error)throw saved.error;connection=saved.data;settingsSaved=true;
   }
  }
  // Recheck source ownership and verified account identity on every refresh.
  const ownerAuth=await admin.auth.admin.getUserById(connection.user_id);
  const showAuth=await show.auth.admin.getUserById(connection.show_user_id);
  if(connection.enabled&&(!ownerAuth.data.user?.email_confirmed_at||!showAuth.data.user?.email_confirmed_at||ownerAuth.data.user.email?.toLowerCase()!==showAuth.data.user.email?.toLowerCase()))return reply({error:'Account email verification changed. Reconnect with matching verified emails.'},409);
  const identity=await admin.from('users').select('id').eq('auth_user_id',connection.user_id).single();if(identity.error)throw identity.error;
  const owned=await rows((a,b)=>admin.from('farms').select('id').eq('owner_id',identity.data.id).eq('is_demo',false).order('id').range(a,b));
  const ids=connection.enabled?connection.herd_ids.filter((id:string)=>owned.some(h=>h.id===id)):[];
  const animals=ids.length?await rows((a,b)=>admin.from('animals').select('id,name,tattoo,species,breed,variety,sex,dob,color_details').in('ring_id',ids).eq('status','active').eq('pedigree_only',false).order('id').range(a,b)):[];
  const imports=await rows((a,b)=>admin.from('breeder_imported_animals').select('animal_id,source_id').eq('owner_id',identity.data.id).eq('source_app','ringmaster_show').order('animal_id').range(a,b));
  const provenance=new Map(imports.map(a=>[a.animal_id,a.source_id]));
  const result=await show.rpc('apply_breeder_animals',{p_connection:connection.id,p_owner:connection.show_user_id,p_version:connection.updated_at,p_animals:animals.map(a=>({...a,show_id:provenance.get(a.id)??null,pattern:a.color_details?.pattern??'',sex:['M','Buck','Boar'].includes(a.sex)?(a.species==='cavy'?'Boar':'Buck'):['F','Doe','Sow'].includes(a.sex)?(a.species==='cavy'?'Sow':'Doe'):null}))});if(result.error)throw result.error;
  await admin.from('show_connections').update({last_synced_at:new Date().toISOString(),last_error:null}).eq('id',connection.id).eq('updated_at',connection.updated_at);
  return reply({connected:connection.enabled,count:result.data});
 }catch(error){
  console.error('show-connection failed', {code:(error as any)?.code??'request_failed'});
  if(connection&&admin)await admin.from('show_connections').update({last_error:'Refresh failed. Please retry.'}).eq('id',connection.id);
  return reply({error:settingsSaved?'Your herd settings were saved, but syncing failed. Please retry.':'Unable to complete the connection request. Please retry.'},503);
 }
});

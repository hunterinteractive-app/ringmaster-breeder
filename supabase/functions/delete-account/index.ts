import { createClient } from 'npm:@supabase/supabase-js@2.110.2';
import {StripeClient} from '../_shared/stripe.ts';
import {cancelOwnerSubscriptions} from '../_shared/billing-state.ts';
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json'}});
const options={auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(input:RequestInfo|URL,init?:RequestInit)=>fetch(input,{...init,signal:AbortSignal.timeout(20000)})}};
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return reply({});
 if(req.method!=='POST')return reply({error:'Method not allowed'},405);
 let started=false;let billingLease:string|undefined;let billingAdmin:any;
 try {
  const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,options);
  billingAdmin=admin;
  const token=(req.headers.get('Authorization')??'').replace(/^Bearer /i,'');
  const verified=await admin.auth.getUser(token);const user=verified.data.user;
  if(verified.error||!user?.email_confirmed_at||!user.email)return reply({error:'Sign in again to manage your account.'},401);
  const body=await req.json();
  if(!['request-code','delete','resume'].includes(body.action))return reply({error:'Unknown action'},400);
  const pending=await admin.from('account_deletions').select('*').eq('user_id',user.id).maybeSingle();if(pending.error)throw pending.error;
  let job=pending.data;started=!!job;
  if(body.action==='request-code'){
   const auth=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,options);
   const sent=await auth.auth.signInWithOtp({email:user.email,options:{shouldCreateUser:false}});
   if(sent.error)return reply({error:'Unable to send a code. Wait a minute and try again.'},429);
   return reply({sent:true});
  }
  if(!job){
   if(body.action!=='delete'||body.confirmation!=='DELETE'||typeof body.code!=='string')return reply({error:'Confirm deletion and enter the code sent to your email.'},400);
   // Use a separate Auth client: verification must not replace the admin token.
   const auth=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,options);
   const fresh=await auth.auth.verifyOtp({email:user.email,token:body.code.trim(),type:'email'});
   if(fresh.error||fresh.data.user?.id!==user.id)return reply({error:'The code is invalid or expired. Request a new code.'},403);
   const owner=await admin.from('users').select('id').eq('auth_user_id',user.id).single();if(owner.error)throw owner.error;
   billingLease=crypto.randomUUID();const lease=await admin.rpc('breeder_billing_lease',{p_owner:owner.data.id,p_token:billingLease,p_release:false});if(lease.error)throw lease.error;
   const stripe=new StripeClient();await stripe.verifyAccount();
   await cancelOwnerSubscriptions(admin,stripe,owner.data.id,true);
   const invitations=await admin.from('breeder_lifetime_invitations').select('*').eq('owner_id',owner.data.id).eq('active',true);if(invitations.error)throw invitations.error;
   for(const invitation of invitations.data){if(invitation.stripe_link)await stripe.request(`payment_links/${invitation.stripe_link}`,'POST',{active:false},`delete-link:${invitation.id}`);}
   const open=await admin.from('breeder_billing_checkouts').select('*').eq('owner_id',owner.data.id).in('state',['creating','open']);if(open.error)throw open.error;
   for(const checkout of open.data){if(!checkout.stripe_session)throw Error('Checkout creation must finish before deletion');const session=await stripe.request(`checkout/sessions/${checkout.stripe_session}`);if(session.status==='open')await stripe.request(`checkout/sessions/${session.id}/expire`,'POST',{},`delete-checkout:${checkout.id}`);}
   // Recheck after expiring checkouts to catch a purchase completing concurrently.
   await cancelOwnerSubscriptions(admin,stripe,owner.data.id,true);
   const begin=await admin.rpc('begin_account_deletion',{p_user:user.id});if(begin.error)throw begin.error;job=begin.data;started=true;
  }
  if(job.connection){
   const showUrl=Deno.env.get('SHOW_SUPABASE_URL'),showKey=Deno.env.get('SHOW_SUPABASE_SERVICE_ROLE_KEY');
   if(!showUrl||!showKey)throw Error('Show unavailable');
   const show=createClient(showUrl,showKey,options);
   // Infinity permanently retires this connection, including in-flight snapshots.
   const stopped=await show.rpc('apply_breeder_animals',{p_connection:job.connection.id,p_owner:job.connection.show_user_id,p_version:'infinity',p_animals:[]});
   if(stopped.error)throw stopped.error;
  }
  for(const bucket of ['animal_photos','health_attachments','offline_results']){
   const names=job.files.filter((f:any)=>f.bucket===bucket).map((f:any)=>f.name);
   for(let i=0;i<names.length;i+=100){const removed=await admin.storage.from(bucket).remove(names.slice(i,i+100));if(removed.error)throw removed.error;}
  }
  const purged=await admin.rpc('purge_account_data',{p_user:user.id});if(purged.error)throw purged.error;
  const deleted=await admin.auth.admin.deleteUser(user.id);if(deleted.error)throw deleted.error;
  return reply({deleted:true});
 } catch(error){
  console.error('delete-account failed',{code:(error as any)?.code??'request_failed'});
  const shared=(error as any)?.message?.includes('ACCOUNT_SHARED_DATA_REVIEW');
  return reply({pending:started,error:shared?'Some records are shared with another account. Contact support to resolve ownership before deletion.':started?'Deletion has started but could not finish. Your account is locked; choose Resume deletion to finish.':'Unable to start account deletion. Your account has not been deleted. Please retry.'},503);
 } finally {if(billingLease && billingAdmin)await billingAdmin.rpc('breeder_billing_lease',{p_token:billingLease,p_release:true});}
});

import { createClient } from 'npm:@supabase/supabase-js@2.110.2';
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Content-Type':'application/json'};
let lastSuccess=0;
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 if(req.method!=='POST')return reply({error:'Method not allowed'},405);
 const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
 const token=req.headers.get('Authorization')?.replace(/^Bearer /i,'')??'';
 const {data:{user},error:authError}=await db.auth.getUser(token);
 if(authError||!user?.email_confirmed_at)return reply({error:'Sign in required'},401);
 if(Date.now()-lastSuccess<300000)return reply({cached:true});
 try{
 const show=createClient(Deno.env.get('SHOW_SUPABASE_URL')!,Deno.env.get('SHOW_SUPABASE_SERVICE_ROLE_KEY')!);
 const {data:breeds,error}=await show.from('breeds').select('id,name,species,varieties(id,name,is_active)').eq('is_active',true).is('local_show_id',null);
 if(error||!breeds?.length)throw error??new Error('Empty source catalog');
 let count=0;
 for(const b of breeds){
 const {data:local,error:e}=await db.from('breeds').upsert({species:b.species,name:b.name,is_recognized:true,show_id:b.id},{onConflict:'species,catalog_key'}).select('id').single();
 if(e)throw e;
 const rows=(b.varieties??[]).filter(v=>v.is_active).map(v=>({breed_id:local.id,name:v.name,is_recognized:true,show_id:v.id}));
 if(rows.length){const {error:e}=await db.from('varieties').upsert(rows,{onConflict:'breed_id,catalog_key'});if(e)throw e;count+=rows.length;}
 }
 lastSuccess=Date.now();
 return reply({breeds:breeds.length,varieties:count});
 }catch(e){console.error('Catalog sync failed',e);return reply({error:'Catalog refresh unavailable. Saved catalog remains available.'},503);}
});

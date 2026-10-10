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
 const {data:knownBreeds,error:knownError}=await db.from('breeds').select('id,show_id');
 if(knownError)throw knownError;
 const {data:knownVarieties,error:varietyError}=await db.from('varieties').select('id,show_id');
 if(varietyError)throw varietyError;
 let count=0;
 for(const b of breeds){
 const known=knownBreeds?.find(row=>row.show_id===b.id);
 const values={species:b.species,name:b.name,is_recognized:true,show_id:b.id};
 const request=known?db.from('breeds').update(values).eq('id',known.id):db.from('breeds').upsert(values,{onConflict:'species,catalog_key'});
 const {data:local,error:e}=await request.select('id').single();
 if(e)throw e;
 const rows=(b.varieties??[]).filter(v=>v.is_active).map(v=>({breed_id:local.id,name:v.name,is_recognized:true,show_id:v.id}));
 const existing=rows.filter(row=>knownVarieties?.some(v=>v.show_id===row.show_id)).map(row=>({...row,id:knownVarieties!.find(v=>v.show_id===row.show_id)!.id}));
 const added=rows.filter(row=>!knownVarieties?.some(v=>v.show_id===row.show_id));
 if(existing.length){const {error:e}=await db.from('varieties').upsert(existing,{onConflict:'id'});if(e)throw e;}
 if(added.length){const {error:e}=await db.from('varieties').upsert(added,{onConflict:'breed_id,catalog_key'});if(e)throw e;}
 count+=rows.length;
 }
 lastSuccess=Date.now();
 return reply({breeds:breeds.length,varieties:count});
 }catch(e){console.error('Catalog sync failed',e);return reply({error:'Catalog refresh unavailable. Saved catalog remains available.'},503);}
});

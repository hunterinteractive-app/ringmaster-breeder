// Compare the tested renderer with the pre-fix allocation-heavy fold, loaded in memory.
import {readFile} from 'node:fs/promises';
import {renderCalendar as current} from '../../supabase/functions/calendar-feed/calendar.mjs';
const source=await readFile(new URL('../../supabase/functions/calendar-feed/calendar.mjs',import.meta.url),'utf8');
const candidate=source.replace(/export function fold\(line\) \{[\s\S]*?\n\}/, "export function fold(line){let out='',part='',bytes=0;for(const char of line){const size=new TextEncoder().encode(char).length;if(bytes+size>75){out+=part+'\\r\\n';part=' ';bytes=1;}part+=char;bytes+=size;}return out+part;}");
if(candidate===source)throw Error('The pre-fix baseline substitution did not match');
const {renderCalendar:baseline}=await import('data:text/javascript;base64,'+Buffer.from(candidate).toString('base64'));
const rows=[];
for(const count of [1000,6500,20000]){
 const events=Array.from({length:count},(_,i)=>({id:`health-synthetic-${i}-administered_date`,date:'2026-11-01',title:`Health record • Synthetic history ${i} • Synthetic animal ${i%1000} • SCALE-${i%1000} 🐇`,description:'Manage this health record in RingMaster Breeder.'}));
 const now=new Date('2026-10-16T12:00:00Z');
 const original=current('Synthetic 1000 animal herd',events,now);
 const revised=baseline('Synthetic 1000 animal herd',events,now);
 if(original!==revised)throw Error('Pre-fix and fixed folding produced different output');
 for(const [label,render] of [['fixed',current],['pre_fix',baseline]]){
  const times=[];
  for(let i=0;i<3;i++){
   const cpu=process.cpuUsage(),start=performance.now();
   const result=render('Synthetic 1000 animal herd',events,now);
   const used=process.cpuUsage(cpu);
   times.push({wall_ms:Math.round(performance.now()-start),cpu_ms:Math.round((used.user+used.system)/1000),bytes:Buffer.byteLength(result)});
  }
  rows.push({events:count,implementation:label,samples:times,identical_output:true});
 }
}
console.log(JSON.stringify(rows,null,2));

const day = (v) => String(v).slice(0,10);
const add = (v,n) => {const d=new Date(day(v)+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
const label = (a) => [a.name,a.tattoo].filter(Boolean).join(' • ') || 'Unnamed';
const defaults = (s) => s==='cavy'?{gestation_min:59,gestation_max:72,palpation_min:28,palpation_max:30,nesting_day:null,weaning_min:3,weaning_max:4}:{gestation_min:28,gestation_max:32,palpation_min:14,palpation_max:14,nesting_day:26,weaning_min:4,weaning_max:8};
function localDay(v,tz) {
 if(/^\d{4}-\d{2}-\d{2}$/.test(v))return v;
 const parts=new Intl.DateTimeFormat('en-US',{timeZone:tz,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(v));
 const get=(type)=>parts.find(p=>p.type===type).value;
 return `${get('year')}-${get('month')}-${get('day')}`;
}
export function calendarEvents(breedings,settings,health,shows,timezone='UTC') {
 const events=[];
 for(const r of breedings){
  const t=r.tracking??{},a=r.dam,status=t.status??r.status;
  if(status==='cancelled')continue;
  const c={...defaults(a.species),...(settings[a.species]??{})},base=day(r.breeding_date);
  const put=(key,title,date,description='')=>events.push({id:`breeding-${r.id}-${key}`,title:`${title} • ${label(a)}`,date,description});
  const window=(key,title,start,end)=>{
   const note=`Expected window: ${start} – ${end}. Based on your herd’s breeding settings; actual dates may vary.`;
   put(`${key}-start`,start===end?title:`${title} • Due window starts`,start,note);
   if(start!==end)put(`${key}-end`,`${title} • Final due day`,end,note);
  };
  put('bred','Breeding recorded',base);
  if(t.check_date)put('checked',`Palpation • ${t.check_result??'Recorded'}`,day(t.check_date));
  if(t.birth_date){
   put('born',a.species==='cavy'?'Pups born':'Kindled',day(t.birth_date));
   if(!t.wean_date&&status==='active')window('weaning','Expected weaning',add(t.birth_date,c.weaning_min*7),add(t.birth_date,c.weaning_max*7));
  }else if(status==='active'&&t.check_result!=='Negative'){
   if(!t.check_date)window('palpation','Palpation window',add(base,c.palpation_min),add(base,c.palpation_max));
   if(c.nesting_day!=null)put('nest','Add nesting box',add(base,c.nesting_day),'Expected date based on herd breeding settings.');
   window('birth','Expected birth',add(base,c.gestation_min),add(base,c.gestation_max));
  }
  if(t.wean_date)put('weaned','Weaned',day(t.wean_date));
 }
 for(const h of health)for(const [key,prefix] of [['administered_date','Health record'],['readminister_date','Follow-up due'],['expires_date','Expires']]){
  if(h[key])events.push({id:`health-${h.id}-${key}`,title:`${prefix} • ${h.title??h.record_type??'Health'} • ${label(h.animal)}`,date:localDay(h[key],timezone),description:'Manage this health record in RingMaster Breeder.'});
 }
 const seen=new Set();
 for(const s of shows){
  if(!s.start_date||seen.has(s.id))continue;seen.add(s.id);
  if(s.is_favorite && s.entry_close_at) events.push({id:`show-deadline-${s.id}`,title:`Entry deadline • ${s.name??'Favorite show'}`,date:localDay(s.entry_close_at,timezone),timestamp:s.entry_close_at,alarms:[1440,120],description:'Favorite show entry deadline. Reminders: 1 day and 2 hours before. Enter at https://show.ringmasterone.com. Calendar app alert support varies.'});
  if(Number(s.entry_count)>0) events.push({id:`show-${s.id}`,title:s.name??'Entered show',date:day(s.start_date),location:[s.location_name,s.location_address].filter(Boolean).join(', '),description:`Show dates: ${day(s.start_date)} – ${day(s.end_date??s.start_date)}. ${s.entry_count} active entries.\nEntered shows for this herd owner’s linked RingMaster Show account.\n${(s.entries??[]).map(e=>[label({name:e.animal_name,tattoo:e.tattoo}),e.breed,e.class_name].filter(Boolean).join(' • ')).join('\n')}`});
 }
 return events.sort((a,b)=>a.date.localeCompare(b.date)||a.id.localeCompare(b.id));
}
export function escapeText(v){return String(v??'').replace(/\\/g,'\\\\').replace(/\r\n|\r|\n/g,'\\n').replace(/;/g,'\\;').replace(/,/g,'\\,').replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g,'');}
export function fold(line) {
 let out='',part='',bytes=0;
 // Iterate code points so a fold never splits a UTF-8 character. Measuring the
 // width directly avoids allocating an encoder and byte array per character.
 for(const char of line){
  const point=char.codePointAt(0);
  const size=point<=0x7f?1:point<=0x7ff?2:point<=0xffff?3:4;
  if(bytes+size>75){out+=part+'\r\n';part=' ';bytes=1;}
  part+=char;bytes+=size;
 }
 return out+part;
}
export function renderCalendar(name,events,now=new Date()) {
 const stamp=now.toISOString().replace(/[-:]/g,'').replace(/\.\d{3}Z$/,'Z');
 const lines=['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//RingMaster Breeder//Herd Calendar//EN','CALSCALE:GREGORIAN',`X-WR-CALNAME:${escapeText(name+' • RingMaster Breeder')}`,'REFRESH-INTERVAL;VALUE=DURATION:PT6H','X-PUBLISHED-TTL:PT6H'];
 for(const e of events){
  lines.push('BEGIN:VEVENT',`UID:${e.id}@breeder.ringmasterone.com`,`DTSTAMP:${stamp}`,...(e.timestamp ? [`DTSTART:${new Date(e.timestamp).toISOString().replace(/[-:]/g,'').replace(/\.\d{3}Z$/,'Z')}`,`DTEND:${new Date(new Date(e.timestamp).getTime()+60000).toISOString().replace(/[-:]/g,'').replace(/\.\d{3}Z$/,'Z')}`] : [`DTSTART;VALUE=DATE:${e.date.replaceAll('-','')}`,`DTEND;VALUE=DATE:${add(e.date,1).replaceAll('-','')}`]),`SUMMARY:${escapeText(e.title)}`,`DESCRIPTION:${escapeText(e.description)}`,'CLASS:PRIVATE','TRANSP:TRANSPARENT');
  if(e.location)lines.push(`LOCATION:${escapeText(e.location)}`);
  for(const minutes of e.alarms??[]) lines.push('BEGIN:VALARM','ACTION:DISPLAY',`TRIGGER:-PT${minutes}M`,`DESCRIPTION:${escapeText(e.title)}`,'END:VALARM');
  lines.push('END:VEVENT');
 }
 lines.push('END:VCALENDAR');return lines.map(fold).join('\r\n')+'\r\n';
}

// Keep a small recent history without imposing any future event cutoff.
export function subscriptionWindow(now = new Date(), timezone = 'UTC') {
 const [year, month] = localDay(now.toISOString(), timezone).split('-').map(Number);
 return {start: new Date(Date.UTC(year, month - 2, 1)).toISOString().slice(0,10), end: null};
}
export function upcomingEvents(events, window) {
 return events.filter(e => e.date >= window.start && (!window.end || e.date < window.end));
}

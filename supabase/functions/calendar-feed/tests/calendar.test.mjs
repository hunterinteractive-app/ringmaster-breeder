import {test} from 'node:test';
import assert from 'node:assert/strict';
import {calendarEvents,renderCalendar} from '../calendar.mjs';
const record={id:'b1',breeding_date:'2026-10-01',status:'active',dam:{name:'Doe',tattoo:'D1',species:'rabbit'}};
test('windows use endpoints and stable identities',()=>{
 const a=calendarEvents([record],{},[],[]);
 assert.deepEqual(a.filter(e=>e.id.includes('birth')).map(e=>e.date),['2026-10-29','2026-11-02']);
 const b=calendarEvents([{...record,breeding_date:'2026-10-02'}],{},[],[]);
 assert.deepEqual(a.map(e=>e.id),b.map(e=>e.id));
 assert.equal(a.length,5);
});
test('actual births replace forecasts and cancelled/negative suppress estimates',()=>{
 const a=calendarEvents([{...record,tracking:{birth_date:'2026-10-30'}}],{},[],[]);
 assert.equal(a.filter(e=>e.id.includes('birth')).length,0);
 assert.deepEqual(a.filter(e=>e.id.includes('weaning')).map(e=>e.date),['2026-11-27','2026-12-25']);
 assert.equal(calendarEvents([{...record,status:'cancelled'}],{},[],[]).length,0);
 assert.equal(calendarEvents([{...record,tracking:{check_result:'Negative'}}],{},[],[]).length,1);
});
test('cavy defaults and herd overrides',()=>{
 const a=calendarEvents([{...record,dam:{...record.dam,species:'cavy'}}],{},[],[]);
 assert.equal(a.some(e=>e.id.endsWith('nest')),false);
 assert.deepEqual(a.filter(e=>e.id.includes('birth')).map(e=>e.date),['2026-11-29','2026-12-12']);
 assert.equal(calendarEvents([record],{rabbit:{gestation_min:30}},[],[]).find(e=>e.id.endsWith('birth-start')).date,'2026-10-31');
});
test('health timezone and deduplicated show dates',()=>{
 const a=calendarEvents([],{},[{id:'h1',animal:{tattoo:'A'},administered_date:'2026-11-02T02:00:00Z'}],[{id:'s1',start_date:'2026-11-04',end_date:'2026-11-06',entry_count:2},{id:'s1',start_date:'2026-11-04'}],'America/Indiana/Indianapolis');
 assert.equal(a[0].date,'2026-11-01');assert.equal(a.length,2);assert.match(a[1].description,/2026-11-06/);
});
test('RFC dates, escaping, Unicode folding and stable UID',()=>{
 const text=renderCalendar('Herd',[{id:'a',date:'2026-12-31',title:'🐇'.repeat(60)+'\nBEGIN:VEVENT',description:'a,b;c\\d'}],new Date('2026-10-01T12:00:00Z'));
 assert.match(text,/DTEND;VALUE=DATE:20270101/);assert.match(text,/UID:a@breeder/);
 assert.equal(text.split('\r\n').filter(l=>l==='BEGIN:VEVENT').length,1);
 assert.ok(text.split('\r\n').every(l=>Buffer.byteLength(l)<=75));
 assert.match(text.replaceAll('\r\n ',''),/\\nBEGIN:VEVENT/);
 assert.match(text,/DESCRIPTION:a\\,b\\;c\\\\d/);
});
test('favorites without entries have timed deadlines and both alerts',()=>{
 const s={id:'favorite',name:'Favorite Show',start_date:'2026-11-05',entry_count:0,is_favorite:true,entry_close_at:'2026-11-01T23:59:00-05:00'};
 const events=calendarEvents([],{},[],[s,s],'America/Indiana/Indianapolis');
 assert.equal(events.length,1); assert.equal(events[0].date,'2026-11-01');
 const feed=renderCalendar('Herd',events);
 assert.match(feed,/DTSTART:20261102T045900Z/);
 assert.match(feed,/TRIGGER:-PT1440M/);assert.match(feed,/TRIGGER:-PT120M/);
 assert.equal(calendarEvents([],{},[],[{...s,is_favorite:false}]).length,0);
 const changed=calendarEvents([],{},[],[{...s,entry_close_at:'2026-11-03T12:00:00Z'}]);
 assert.equal(changed[0].id,events[0].id);
 assert.equal(calendarEvents([],{},[],[{...s,entry_count:2}]).length,2);
 assert.equal(calendarEvents([],{},[],[{...s,entry_close_at:null}]).length,0);
});

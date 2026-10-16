import {test} from 'node:test';
import assert from 'node:assert/strict';
import {allPages,calendarRecords,showInWindow} from '../../_shared/calendar-records.mjs';
test('server pagination exceeds old 20000 limit and respects shorter server pages',async()=>{
 const rows=await allPages(async(a,b)=>({data:Array.from({length:Math.max(0,Math.min(30001-a,123))},(_,i)=>({id:a+i})),error:null}));
 assert.equal(rows.length,30001);assert.equal(rows.at(-1).id,30000);
 await assert.rejects(allPages(async()=>({data:null,error:new Error('failed')})),/failed/);
});
test('feed queries only bounded candidates, including tracking and health follow-ups',async()=>{
 const calls=[];
 const db={from(table){const call={table};calls.push(call);const query={};for(const name of ['select','eq','gte','lt','or','order'])query[name]=(...args)=>{call[name]=args;return query;};query.range=async(a,b)=>{call.range=[a,b];return {data:table==='breeding_settings'&&a===0?[{species:'rabbit',gestation_max:365,weaning_max:52}]:[],error:null};};return query;}};
 await calendarRecords(db,'ring','2026-10-31','2026-12-01');
 const bred=calls.find(c=>c.table==='breeding_records');
 assert.deepEqual(bred.gte,['breeding_date','2025-10-31']);assert.deepEqual(bred.lt,['breeding_date','2026-12-01']);
 assert.match(calls.find(c=>c.table==='breeding_tracking').or[0],/birth_date.gte.2025-11-01/);
 assert.match(calls.find(c=>c.table==='animal_health_records').or[0],/expires_date.lt.2026-12-01/);
 assert.equal(showInWindow({start_date:'2001-01-01'},'2026-10-31','2026-12-01'),undefined);
 assert.ok(showInWindow({start_date:'2001-01-01',is_favorite:true,entry_close_at:'2026-11-01T12:00:00Z'},'2026-10-31','2026-12-01'));
});

test('phone query has a lower bound but no future limit on any event source',async()=>{
 const calls=[];
 const db={from(table){const call={table};calls.push(call);const query={};for(const name of ['select','eq','gte','lt','or','order'])query[name]=(...args)=>{call[name]=args;return query;};query.range=async()=>({data:[],error:null});return query;}};
 await calendarRecords(db,'ring','2026-09-01',null);
 const bred=calls.find(c=>c.table==='breeding_records');
 assert.deepEqual(bred.gte,['breeding_date','2026-06-21']);assert.equal(bred.lt,undefined);
 for(const table of ['breeding_tracking','animal_health_records']) {
  const filter=calls.find(c=>c.table===table).or[0];
  assert.match(filter,/\.gte\./);assert.doesNotMatch(filter,/\.lt\.|null/);
 }
 assert.ok(showInWindow({start_date:'2035-01-01'},'2026-09-01',null));
 assert.ok(showInWindow({start_date:'2001-01-01',is_favorite:true,entry_close_at:'2035-01-01T12:00:00Z'},'2026-09-01',null));
});

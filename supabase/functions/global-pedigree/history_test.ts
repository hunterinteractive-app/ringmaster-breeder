import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { litterList, litterDetail, weightHistory } from "./history.ts";
Deno.test('history includes distinct same-date breedings and retains original malformed dates',()=>{
 const row=(id:string)=>`<tr><td></td><td><a href="?page=rabbits&function=litter&lid=${id}&rid=1&rid2=2">Dam</a></td><td>Sire</td><td>02/05/1970</td><td>04/10/2926</td><td>4</td><td></td><td></td><td>0</td><td></td><td>0</td></tr>`;
 const records=litterList(`<h1 id="hybridDefaultHeading">Litter Data for My Herd</h1><table id="results_table"><tr><td colspan="11">Failed Litters</td></tr>${row('10')}${row('11')}</table>`);
 assertEquals(records.length,2); assertEquals(records[0].kindled_or_due,'04/10/2926');assertEquals(records[1].category,'Failed Litters');
 const detail=litterDetail('<table id="litterData_table"><tr><td>Breeder:</td><td>Private contact</td></tr><tr><td>Number Fostered:</td><td>2</td></tr><tr><td>Comments</td></tr><tr><td>Notes</td></tr></table><fieldset id="litDateBtnsBox"><legend>Litter Events</legend><input value="Palpated" title="03/20/2025"></fieldset><fieldset><legend>Weaned Kits</legend><a href="?page=rabbits&rid=3">Kit</a></fieldset>',records[0]);
 assertEquals(detail.fields,{ 'Number Fostered':'2',Comments:'Notes'});assertEquals(detail.offspring_source_ids,['3']);assertEquals(detail.events,[{event:'Palpated',date:'03/20/2025'}]);
});
Deno.test('weight history uses the original date and source ID, ignoring synthetic chart birth zero',()=>{
 const records=weightHistory('<table id="chart"><tr><td>Birth</td><td>0</td></tr></table><table id="weights-table"><tbody><tr><td>1</td><td><span data-date-sortable="2025-05-15">May 15</span></td><td>4 lbs 8 oz - (4.5 lbs)</td><td></td><td><a id="deleteWt_123">Delete</a></td></tr></tbody></table>','1');
 assertEquals(records,[{kind:'weight',source_id:'1:123',animal_source_id:'1',recorded_date:'2025-05-15',weight:4.5,raw_weight:'4 lbs 8 oz - (4.5 lbs)'}]);
 assertThrows(()=>weightHistory('<h1>Login</h1>','1'));
 assertThrows(()=>litterList('<h1>Login</h1>'));
});

import { historyBatch, State } from "./collector.ts";
Deno.test('history continuation follows linked offspring before collection can finish',async()=>{
 const state:State={user:'fixture',account:'fixture',cookies:{},expires:Date.now()+60000,owned:['1'],seen:['1','2'],queue:[],historyQueue:[{kind:'litter',source_id:'10',animal_source_id:'1',sire_source_id:'2',detail_path:'/index.php?page=rabbits&function=litter&lid=10&rid=1&rid2=2'}]};
 const result=await historyBatch(state,async()=>new Response('<table id="litterData_table"><tr><td>Date Bred:</td><td>05/15/2025</td></tr></table><fieldset><legend>Weaned Kits</legend><a href="?page=rabbits&rid=3">Kit</a></fieldset>'));
 assertEquals(result.length,1);assertEquals(state.historyQueue,[]);assertEquals(state.queue,['3']);
});

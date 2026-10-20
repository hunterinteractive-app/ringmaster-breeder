// Isolated in-memory PostgreSQL only. No live Supabase connection.
const { PGlite } = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const db = new PGlite();
await db.exec(`
  create role authenticated;
  create table public.animals(id text primary key, owner_id text, name text, variety text);
  insert into public.animals values('a','owner','Sample','Chocolate'),('b','other','Other','Blue');
  alter table public.animals enable row level security;
  grant select,update on public.animals to authenticated;
  create policy own_animal on public.animals to authenticated
    using(owner_id=current_setting('fixture.owner',true))
    with check(owner_id=current_setting('fixture.owner',true));
`);
await db.exec(readFileSync(new URL('../migrations/20261020105258_animal_genotype_record.sql', import.meta.url),'utf8'));
assert.deepEqual((await db.query('select genotype from public.animals order by id')).rows.map(r=>r.genotype),[{},{}]);
await db.exec("set role authenticated; set fixture.owner='owner';");
const raw='aa bb C- D? E- enen Sa- L- wewe';
const record={notation:raw,basis:'imported',source:'Rabbit Register'};
await db.query('update public.animals set genotype=$1 where id=$2',[record,'a']);
assert.deepEqual((await db.query('select genotype from public.animals where id=$1',['a'])).rows[0].genotype,record);
assert.deepEqual((await db.query('select name,variety from public.animals where id=$1',['a'])).rows[0],{name:'Sample',variety:'Chocolate'});
assert.equal((await db.query('update public.animals set genotype=$1 where id=$2 returning id',[record,'b'])).rows.length,0);
for(const invalid of [null,[], 'aa', {notation:'aa'}, {notation:'',basis:'inferred'},
  {notation:'aa',basis:'confirmed-by-app'}, {notation:'aa',basis:'inferred',source:42},
  {notation:'aa',basis:'inferred',unreviewed:true}, {notation:'a'.repeat(501),basis:'inferred'},
  {notation:'aa',basis:'inferred',source:'x'.repeat(301)}]) {
  await assert.rejects(db.query('update public.animals set genotype=$1 where id=$2',[invalid,'a']));
}
await db.query('update public.animals set genotype=$1 where id=$2',[{},'a']);
assert.deepEqual((await db.query('select genotype from public.animals')).rows,[{genotype:{}}]);
await db.exec('reset role;');
assert.deepEqual((await db.query("select genotype from public.animals where id='b'")).rows[0].genotype,{});
await db.close();
console.log('Genotype migration: defaults, round-trip, clearing, 10 invalid shapes and owner isolation passed.');

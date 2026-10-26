// Isolated database only. Set PGLITE_MODULE to an installed PGlite dist/index.js.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const { PGlite } = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const read = name => readFileSync(new URL('../migrations/' + name, import.meta.url), 'utf8');
const identity = read('20261010030120_catalog_identity_guardrails.sql');
const catalog = read('20261010024610_shared_breed_catalog.sql');
const migration = read('20261025183901_britannia_petite_catalog_alias.sql');
const db = new PGlite();
await db.exec(`
 create role anon; create role authenticated; create schema breeder_private;
 ${identity.slice(identity.indexOf('create or replace function'), identity.indexOf('-- Keep the source-linked'))}
 create table breeds(id uuid primary key default gen_random_uuid(), species text, name text,
  catalog_key text generated always as (public.catalog_key(name)) stored,
  show_id uuid, is_recognized boolean default false, unique(species,catalog_key));
 create table varieties(id uuid primary key default gen_random_uuid(), breed_id uuid references breeds on delete cascade,
  name text, catalog_key text generated always as (public.catalog_key(name)) stored,
  show_id uuid, is_recognized boolean default false, unique(breed_id,catalog_key));
 create table animals(id uuid primary key default gen_random_uuid(),species text,breed text,variety text);
 ${catalog.slice(catalog.indexOf('create or replace function breeder_private.catalog_animal()'))}
 insert into breeds(species,name,show_id,is_recognized) values
  ('rabbit','Britannia Petite',gen_random_uuid(),true),('rabbit','Britannia Petit',null,false),
  ('rabbit','Distinct Breed',null,false);
 insert into varieties(breed_id,name,show_id,is_recognized)
 select id,'Black',gen_random_uuid(),true from breeds where name='Britannia Petite';
 insert into varieties(breed_id,name,is_recognized)
 select id,'Custom Color',false from breeds where name='Britannia Petit';
`);
const before = (await db.query('select * from breeds order by id')).rows;
const originalColors = (await db.query('select * from varieties order by id')).rows;
await db.exec(migration);
assert.deepEqual((await db.query('select * from breeds order by id')).rows, before);
assert.deepEqual((await db.query('select * from varieties order by id')).rows, originalColors);
// Both fresh imports and edits resolve the source label through the real trigger.
await db.exec("insert into animals(species,breed,variety) values('rabbit','  BRITANNIA   PETIT ','Black')");
assert.deepEqual((await db.query('select breed,variety from animals')).rows, [{breed:'Britannia Petite',variety:'Black'}]);
await db.exec("update animals set breed='Britannia Petit',variety='Custom Color'");
assert.deepEqual((await db.query('select breed,variety from animals')).rows, [{breed:'Britannia Petite',variety:'Custom Color'}]);
assert.equal((await db.query("select count(*)::int n from breeds where name='Britannia Petite'")).rows[0].n, 1);
assert.deepEqual((await db.query('select * from breeds order by id')).rows, before);
assert.equal((await db.query('select count(*)::int n from varieties where id=any($1::uuid[])', [originalColors.map(v=>v.id)])).rows[0].n, originalColors.length);
await db.exec("insert into animals(species,breed) values('rabbit','Distinct Breed')");
assert.equal((await db.query("select count(*)::int n from animals where breed='Distinct Breed'")).rows[0].n, 1);
await db.exec(migration);
assert.deepEqual((await db.query('select * from breeds order by id')).rows, before);
assert.equal((await db.query("select prosecdef from pg_proc where oid='breeder_private.catalog_animal()'::regprocedure")).rows[0].prosecdef, true);
assert.equal((await db.query("select has_function_privilege('authenticated','breeder_private.catalog_animal()','EXECUTE') allowed")).rows[0].allowed, false);
await db.close();
console.log('Britannia alias checks passed: import/edit normalization, retained catalogs and colors, unrelated breed, repeat migration, unchanged function privileges.');

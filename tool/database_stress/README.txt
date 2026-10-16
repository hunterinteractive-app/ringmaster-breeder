Local database stress-test fixtures

These scripts deliberately target only the named disposable database container
ringmaster-breeder-scale-test-20261016 and http://127.0.0.1:56433. Do not edit them
to point at production. All credentials and identities in these files are synthetic.

Prerequisites: a FRESH schema-only clone of the current Breeder application in
Postgres 17, Supabase roles and Auth helpers, minimal storage metadata fixtures,
and PostgREST exposing public on port 56433 with a 1,000-row response cap.
The 2026-10-16 run used the locally cached Supabase Postgres and PostgREST images.
Schema export and container provisioning are not automated by these runners.

Apply support.sql to the disposable compatibility fixture, then seed.sql as its
administrator. run.py adds 100 archived animals and tests real authenticated HTTP
requests, concurrency, and interrupted writes. Run it once per fresh fixture;
its successful concurrency tests intentionally advance revisions and payments.
The original duplicate-save and concurrent-animal-edit regressions now use stable record IDs and revision predicates and should pass. The Dart write_safety_test.dart additionally exercises the actual production save services against this API.

python3 tool/database_stress/run.py
npx --yes deno run --allow-net=127.0.0.1:56433 --allow-write=deliverables/database-calendar-results.json tool/database_stress/calendar_test.ts

The TypeScript runner imports the actual production calendar query and event
helpers and independently checks expected events from the synthetic seed.
JSON evidence is written to deliverables/. Containers were removed after the run.

provision.py restores a fresh explicitly named container from the schema-only snapshot at /private/tmp/ringmaster-breeder-scale-schema.sql, applies the animal revision migration, and seeds the history fixture. It refuses a nonempty application schema.

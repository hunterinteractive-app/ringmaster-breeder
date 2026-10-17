RingMaster Breeder — isolated endurance and scaling regression tests

Safety and evidence
These tools accept only the named local rmb-next-stress stack at 127.0.0.1:56431.
All users, credentials, animals and histories are synthetic. No production records
are copied. No email is delivered to real recipients. Private subscription URLs
and bearer tokens are never logged or committed.

Pre-fix evidence from release c5ede03 remains in deliverables/*.json and the
original endurance-stress-report.txt. New fixed-code evidence is written to
  deliverables/scaling-fixes/
Do not combine those two runs or overwrite the original failure evidence.

Fixes under test
- Migration 20261017023049_calendar_query_scaling.sql resolves family rings once
  per statement; history/breeding policies hash accessible animal IDs instead of
  invoking a privileged access lookup on each candidate history row.
- calendar-feed/calendar.mjs measures UTF-8 code-point widths directly. No
  TextEncoder/byte-array allocation for each character; emitted bytes are unchanged.
- Pool size 10, acquisition timeout, API max_rows=1000 and Edge CPU limit 2000ms
  remain unchanged. No future date cutoff or total-record cap was introduced.
- Two experimental history indexes were removed after the policy change alone
  passed the workload. The final migration adds no indexes.

Environment
Supabase CLI 2.95.4; real Auth, PostgREST, Storage, Kong and Edge Runtime.
Postgres 17.6.1.127; PostgREST v14.10; Edge Runtime v1.73.13 (Deno 2.1.4).
Flutter 3.38.5/Dart 3.10.4 release JavaScript browser build; production CI uses
Flutter 3.41.4. Supabase JS 2.110.2; Python icalendar 6.3.2 for independent parsing.
These local synchronized bursts are not a production hosting capacity SLA.

Provisioning
Create a fresh temporary Supabase project with ID rmb-next-stress and ports:
API 56431, DB 56432, shadow 56430, mailpit 56435, edge inspector 56437.
Set API max_rows=1000, Auth sign_in_sign_ups=300, and seed.sql_paths=[].
Use edge_runtime.policy="oneshot" for functional/per-request CPU checks. The
pre-fix failure was independently reproduced in a fresh oneshot worker.
Set calendar-feed and show-calendar verify_jwt=false: handlers implement their
own private-token/verified-user authorization.

Start the isolated stack:
  supabase start --workdir /private/tmp/rmb-next-stress \
    -x realtime,studio,postgres-meta,logflare,vector,supavisor,imgproxy
Save local-only credentials without printing them:
  supabase status --workdir /private/tmp/rmb-next-stress --output json \
    > /private/tmp/rmb-next-stress/local-status.json

Restore the schema-only public/breeder_private export retained from the earlier
application test, then migration 20261016222731_animal_edit_revision, and the
synthetic tool/database_stress/seed.sql. Apply the scaling migration with psql
only in this disposable stack. Do not run the old compatibility support.sql:
it would replace real Auth helpers with simplified fixtures.

The base fixture's scale-%@example.invalid Auth users need complete instance_id,
aud/role, empty confirmation/recovery/change tokens, created_at/updated_at,
JSON metadata, password hashes and email-provider identities for real Auth login.
Use the synthetic password Synthetic-stress-only-2026! and extensions.crypt(...,
extensions.gen_salt('bf')). No real credentials are used. Notify PostgREST to
reload its schema after restoration.

Run seed_families.py ONCE against that fresh base fixture. It adds 49 independent
families with 1000 animals and 10000 history records each. Together with the main
1000-animal/500000-history fixture this yields 50 breeders, 50000 animals and
990000 initial history records. Later tests add small audited synthetic writes.
It creates /private/tmp/rmb-next-stress/multi-identities.json with deterministic
IDs and expected per-animal counts; JWTs must be generated anew after restarts.

Copy calendar-feed, show-calendar and _shared from supabase/functions into the
temporary project and run:
  supabase functions serve --workdir /private/tmp/rmb-next-stress
Show's external connection is not configured or contacted by this fixture.

Retest commands (run from repository root)
1. Python scripts need local Docker and loopback network access. Create a temp
   venv with pinned icalendar==6.3.2 for the calendar scripts.
   calendar_lifecycle.py checks actual HTTP management/feed behavior, date bounds,
   stable UIDs, update/delete, rotation/revocation, inactive users and revoked members.
   It writes test-subscription.json in the temporary fixture directory for capacity.py.

2. Build the instrumented browser component harness:
   flutter build web --release --pwa-strategy=none --no-pub \
     --target tool/endurance_stress/main.dart --dart-define=APP_VERSION=local-stress-test
   Run server.py and open http://127.0.0.1:56440 in the browser tool. Click
   Start 30-minute test. The harness imports production widgets/services. It
   exercises herd pagination, card/list scrolling/search, month navigation,
   error/retry UI, history/graphs, bulk saves, lost acknowledgements after actual
   inserts, racing retries and stale edits. It uses HTTP 503 and 350ms added delay;
   it does not emulate physical Wi-Fi/packet loss. The calendar error check scrolls below the month grid and waits for its UI state up to 10s and records the
   maximum observed wait. The former fixed 500ms assumption failed once during
   calibration. A second run established that the lazy error card must be scrolled
   into view, rather than merely waiting longer. Both incomplete runs are preserved. The 80s save
   confirmation check is unchanged.

3. Use Deno with loopback-only network permissions:
   deno run --allow-net=127.0.0.1:56431 --allow-read=/private/tmp/rmb-next-stress \
     --allow-write=deliverables/scaling-fixes tool/endurance_stress/multiuser.ts
   Each 1/10/25/50-breeder stage has three synchronized rounds of full herd reads,
   history/calendar queries, foreign-read denial checks and verified weight saves.
   It imports the actual shared calendar query helper. Each round waits for all
   queries to settle; failures remain in the output. --baseline-only runs stage 1.

4. Run isolation.py: all 50 families, no foreign rows, and mixed-family bulk writes
   rejected atomically (both own and foreign rows remain absent).
   Run policy_equivalence.py to compare old/new permissions across every synthetic
   animal and identity, including unauthenticated access.
   Run access_policies.py: accepted/pending/revoked membership, inactive owners,
   demo herds, reassignment rejection, valid member health CRUD, both-parent
   breeding access and multiple-family revocation, private helper attributes/RLS.
   Tests restore modified fixture state and remove temporary cross-family rows.

5. Run calendar_capacity.py with the icalendar venv. It adds 14000 distant-future
   follow-ups whose source dates are 1999, calls the fixed real function three
   times under the default 2s CPU limit, checks all 20434 events/8.20MB with an
   independent parser, and removes the extra rows in finally. It never edits
   the function copy or repository. Original failed-worker evidence is preserved.

6. Run query_plans.py. It temporarily enables EXPLAIN only on the disposable API,
   captures actual app/service-role queries, then restores the setting in finally.
   Run node tool/endurance_stress/render_profile.mjs and redirect its JSON to
   deliverables/scaling-fixes/calendar-render-profile.json. It compares the fixed
   renderer with an allocation-heavy pre-fix fold loaded only in memory, asserts
   byte-identical output, and records three CPU/wall samples for 1000/6500/20000 events.

7. Run flutter test, flutter analyze, and
   node --test supabase/functions/calendar-feed/tests/*.test.mjs
   Run local supabase db lint and supabase db advisors. Their reports include
   existing warnings in unrelated pedigree functions/draft policies; retain those
   separately and do not report them as new defects or as a clean whole-schema audit.

8. After the 30-minute run completes, run audit.py to audit duplicate logical retry weights,
   temporary future-fixture leftovers and animal revisions; save
   endurance-data-audit.json and regression-verification.json. Keep the existing
   user-provided physical iPhone result in the temporary phone-check.json.
   Run report.py to generate the final before/after summary. It refuses incomplete
   browser runs and exits nonzero if any required check fails. Compress the raw
   browser JSONL after reporting and keep the compressed evidence.

Limits
The harness covers real components/services, not every whole-app navigation path.
Heap measurements cover JavaScript only, excluding GPU/Wasm. A physical iPhone
subscription already worked for the user; the user lacked suitable dates to
compare recent/distant-future boundaries. Automated checks cover those dates.
No physical Android or provider-controlled alert/refresh guarantee is established.
Existing nested SQL permission-denial DO blocks caused a separate local backend
segfault in prior testing; normal actual HTTP denials pass. Do not rerun those
crashing diagnostics in a stack while the soak is active.

Cleanup
Save a final browser screenshot and close only the temporary test tab. Stop the
loopback host and this explicitly named Supabase stack with --no-backup. Leave
unrelated local projects/stacks alone. Restore a normal lib/main.dart web build
so ignored build/web does not retain the stress harness. Never publish the
synthetic test build, users, credentials or workload.

# Breeder Phase 1 offline PWA

Implementation and acceptance record, October 17, 2026. Phase 1 extends the first
animal/weight pilot to the ordinary workflows throughout Breeder. See the release
record below for deployment and device qualification; passing desktop browser
checks is not a claim of certification on older phones.

## Initial deployment and validation record

Deployed with owner authorization on October 17, 2026 to
https://breeder.ringmasterone.com. Cloudflare production deployment
`8cc88432-70e1-4093-83b4-5abde335aab6` publishes the tested
`build/web-offline-phase1` artifact, worker revision `359402b727ef84da33a1`.
Its immutable deployment URL is https://8cc88432.ringmaster-breeder.pages.dev.
Subsequent main-branch deployments build this source in CI and use the commit
hash as the visible application version; their worker revisions will differ.
The existing port-8791 preview remains untouched; its device storage is separate
from production and pending work must be synced/exported on that original origin.

All four migrations are live in Breeder project `aqfsrolvaewcpkdkttiz`:
`20261017130853` workspace sync, `20261017130903` external jobs,
`20261017130912` import receipts, and `20261017131108` empty-herd management.
Edge Functions are active: `offline-jobs` v1, `import-ringmaster-records` v4,
and `delete-account` v2. Existing authentication flags were preserved; the new
job handler verifies the caller with Auth itself. All three endpoints reject
unauthenticated calls with HTTP 401. No production records were created or
edited by the deployment checks.

Production application JavaScript, worker, fonts, manifest and CanvasKit match
the tested artifact byte-for-byte and retain the no-cache response headers.
Cloudflare adds its existing browser security script to the HTML. The pre-Phase-1
production deployment is `6acff0de-ea74-47cc-87eb-8231bc6f6b7f`; database migrations
are additive and must remain when rolling the frontend back. Original RPC and
function definitions were backed up locally before release.

The first live smoke test caught a Cloudflare-specific index redirect: returning
a cached redirected response to an offline navigation failed in Chrome. The
worker now normalizes that navigation response. The fixture server reproduces
Pages' HTTP 308 index redirect, and both complete browser suites and all 40
repository tests passed again. The corrected live deployment installed all 49
assets and reloaded its rendered UI with Chrome's network disabled, without
runtime errors. This production smoke check used a fresh unsigned-in browser;
authenticated offline workflows were validated against isolated fixtures.

Security verification confirms account-scoped receipt/job RLS, private owner-only
result files, no anonymous table access, security-invoker public entry points,
and service-only import receipt execution. The advisor reports the three new
tables as discoverable in authenticated GraphQL introspection because their
SELECT grants support the authenticated sync implementation. This is intentional:
job/receipt rows remain restricted to their actor; the private version table
contains only shared table-version counters. See the
[advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0027_pg_graphql_authenticated_table_exposed).
Other advisor findings predate this release.

Validation: 179 Flutter tests, 40 shared repository tests, 10 Deno tests with nine
handler lifecycle steps, isolated Postgres workflow/RLS/storage tests, and complete
Chrome/WebKit acceptance runs. Chromium additionally delivered a queued record
through an actual worker Sync event with the app page closed. This checks the
worker implementation; browser scheduling remains opportunistic. A desktop
10,000-animal/100,000-weight projection/detail benchmark took approximately 64 ms
after indexed joins, versus 6.4 seconds before the query optimization. It is not a
phone performance guarantee.

## What works offline

Sign in and finish the first complete download while connected. The Sync button
in the site-wide header reports record download freshness, files, queued work,
conflicts, server jobs, storage statistics when available, and recovery actions.
Downloading application files alone does not prepare private herd records.

| Workflow | Phase 1 behavior |
| --- | --- |
| Herd dashboard and family selection | All currently authorized herds and membership downloaded |
| Create or rename herd | Provisional records and durable queued writes; server checks licenses/access |
| Delete herd | Owner confirmation; only empty herds; protect animals, history, sales and drafts |
| Animal lists, search, detail and parents | Download all authorized records; unvisited records open locally |
| Create animals, quick parents and initial weights | Stable IDs and atomic replay of related records |
| Edit animals | Local projection immediately; independent fields merge; competing/related fields require review |
| Weight history, new and bulk weights, latest correction | Local history and durable writes; server rechecks the latest-record rule |
| Health records, edits, deletion and bulk saves | Local history and files; bulk additions have independent per-animal outcomes |
| Breeding settings, records, tracking, litters and offspring | Local projections and relationships; original server validation on replay |
| Pedigree drafts, tree, PDF and ordinary exports | Local graph, source records and packaged fonts; graph writes use stable IDs |
| Listings, reservations, payments and refunds | Local sale/status/history projections; authoritative server triggers on replay |
| Herd calendar | Compute any month from downloaded breeding/health source records |
| Show history, connection and report metadata | Downloaded snapshots; outside refresh/retrieval queued when unavailable |
| Pedigree buyer email | Approved recipient/PDF saved immutably; server rechecks pedigree and sender before sending |
| Show/Club lookup and import | Queue retrieval; review returned records; committed imports have transaction receipts |
| Global Pedigree collection | Existing downloaded draft available; missing collection queues a sign-in reminder; never retain its password |
| Global Pedigree import | Review while connected, or reuse an exact previously downloaded review; queue the approved import |
| Profile contact/address edits | Local projection, queued write, server ownership checks |
| Photos and attachments | Default photo thumbnails; optional original photos/documents with size estimate; pending uploads available locally |
| First login, new legal acceptance, family permissions, account deletion, billing and sensitive administration | Require a connection and current authorization |
| Device calendar subscriptions | Create/manage online; external calendar app controls its own refresh |

Recording money received is ordinary recordkeeping. Card checkout is online and
card credentials are never queued. Browsers cannot retrieve information that was
never downloaded while there is no network; queued retrieval produces a result
or a clear request for further input after reconnection.

## Saving, conflicts and recovery

Private records, immutable operation IDs, dependencies and file bytes are stored
in account-scoped IndexedDB transactions. A failed disk/quota write fails the save
and leaves the form available. There is no in-memory substitute that reports a
successful offline save. Binary data is stored separately from the small outbox.

Accounts may edit for seven days from the last verified server snapshot. Reading
local records or restoring a recovery file never extends that lease. Expiry keeps
viewing and recovery available and requires reconnection before another edit.
An expired hourly login token does not block local record access; the original
Auth client refreshes the actual session before delivery. The server still checks
its JWT and permissions for every replay.

New independent records coexist. Changed fields are compared with their original
values under server row locks. Changes to species, breed, variety, color, sex,
birth, status or parent relationships are reviewed together. Conflicts keep the
user's version visible and show the server values in Sync. Users choose the
server version or explicitly keep their changes. Both choices update the local
base atomically; a retried decision retains stable created-record IDs. Deleted or
inaccessible records retain their drafts for recovery. Rejections retain their
specific reason. Neither conflicts nor rejected records stop unrelated animals.
Dependent actions wait until their prerequisite is resolved.

RPCs and ordinary record writes run through an authenticated receipt transaction
that invokes the existing validation, RLS, column grants, quotas and business
triggers. Receipts retain a payload hash and result. A lost acknowledgement can
be replayed without duplicating animals, offspring, sale payments or imports.
Raw file uploads use immutable paths and confirm matching bytes after uncertain
responses. Page/worker leases and compare-and-swap checks coordinate uploads,
conflict choices, downloads and recovery export across tabs.

Logout requires delivery or a complete recovery export of pending local work.
The user confirms possession of the downloaded file. The exact exported queue is
then released atomically; work added during export prevents logout. Recovery
includes each pending file and preserves request IDs. It excludes credentials,
leases and unrelated downloaded media. Requests previously accepted by the server
may still finish after logout; restoration reconciles their original identities.

## Reconnection and outside services

Foreground sync runs on open, resume, reconnect and Sync now. Known outages use
bounded background reachability checks approximately every 15 seconds, with
bounded retry backoff for pending work. An active connected app checks record
versions approximately every 30 seconds. Responses, including their bodies, have
deadlines so stalled service cannot hold a sync indefinitely.

The shared worker runs genuine Background Sync when the browser exposes it.
Registration and actual execution are different: the browser chooses when it may
run, and a valid cached access token is required. iPhone/iPad web apps cannot
promise to upload immediately while suspended or closed. Reopen Breeder after
reconnecting for reliable completion. The implementation does not store refresh
tokens in the background worker's configuration or in recovery files.

After a verified server accepts an outside-service job, it can continue without
the phone. The durable job ledger distinguishes queued, processing, sign-in
needed, review ready, completed, failed and cancelled. Requests that have not
started can be cancelled. Failed jobs and invocations interrupted for five
minutes can be retried with the same identity. Completion updates are fenced to
the processing attempt. Bulk source data and PDFs are removed from completed or
cancelled job payloads while their immutable hashes/results remain. Failed jobs
retain their approved inputs. Existing provider safeguards prevent unsafe email
retries after the provider's idempotency window.

Retrieved report files are copied into the private `offline_results` bucket and
then downloaded to the device; an expiring signed URL alone is not offline data.
Global Pedigree credentials are never persisted: its queued intent requires the
user to sign in on reconnection. Cross-app imports retain their first transaction
result even if the source changes before a lost-response retry.

## Browser storage and updates

Target iOS 15.6+ Safari/Home Screen and Android 10+ with updated Chrome. Detect
storage estimates, persistence and background capabilities rather than assuming
they exist. Installing on the Home Screen is recommended for barn use; it does
not replace the initial record/file download. Clearing browser data, uninstalling
the web app, device failure or browser eviction can remove unsynced data. A PWA
cannot guarantee native-style permanent storage on every phone, including iOS 17.
Use the visible readiness indicator and recovery export for important unsynced work.

Private records/files are never placed in the public application cache. Public
assets include the UI/PDF fonts and CanvasKit, approximately 38.4 MB in the tested
release. Thumbnails are generated on-device from downloaded originals; no paid
image-transformation service is required. Optional file downloads add storage and
bandwidth to the existing hosting/Supabase allowance. No new paid service is
required, but usage is subject to those existing service limits.

The service worker versions the entire application bundle. An update waits while
old tabs are open, preserving unsaved forms. Sync indicates a waiting update;
save forms, close all Breeder tabs and reopen to activate it. Do not clear storage
to force an update when pending work exists. Keep a compatible offline build
available until queues created by it have been reconciled.

## Architecture and release

- `web/offline_query.js`: the query/relationship contracts used by current screens.
- `web/offline_actions.js`: deterministic provisional results and write validation.
- `web/offline_workspace.js`: shared page/worker repository, downloads, queue,
  file persistence, receipts, leases and outside-job bridge.
- `lib/offline/`: Flutter bridge, original pilot compatibility, seven-day lease,
  Auth/data routing, sync/recovery and bounded connection state.
- `supabase/migrations/20261017*offline*.sql`: four additive protocol, job,
  import-receipt and empty-herd migrations. RPC adaptation preserves existing
  validation while supplying deterministic IDs inside receipt transactions.
- `supabase/functions/offline-jobs/`: authenticated job ledger and runner.
  Updated `import-ringmaster-records` supports receipts; `delete-account`
  includes private result files in cleanup.

Apply the four migrations in filename order to Breeder, then deploy those three
Edge Functions, preserving their verified authentication behavior. The job runner
uses the existing Supabase environment variables and caller JWTs. It needs no
new paid scheduler. Deploy a matching packaged frontend. CI builds with both flags,
checks Flutter/shared repository/job handlers, and packages the worker before its
existing Cloudflare deployment step.

```sh
flutter pub get
flutter analyze
flutter test
node tool/offline_workspace_test.cjs
npx --yes deno@2 check supabase/functions/offline-jobs/index.ts supabase/functions/import-ringmaster-records/index.ts
npx --yes deno@2 test --allow-env supabase/functions/offline-jobs/core_test.ts supabase/functions/offline-jobs/handler_test.ts
flutter build web --release --pwa-strategy=none --dart-define=OFFLINE_PILOT=true --dart-define=OFFLINE_FULL=true --output build/web-offline-phase1
python3 tool/prepare_offline_pilot.py build/web-offline-phase1
python3 -m http.server 8792 --bind 127.0.0.1 --directory build/web-offline-phase1
```

`OFFLINE_PILOT` is the retained technical flag name for compatibility with the
first preview. `OFFLINE_FULL` enables automatic whole-workspace preparation.
The packager refuses an unflagged bundle. Use HTTPS on real phones; simulator
loopback is suitable for local testing. Leave the old preview on port 8791 until
its forms are saved. A new port has separate browser storage and needs a fresh
online sign-in/download.

## Automated validation and physical acceptance

The final local check record includes Flutter tests, shared repository tests,
real Chrome and WebKit worker/IndexedDB runs, job-handler HTTP fixture tests, and
rollback-only tests against an isolated Postgres copy of the current schema.
Browser fixtures never contact live Auth, data, email or import services.

The browser runs cover first sign-in, failed account-check recovery, complete
preparation, unvisited records, offline editing, restart with an expired token,
Sync status, ordinary workflow request contracts, binary persistence, outside
request queueing, reconnection, duplicate prevention, and delivery of older pilot
weights through the real network path rather than their own local projections.
WebKit's fixture rejects network requests with 503 responses; Chromium additionally
uses the browser's actual offline setting. These are browser-engine checks, not
physical iPhone/Android certification.

Prepare the SQL suite with `python3 tool/prepare_offline_database_tests.py /tmp/offline-test.sql`
and execute it only in a disposable local copy with migrations and existing storage
policies installed. It verifies actual server workflows/triggers, deterministic
IDs, retries, independent merges/conflicts, rollback on invalid batches, protected
columns, cross-account RLS/file/job isolation, receipt immutability and safe herd
deletion. The development test DB is `breeder_offline_phase1_final_test` in the
existing local `supabase_db_ringmaster-show-full-e2e-convention` container; it has
no live user records. The Show application's database is untouched.

Before calling a phone/version qualified, test on that hardware:

1. Install on Home Screen, sign in, download records/thumbnails; verify counts and
   a new record that has never been opened. Optionally download original files.
2. Disable Wi-Fi and cellular. Open every ordinary workflow; create/edit weights,
   health, breeding, offspring, drafts, sales and files. Confirm the queue grows.
3. Close the app completely, reopen offline and verify pending work and file bytes.
   Include a session that has been offline beyond the normal login-token lifetime.
4. Reconnect. Open the app, wait for delivery and inspect the authoritative records
   from a second device. Repeat after interruption halfway through a sync.
5. Make competing changes on two devices, check independent merging and explicit
   conflict choices; revoke family access and retain rejected drafts for recovery.
6. Exercise low storage, quota failures, lease expiry, export/restore, logout,
   app updates with pending work, and removal of downloaded data. Never use real
   payments or unintended recipient emails as test fixtures.

Start with the owner's current iPhone and an Android device/emulator. Older iOS
15.6/17 and Android 10 hardware remain a separate qualification step. Background
Sync opportunism and iOS storage eviction require real-device observation.

## Responsive screen acceptance

The shared application shell applies compact spacing, headings, cards and inputs
below 600 logical pixels wide or 500 pixels of usable height. Native keyboard
insets and browser viewport resizing both trigger compact layouts. System text
scaling remains enabled, and resize does not replace the navigation/form tree.
Add/Edit Animal forms stop growing at 720 pixels on larger screens.

Animal Details puts its primary edit action beside the essential information on
phones, with a smaller photo, a two-column field layout, and expandable registration
and parent sections. Enlarged text falls back to one column. Sales totals are
expandable on phones, calendar category filters use one picker, and breeding/report
summaries use less space. Weight History uses one lazy scroll view; its chart is
expandable on phones and scrolls with the records when open. Account, import,
pedigree entry, legal and other forms share the compact spacing rules.

`test/adaptive_screens_test.dart` covers detail actions, expandable show notes,
weight history scrolling and permissions, sales search preservation on resize,
and calendar filtering at phone, landscape and desktop sizes, including 150% text.
The existing responsive form cases exercise native keyboard insets and unsaved
field/focus preservation. With a packaged offline build and Playwright available,
run `FULL_WORKSPACE=true FRESH_LOGIN=true RESPONSIVE_SITE=true node tool/offline_browser_test.cjs build/web`
for offline page navigation and screenshots. Use `RESPONSIVE_FORM=true` instead
for browser keyboard-sized viewports, lower fields, Save access and draft retention.
Repeat with `BROWSER=webkit`; browser engines complement simulator/device testing.

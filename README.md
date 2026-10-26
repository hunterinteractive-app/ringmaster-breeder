# RingMaster Breeder

Flutter application for rabbit and cavy herd records. Local development uses the existing Breeder Supabase project; this is separate from Show and Club.

## Development

Run `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter run -d chrome`.

Authentication uses Supabase email codes. Both Confirm Sign Up and Magic Link / OTP templates must contain `{{ .Token }}`; the retained template is `supabase/auth-email-template.html`. Custom SMTP must be configured for email delivery beyond Supabase's built-in restrictions. Never place SMTP passwords or service-role keys in Flutter code or Git.

`SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` can override the existing public configuration through `--dart-define`. Public keys are expected in browser clients; authorization is enforced by database policies.

## Family access

Each login retains its own identity. Family Access creates a seven-day invitation for a verified email. The recipient signs in with that email and accepts it in Family Access. Invitations currently appear in the app; the owner must tell the recipient to sign in. Automatic invitation email delivery is not implemented.

Accepted members can select the owner's family and access all its Rings, animals, health records, attachments, weights, and pedigrees. Members can leave; owners can revoke immediately. Members cannot change licenses, ownership, identities, or invite others into a family they do not own. Weights remain append-only; sold/deceased animal edits and new weights are locked on the server.

Verified sign-in links the legacy Breeder account by its unique normalized email, preserving its original user ID, Rings, animals, and license. No records are merged or deleted.

## Database

Testing enrollment currently grants each newly created, verified Breeder identity an active `HOBBY` license for one herd. The insert trigger does not change existing licenses or reissue cancelled access. Administrators can stop future grants with `update breeder_private.testing_access set enabled=false where singleton;`. Existing testing licenses have no automatic expiration and remain active until explicitly changed; disabling enrollment alone does not revoke them. The setting is inaccessible to app users. `supabase/tests/testing_herd_access.sql` verifies onboarding, the one-herd quota, verification requirements, cancellation preservation, and the enrollment switch inside a rolled-back transaction.

The modernization migration was applied to the existing project after validation against a local copy of its schema. `docs/database-baseline.sql` is a reference snapshot before modernization, not an installation script. `supabase/tests/family_access.sql` tests synthetic accounts inside a transaction and rolls back. It verifies verified-email linking, pending/accepted invitations, family editing, unrelated-account isolation, quotas, protected licenses, private attachments, pedigree access, and revocation.

## Backups and recovery

The nightly B2 service-backup workflow and administrator-assisted individual
owner recovery are documented in [service backups](docs/service-backups.md).
Backups include database records and original Storage files. Verified nightly
copies are retained for 90 days; first-of-month copies are retained for 365 days.
Breeder's GitHub secrets and first successful B2 run are configured. Individual recovery
restores snapshot records while preserving newer records and current access.

## Deployment

GitHub Actions checks analysis and tests, builds Flutter web, and uploads to Cloudflare Pages on pushes to `main`. Pull requests run checks without publishing. Configure `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` as repository secrets The `ringmaster-breeder` Pages project and `breeder.ringmasterone.com` domain already exist. After the Actions credentials are configured, disable the existing direct GitHub builds in Pages so Actions controls deployment. Local Flutter is 3.38.5; CI follows Show and Club's pinned Flutter 3.41.4.

Every served asset has browser/CDN `no-store` headers. Flutter's service worker is disabled; the bootstrap unregisters old root-scope workers and removes Flutter caches. Refresh fetches the currently deployed version after deployment completes. The footer displays the configured application release version (0.27.1 for this release). Do not set an overriding Cloudflare cache rule that forces caching for this host.

## Branding and remaining setup

`lib/theme/app_theme.dart` centralizes the palette. The approved palette uses maroon `#42101A`, core navy `#1E2849`, and off-white accent `#C7CBCC`. Shared header, content width, cards, and footer follow the other RingMaster applications.

Production SMTP, GitHub repository secrets, switching Pages from direct GitHub builds to Actions, and real two-account sign-in are still required before production launch. The schema baseline does not include backup data; retain the original local project backup.

## Validation and limits

Flutter analysis, five application tests, and the release web build passed locally. Family permission tests passed against the isolated baseline and live database with all synthetic changes rolled back. Existing record counts were preserved. Supabase security checks no longer report the original disabled-RLS errors; expected advisory items remain for the private invitation table without direct-client policies and authenticated GraphQL visibility, which is governed by RLS. Performance advisories include a license-tier foreign-key index and newly added indexes that have not yet accumulated usage.

Animal, health, weight, and pedigree workflows have been updated, but a complete signed-in browser walkthrough, printing and attachment checks with real accounts, and production refresh checks remain before launch. Automatic invitation emails and automatic health-record retention deletion are not implemented.

## Cross-app imports

Verified first-login matching now includes Breeder in Show and Club's server lookup. Club presents Show and Breeder candidates; Show retains its existing local-claim and Club priority, then checks Breeder when no Club match exists. After accepting the Terms and Privacy Policy, new Breeder users review Show/Club profile matches before herd setup, including in builds with offline mode enabled. They can import selected profiles or explicitly continue without importing; no matches also offers a continuation. Connection failures offer retry and do not silently bypass the step. Onboarding lookup/import requests require server confirmation rather than queuing an import job. Existing accounts with imported profiles or a non-demo herd bypass this first-use step, including from downloaded data. Imports remain available in Account Settings.

Select exhibitor profiles from one source per import. Show can additionally supply animals and individual entries/results; Club has no owned animal/entry tables and supplies profiles only. Animals require an existing personally owned Ring. Profiles and history can be imported before a Ring exists; a later animal import links retained history. Family members can read imported profiles and history, while personal imports require the signed-in owner's identity. Sources are copied without changing original records.

Imports retain provenance and source IDs; repeated imports do not create duplicate animals or history. Existing Breeder animal fields are preserved. Multiple matches or conflicting birth dates/varieties require review before import. Show-history rows are retained snapshots, not payment transfers or automatic synchronization. Server credentials are configured only in Edge Function secrets and must never be added to Flutter or committed files.

Results-only import is the default. Animal creation requires an explicit opt-in. Results can link an existing personally owned animal only when tattoo/tag, species, breed, sex, and variety identify exactly one record. Unmatched or ambiguous results remain in show history without creating or modifying animals; repeated imports retain the same source entry.

Policy changes: increment the affected version in `lib/config/legal_config.dart` and update its effective date when changing the Terms or Privacy Policy. The app checks each signed-in user's acceptance before mounting application routes. Both acknowledgments must be saved successfully before proceeding; each family member agrees separately. The database retains each accepted version and its server timestamp. This is an application access gate, matching Show and Club; it is not a substitute for database authorization.

## Large herds and calendar history

Animal lists, weight history, health history, and breeding history fetch ordered pages until all available records have loaded, rather than stopping at the API row limit. The in-app calendar fetches the viewed month plus its preceding and following months, and replaces that window on navigation, Today, or Refresh. Bounded queries include older source records when their follow-up or calculated breeding events can land in that window.

Device subscriptions export dates from the first day of the previous month onward, using the subscription timezone, with no future cutoff. Older historical dates are excluded; the start advances on each subscription refresh. A historical source record can still contribute an upcoming follow-up. Existing device caches update on the calendar app's refresh schedule.

## Litter grow out

Breedings & litters → Update tracking → After weaning offers Individual records
or Grow out. Herd → Breeding → Grow-out dashboard opens a dedicated overview
with active group and animal counts, latest group weights, and cumulative feed.
Filter by species or search parents/cage; totals follow the groups shown. Each
group contributes its latest valid reading since weaning. Earlier cumulative feed
readings are not added together, and missing readings remain unknown.

Grow-out litters also stay grouped in Active and the Grow out filter,
using their existing litter weights and feed records. Create individual records
lets you select youngsters later; the remainder stay grouped. The litter completes
when every youngster has an individual record, or you mark its tracking completed.
Rabbit and cavy counts, parentage, birth dates and offspring offline sync are
retained. Measurement saves use the existing server-confirmed workflow; downloaded
readings are available offline. Assigning individual records does not recalculate
earlier group weights or feed readings.

Apply the `litter_grow_out` and `litter_grow_out_rpc_access` migrations before
releasing this client. Existing litters default to Individual records. Validate with
`flutter test test/litter_grow_out_test.dart test/grow_out_dashboard_test.dart`, `node tool/offline_workspace_test.cjs`
and `supabase/tests/litter_grow_out.sql` against a disposable local database.

## Record save safety

Phase 1 offline behavior, build/deployment instructions, recovery safeguards and
phone qualification are documented in [docs/offline-pwa-plan.md](docs/offline-pwa-plan.md).
The packaged PWA uses `OFFLINE_PILOT=true` and `OFFLINE_FULL=true`; CI includes both.
Apply the matching backend migrations/functions before enabling complete workspace
preparation. A complete download is required before offline use.

Weight-entry dialogs and bulk weight/health saves retain their record IDs and payload while a save is uncertain. Retrying confirms matching saved records before inserting any missing records. A retry cannot overwrite an existing record with different data. Animal edits compare the revision originally loaded by the form; stale edits keep the draft visible and require an explicit reload. Database-triggered animal updates also advance the revision. Apply the animal revision migration before publishing the corresponding app version.

## Rabbit Register XML import

Account Settings → Import & export → Import from Rabbit Register previews Evans Rabbit Register's Other XML exports. Contacts, animal management, sales, litters, feed/weight readings, wool production and show results connect to their normal tracking screens. Source records remain preserved, and new imports also archive the original XML. Review unknown sex, missing parents, cycles and existing-animal matches before saving. Existing imports can link their retained history from Rabbit Register history. Apply the integration migration before releasing the client. See `docs/rabbit-register-import.md` for behavior, setup, limits and verification.

## Kintraks CSV import

Account → Import & export → Import from Kintraks previews All records CSV exports. It preserves source IDs, pedigrees, pounds-and-ounces weight snapshots, and all custom fields. Current herd membership requires explicit selection; ancestors default to archived pedigree records. Apply the Kintraks migration before releasing the client. See [Kintraks import](docs/kintraks-import.md) for supported fields, review behavior, setup, and verification.

## License plans and usage

Annual catalogue: Hobby $49 / 50 active animals / 1 herd; Professional $99 / 250 / 1 herd; Top $179 / 1,000 total / 5 herds. Prices are USD configuration, not payment collection. My Herds displays account-wide usage and warnings at 75%, 85%, 95%, and 100%. See [license entitlements](docs/license-entitlements.md) for grace, enforcement, feature gates, offline behavior, recovery and verification.

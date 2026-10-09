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

The modernization migration was applied to the existing project after validation against a local copy of its schema. `docs/database-baseline.sql` is a reference snapshot before modernization, not an installation script. `supabase/tests/family_access.sql` tests synthetic accounts inside a transaction and rolls back. It verifies verified-email linking, pending/accepted invitations, family editing, unrelated-account isolation, quotas, protected licenses, private attachments, pedigree access, and revocation.

## Deployment

GitHub Actions checks analysis and tests, builds Flutter web, and uploads to Cloudflare Pages on pushes to `main`. Pull requests run checks without publishing. Configure `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` as repository secrets The `ringmaster-breeder` Pages project and `breeder.ringmasterone.com` domain already exist. After the Actions credentials are configured, disable the existing direct GitHub builds in Pages so Actions controls deployment. Local Flutter is 3.38.5; CI follows Show and Club's pinned Flutter 3.41.4.

Every served asset has browser/CDN `no-store` headers. Flutter's service worker is disabled; the bootstrap unregisters old root-scope workers and removes Flutter caches. Refresh fetches the currently deployed version after deployment completes. The footer displays the deployment commit. Do not set an overriding Cloudflare cache rule that forces caching for this host.

## Branding and remaining setup

`lib/theme/app_theme.dart` centralizes the palette. The approved palette uses maroon `#42101A`, core navy `#1E2849`, and off-white accent `#C7CBCC`. Shared header, content width, cards, and footer follow the other RingMaster applications.

Production SMTP, GitHub repository secrets, switching Pages from direct GitHub builds to Actions, and real two-account sign-in are still required before production launch. The schema baseline does not include backup data; retain the original local project backup.

## Validation and limits

Flutter analysis, five application tests, and the release web build passed locally. Family permission tests passed against the isolated baseline and live database with all synthetic changes rolled back. Existing record counts were preserved. Supabase security checks no longer report the original disabled-RLS errors; expected advisory items remain for the private invitation table without direct-client policies and authenticated GraphQL visibility, which is governed by RLS. Performance advisories include a license-tier foreign-key index and newly added indexes that have not yet accumulated usage.

Animal, health, weight, and pedigree workflows have been updated, but a complete signed-in browser walkthrough, printing and attachment checks with real accounts, and production refresh checks remain before launch. Automatic invitation emails and automatic health-record retention deletion are not implemented.

## Cross-app imports

Verified first-login matching now includes Breeder in Show and Club's server lookup. Club presents Show and Breeder candidates; Show retains its existing local-claim and Club priority, then checks Breeder when no Club match exists. Breeder checks Show and Club and offers a review screen on first login when matching profiles exist. Imports are also available from the dashboard.

Select exhibitor profiles from one source per import. Show can additionally supply animals and individual entries/results; Club has no owned animal/entry tables and supplies profiles only. Animals require an existing personally owned Ring. Profiles and history can be imported before a Ring exists; a later animal import links retained history. Family members can read imported profiles and history, while personal imports require the signed-in owner's identity. Sources are copied without changing original records.

Imports retain provenance and source IDs; repeated imports do not create duplicate animals or history. Existing Breeder animal fields are preserved. Multiple matches or conflicting birth dates/varieties require review before import. Show-history rows are retained snapshots, not payment transfers or automatic synchronization. Server credentials are configured only in Edge Function secrets and must never be added to Flutter or committed files.

Results-only import is the default. Animal creation requires an explicit opt-in. Results can link an existing personally owned animal only when tattoo/tag, species, breed, sex, and variety identify exactly one record. Unmatched or ambiguous results remain in show history without creating or modifying animals; repeated imports retain the same source entry.

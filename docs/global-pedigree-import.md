# Global Pedigree importer

## Britannia Petite spelling correction — October 25, 2026

The collector maps Global Pedigree's `Britannia Petit` label to `Britannia Petite` for owned rabbits and ancestors before review/matching. It strips the original breed suffix from the rabbit's heading before applying the alias, preserving the rabbit name. Collector version 10 is deployed with JWT verification enabled. Migration `20261025183901_britannia_petite_catalog_alias.sql` adds the same exact rabbit-breed correction to the existing catalog trigger without removing or merging any catalog rows or changing its privileges. The app's catalog identity and checklist tooling also recognize the alias.

Seven imported records in Sara's Munchkins were corrected; only breed and the normal revision counter changed. Existing animal IDs, pedigree links, genotypes, colors and history were retained. Validation: 16 collector/history/sales tests, 13 Flutter catalog/checklist tests, scoped analysis, an isolated PostgreSQL catalog-trigger fixture, and a rolled-back authenticated live update confirming the source spelling saves as `Britannia Petite`.

## Unrecorded varieties — October 25, 2026

The owner confirmed `Standard` for imported Standard Chinchillas with unrecorded varieties. Twenty blank records in Sara's Munchkins were updated; only variety and revision changed. Collector version 11 applies this default when the Standard Chinchilla detail page has an explicit Variety field whose value is empty or a recognized placeholder. An absent field remains unknown, explicit varieties are preserved, and Britannia Petite receives no default. All 17 collector/history/sales tests and the function type check passed before deployment; JWT verification remains enabled.

Authenticated browser inspection confirmed the source Variety field reads `None selected` for Britannia Petite records F6 (356609), HIGHER GROUND FARM ON CLOUD / F22 (356610), and HIGHER GROUND ANGEL / A (369177). These remain unrecorded pending owner-supplied values. The other four imported Britannia Petites retain Black (F12), Chestnut Agouti (F62), Opal (OPAL), and Black (OC).

Account Settings → Import & export → Import from Global Pedigree collects the account's All Rabbits list and recursively follows sire/dam links. It previews the import into an owned, non-demo herd and saves only after the user chooses Import into herd.

## Data and matching

The collector reads names, tattoos, breed, variety, Known Genotype (when present), sex, date of birth, current weight in pounds, registration and grand champion numbers, show legs, deceased status, notes, and parent IDs. Unowned ancestors become pedigree-only records. Unknown sex requires an explicit Buck/Doe choice and another preview. Missing ancestors, pedigree cycles, duplicate source IDs, future dates, invalid sex, and unresolved duplicate decisions prevent saving. A shared ear number by itself does not prevent import.

Source-account IDs are hashes of the dashboard's account referral identifier, so signing in by username or email uses the same import identity. Source rabbit IDs are retained in a private provenance table. A repeat import reuses those records. Otherwise, an existing rabbit is reused only when exactly one record matches the normalized name and tattoo, species, breed, sex, and birth date. Placeholder names never match automatically. Explicit keep-separate decisions disable automatic matching. Imported animals have a source-scoped global_pedigree_identity; ordinary manual records retain the tattoo uniqueness index. Existing animals and their weights/parents are preserved. Apparent duplicate groups use name + tattoo + breed + sex as suggestions only. Users choose separate records or one canonical record. Canonical choices require compatible identity and birth dates, retain provenance for every source ID, and redirect child parent references. Conflicting choices, alias chains, cycles created by merging, and attempts to merge records previously imported separately are rejected. The selected record supplies its details; choosing a merge can omit the other record’s differing details, which the preview explains. New animals, weights, provenance, and parent links are saved atomically. Global Pedigree is read only.

Global Pedigree exposes deceased status on the observed detail pages; the importer does not infer sold/retired status. It imports the current displayed weight, not weight history. Photos and owner contact details remain outside this importer. Genotype capture is enabled by the 0.20.1 update below; history support is described in the later updates. Up to 2,000 combined herd animals and ancestors are supported. Collection fails instead of returning a partial pedigree when a page is unavailable or the limit is exceeded.

## Session handling

The Edge Function checks the caller's authenticated, verified Breeder account. Credentials are sent only to Global Pedigree's fixed HTTPS login form and never persisted or logged. Only the upstream session cookies survive sign-in, inside AES-GCM authenticated continuation tokens bound to the Breeder user and expiring after one hour. Continuation tokens remain in memory. Animal data is saved as a private draft during preview, keyed to the authenticated owner and destination herd. Drafts contain no credentials or upstream session tokens. The app resumes a draft for 24 hours; completing an import or choosing another account deletes it. Expired drafts are filtered from restoration and overwritten by a new preview; no background physical-expiry cleanup is currently configured. Redirects outside the fixed origin are rejected before another request can send credentials/cookies. HTML is parsed without executing scripts. Detail requests run sequentially, six per invocation, with timeouts and response-size limits.

The encryption key comes from GLOBAL_PEDIGREE_SESSION_KEY when configured, otherwise a domain-separated derivation from the function's existing SUPABASE_SERVICE_ROLE_KEY. The service role client is never used for data writes. The database RPC runs with the caller's privileges and verifies herd ownership.

## Deployment

Apply `supabase/migrations/20261013133020_global_pedigree_import.sql`, deploy `supabase functions deploy global-pedigree`, and ship the Flutter application containing the new screen. Keep JWT verification enabled. An optional dedicated GLOBAL_PEDIGREE_SESSION_KEY can be configured through Supabase secrets. Do not disable authorization or expose continuation tokens in logs.

Deployed on 2026-10-13 to the existing Breeder Supabase project and Cloudflare Pages. The remote migration history records global_pedigree_import as version 20261013150802; the Edge Function is version 1 with JWT verification enabled. Web deployment: https://fd5ff1ec.ringmaster-breeder.pages.dev, production: https://breeder.ringmasterone.com. The footer identifies 43f3bab-global-pedigree-beta; this was a direct deployment from the local working tree, not a GitHub release. Live-schema synthetic preview, parent-link, and repeat-import tests passed in a rolled-back transaction; unauthenticated function invocation returned HTTP 401. No beta-user animals have been imported. The logged-in beta account's listing and detail DOM were inspected to verify selectors and field mapping (63 All Rabbits records, 32 live). Fresh server-side credential login and complete ancestry collection succeeded for the beta account (155 records). The collection was preserved as a private draft and restored in the updated deployed screen without a new Global Pedigree login. The beta-user commit remains pending sex corrections and duplicate choices; the existing browser login is not transferred to the server.

## Validation

- `flutter analyze --no-pub`
- `flutter test --no-pub test/global_pedigree_import_test.dart test/global_pedigree_collection_test.dart test/record_import_test.dart`
- `npx --yes deno check supabase/functions/global-pedigree/index.ts`
- `npx --yes deno test --allow-env supabase/functions/global-pedigree/collector_test.ts`
- Install `@electric-sql/pglite@0.3.14` in a temporary test directory; set PGLITE_MODULE to its dist/index.js absolute path, then run `node supabase/tests/global_pedigree_import.test.mjs`.

The database test uses an isolated database with matching minimal tables and the repository's real animal-validation trigger. It verifies no-write previews, unordered parent links, historical-status handling, retries, existing-data preservation, conflicts, cycles, invalid input, and cross-herd denial. It does not replace a full deployed-schema integration check.

## Duplicate-review release, 2026-10-13

Apply the additional migration `supabase/migrations/20261013154734_global_pedigree_identity_review.sql`. The source collector function is unchanged. The web release is https://d5c91bb2.ringmaster-breeder.pages.dev and the production footer identifies `43f3bab-global-pedigree-review`. The current test herd’s 155 records were restored successfully. The original nine parent-sex warnings represented missing parent sex and are now suppressed until a known sex contradicts the parent role. Three duplicate pairs and five unknown sexes still require user decisions. No beta animals have been committed.

Validation: 13 Flutter tests, clean analysis, successful release build, expanded isolated database regression tests, and a rolled-back live-schema test of a canonical alias, shared tattoo, child parent link, private draft, and repeat import. Additional tests verify keeping separate records cannot collapse into an existing match, conflicting birth dates cannot merge, and other users cannot read or save drafts in the owner’s herd. Security advisors report expected authenticated GraphQL schema discoverability for these exposed tables; row access remains restricted by ownership policies.

## Readable review details, 2026-10-13

The preview now resolves sire/dam source IDs to collected parent ear numbers and names. Duplicate dropdown options and missing-sex controls show DOB in MM/DD/YYYY format or explicitly say DOB unknown. Source IDs remain the internal choice values and are shown as record references where needed to distinguish equal dates.

Unknown-sex controls show evidence from parent roles in the collected graph. Sire-only usage suggests Buck; dam-only usage suggests Doe; both roles produce a conflict hint; no roles produce no suggestion. Hints do not set sex or permit import without a choice. In the beta collection, W28V appears as sire twice, WILLIE WONKA six times, and GARRETTS MR ANGEL once. HIGHER GROUND ANGEL and SARA’S JASON KELCE have no parent-role evidence in this collection. The source detail field supplied no usable sex for those five. The user’s W28V → Buck correction was saved and retained during the update.

Deployed web version: 43f3bab-global-pedigree-details, https://411cd230.ringmaster-breeder.pages.dev. Fifteen Flutter tests, clean analysis, and a release build passed. Live inspection verified parent ear numbers, DOB dropdown options, sex hints, and restoration of all 155 collected records. No backend/schema changes were needed for this revision.


## Historical records release (2026-10-13)

Release `43f3bab-global-pedigree-history` collects herd litters from the observed `archive=show` URL, including hidden records. Sara's observed list contains 73 records. Each litter retains its source ID, both parents, category, dates, totals (including fostered/added/raised), comments, recorded litter events, and available offspring source IDs. Offspring missing from the initial animal graph are collected before completion. Multiple same-date failed breedings remain distinct.

History is stored in `global_pedigree_history`, with herd-owner RLS, atomic animal/history commits, original-source provenance, and retry deduplication. Rabbit merges resolve history from both IDs onto the kept animal. Account Settings, rabbit detail, and Breedings & litters link to a read-only imported-history view. Imported litter records are separate from the active tracking workflow, whose same-date uniqueness and active-parent requirements cannot represent source archives without loss. No new offspring are fabricated from numeric litter totals.

Full dated weight tables are collected for every animal in the source All Rabbits list, including historical herd animals. Ancestor-only source records retain profile details but are not treated as the user's owned weight history. Chart birth-date zeroes are ignored. When collection is complete, new imports use dated source weights for rabbits with weight history instead of creating a current-time snapshot from their profiles. Known ancestor profile weights without accessible recording dates remain available as undated-source snapshots. Historical locked-animal weights require an accessible history record with exactly matching original date and weight; ordinary locked-animal additions remain rejected.

Individual show result pages were not found, and the user did not know of one. The preview explicitly reports this limitation; show-leg totals continue to be preserved. Questionable litter dates such as 1970 and 2926 are preserved verbatim and flagged in the preview. The source is not edited.

Testing: 10 collector/parser tests; 13 affected Flutter tests; isolated PostgreSQL preview, alias, atomicity, dated-weight, locked-animal, retry and cross-owner checks. Source fixtures parsed 73 archived litters and the observed 2025-05-15 weight. Live synthetic weight/litter commits and retries passed inside a rolled-back transaction; no verification rows remain.

The initial Testing For Sara reset attempt was unperformed: Supabase connector deletion calls return `Invalid or expired requestState`, CLI SQL execution fails creating its login role. A local backup exists at `/private/tmp/global-pedigree-import/testing-for-sara-before-reset.json` (152 animals, 155 source mappings, 57 weights). No other herd was changed.


Testing For Sara reset completed on 2026-10-13 after the user renewed the request. All 152 animals were deleted; cascading weight/source-history/source-mapping removal was verified, with zero remaining animals, source mappings, or imported history. The herd itself was retained. The pre-reset backup remains available locally.


## Live herd status correction (2026-10-13)

Release `43f3bab-global-pedigree-live-status` reads and verifies both All Rabbits and All Live Rabbits lists, requesting the complete number of rows and checking that live IDs are a subset of collected herd IDs. The importer archives non-deceased owned records outside the live list, preserving deceased status and pedigree-only ancestor classification. `archived` deliberately does not infer sold or retired. Keeping a historical duplicate with a live alias retains active status. Old continuation tokens require reconnection to avoid unverified status mapping.

Sara's existing import was corrected against the observed 32-member live list: 32 active, 19 archived, 9 deceased herd rabbits. The correction changed only those 19 active statuses; 187 total animals, 64 weights, 79 history records and 247 parent links were unchanged. An exact status backup and source membership list are stored locally at `/private/tmp/global-pedigree-import/sara-status-correction-backup.json`. No reimport is needed. Archived rabbits remain available in the animal list Archived filter.

Verification: 12 collector/history tests, 15 Flutter import tests, isolated PostgreSQL tests for archived insertion and a kept historical duplicate with a live alias. Analysis and release web build passed; the active Edge Function is version 4 with JWT verification enabled.


## Historical sales release (2026-10-14)

Release `bc7a27c-global-pedigree-sales` is deployed at https://9630a9a5.ringmaster-breeder.pages.dev and production breeder.ringmasterone.com; production JavaScript SHA-256 matches the tested build. Edge Function version 6 keeps JWT verification enabled. The sales list parser uses the observed results_table columns and sale/rabbit links. It preserves source sale IDs, original fields, dates, exact cents including explicit zero, and blank buyer names. Sales-linked rabbits outside the original animal graph are collected and classified as historical herd records, without changing verified live membership. Individual sales-detail notes, buyer contact fields and payment receipts are not collected from this list.

The beta source contains seven sales: five explicit zero prices, and two separate source sale IDs for GARRETTS MR ANGEL at $3 each. Both Angel sales link to rabbit 211161, absent from the earlier 194-source animal collection; they must not silently link to similarly named 211160. Source inspection used the importer’s authenticated connection because the native signed-in browser was not accessible to browser tools. A caller-private, expiring source preview enabled inspection; ongoing collection no longer saves those diagnostic pages.

The invoker RPC import_global_pedigree_with_sales wraps the existing atomic animal/history import and adds owner-authorized animal_sales records. Provenance prevents duplicate retries and retains resolved animal aliases. Source sales use sold status without rewriting animal status. Missing buyer, date or amount remain missing; payment_history_complete=false prevents invented unpaid balances. Owners can reconcile receipts and mark payment history complete in Edit sale. The dashboard identifies imported sale IDs and excludes unknown balances from balance totals.

Verification: 14 Deno collector/history/sales tests, 19 Flutter importer/sales tests, clean changed-file analysis and release build, isolated PostgreSQL checks for blank buyers, zero amounts, separate same-date sales, owner RLS, retries and unchanged archived status. Live authenticated sales insertion passed inside a rolled-back transaction. No verification records remain; Sara still has 32 active herd animals and zero committed sales at release. Her prior preview predates sales collection, so a fresh connection is required before saving the seven sales.

Post-import verification: all seven sales committed successfully with matching dates, prices and source IDs. Both Angel sales resolve to the explicitly merged rabbit aliases 211160/211161; Wigley retains aliases 260747/260753. All seven are Sold, retain blank buyers and incomplete payment history, and contain no fabricated payments.

## Genotype capture — prepared October 20, 2026

**Version 0.20.1 update: the two database migrations are applied and collector version 7 is deployed.** The reviewed implementation requires both `20261020105258_animal_genotype_record.sql` and `20261020112220_global_pedigree_genotype.sql`, plus the updated collector function. Existing saved drafts and previous collections do not gain missing genotype text automatically; reconnect to collect it after deployment.

The detail parser reads **Known Genotype** on owned rabbits and linked ancestors, preserving case, internal spacing and unknown `_`, `-` and `?` symbols. Blank or absent fields stay absent; it never substitutes a genotype based on breed or variety. Duplicate/unreadable genotype rows and overlong values stop collection rather than silently dropping the text. The screenshot supplied by the owner (`aa bb C_ dd E_`) is included as a synthetic parser/import fixture; no live source account was scraped in this change.

New animal records receive `{notation, basis: imported, source}` in the Animal Details genotype field. The source explicitly names Global Pedigree's Known Genotype field and notes that the method is unverified. A source field label does not prove laboratory testing or a complete genotype; contradictions are not silently corrected. Version 0.20.1 applies readable compatible saved references as prediction constraints, retaining unknowns and blocking unsupported/conflicting notation.

Existing animals remain unchanged, including existing genotypes and empty genotype fields. The incoming text is shown in preview and stored separately in `global_pedigree_animals.source_known_genotype`. Repeat imports can refresh this source reference without changing the animal's chosen genotype; a subsequent missing/blank source value does not erase an earlier captured reference. On explicit merges, the selected record supplies the animal genotype and every source ID retains its own reference text. Duplicate review displays these differences.

The importer remains a security-invoker transaction under the existing herd-owner RLS. The only new provenance grant is `UPDATE(source_known_genotype)`; source identity/animal mapping columns do not gain update access. Preview preserves the source text in the private draft without changing animal/provenance rows. Malformed incoming genotype values block commit along with other review issues.

Validation: **15 collector/history/sales tests and 10 Flutter collection/import checks passed**, plus the full isolated PGlite import fixture. Database checks include preview/draft preservation, new records and ancestors, literal unknown markers, absent values, retries, manual-record preservation, merge evidence, malformed payload rejection, the sales/history wrapper used by the client, and owner isolation/column privilege checks. Scoped Flutter analysis is clean. No credentials, source settings, real records or production schema changed. Reviewed the cached current Supabase changelog and [official database function guidance](https://supabase.com/docs/guides/database/functions).

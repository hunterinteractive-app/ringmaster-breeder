# Kintraks CSV import

Account → Import & export → Import from Kintraks accepts the **All records → CSV file** export using comma delimiter and double-quote wrapping. This version supports rabbit databases. Native `.cax` backups are not accepted.

Choose a personally owned, non-demo destination herd and a source database name. Reuse that name for later exports of the same database. Use a distinct source name for another breeder's database. Names are trimmed and case-insensitive; filenames are not import identities.

## Data and review

The parser reads UTF-8 CSV locally, including quoted commas, escaped quotes, and multiline notes. Every original field and ordered header is retained. Both repeated `Breeder` columns survive: `Breeder [1]` is the boolean source flag, and `Breeder [2]` is the breeder name. Unrecognized custom columns remain in source history. Ambiguous duplicate headings are rejected. Limits: 10 MB file, 2,000 rabbits, 500 columns, 15 MB server payload.

Animal names combine prefix, name (or ear number/fallback label), and suffix. Breed, colour, sex, DOB, ear number, registration number (`Registration #`), GC number, integer legs, and notes map to animal fields. The separate `Registration` field stays in the source snapshot. Unknown sex needs explicit review; blank breeds and dates remain blank. Non-integer leg counts generate warnings and remain raw without becoming an invented integer. The searchable **Review and edit rabbits** section opens an editor for every CSV field except the fixed source ID. Apply corrections before preview; originals remain unchanged. For a valid lb.oz value in Legs, **Move Legs value to Weight** replaces Weight and clears Legs only when the user applies the correction. The editor shows original values, validates dates/weights, supports Reset to CSV, and recomputes source warnings. Corrections are saved separately with the import decisions; existing animals remain unchanged. All corrections reset acknowledgment and invalidate the prior preview.

**Weights use pounds and ounces:** `3.13` = 3 lb 13 oz = 3.8125 lb; `3.04` and `3.4` = 3 lb 4 oz; `3.10` = 3 lb 10 oz; `3.1` = 3 lb 1 oz. The original string is never converted through a decimal-number parser. Ounces must be 0–15. The RPC independently checks the conversion. These profile snapshots have no measurement date, so they do not create dated weight entries.

Parent relationships use `Fatherid` and `Motherid`, never names. Repeated names and ear numbers remain distinct source IDs. Missing parent references produce warnings and stay unlinked; original references remain in the source snapshot. Wrong parent sexes and cycles require explicit link omissions or correction in Kintraks. Chronology warnings flag birth dates on/before a parent's birth date without rewriting source dates.

**Current herd membership is explicit.** Sold/deceased flags retain their source status, even without a sale/death date. Every other rabbit defaults to archived and pedigree-only. The searchable Current herd section lets the user select living, unsold rabbits to become active. Blank ownership and the Breeder flag never imply active ownership. Existing linked or previously imported animals keep their status and pedigree flags.

The acknowledgment label is **I reviewed the source warnings**. Source warnings require acknowledgment. Server preview performs no writes. Changes to source/herd, current herd membership, sex, parent omissions, or existing-animal choices invalidate the prior preview. Nothing saves until Import into herd. An exact existing-animal candidate requires name, tattoo, species, breed, variety, sex, and DOB to match and needs an explicit link/separate decision. Existing details, parents, weights, and status are preserved.

The final RPC inserts animals, parents, source identities, raw snapshots, normalized undated weights, and review choices in one transaction. Imports into a herd are serialized. Retrying the same source IDs adds nothing. First snapshots remain immutable; changed name/prefix/suffix/ear/breed identities block reuse of the same mapping. Other source changes produce preservation warnings. This is an import, not synchronization.

All original custom fields, breeder/owner names, COI, vaccine details, merits, sales flags/dates, and purchase fields remain in Kintraks history, accessible from Account → Imported history and animal details. They do not create contacts, treatments, payments, active breeding workflows, or calculated COI values. The CSV does not contain separate mating, litter, show-result, image, or dated weight-history records.

## Database and release

Apply `supabase/migrations/20261019015628_kintraks_import.sql` after the existing Rabbit Register migration before releasing the client. It adds `animals.kintraks_identity`, `kintraks_sources`, `kintraks_animals`, and the invoker RPC `import_kintraks`. Owner RLS restricts source data to personally owned, non-demo herds. Anonymous execution is revoked; the function fixes its search path and repeats ownership, IDs, date, weight, graph, and existing-match checks. The manual tattoo unique index continues to exclude all three independently identified importer types.

Preview and commit require internet. The offline workspace never queues or replays the import; after a successful commit it refreshes the downloaded herd. Source history is online-only.

Implementation is deployed. No Kintraks breeder records were imported into production by the deployment checks.

## Verification

The supplied CSV parsed as 537 rabbits, 862 parent links, and 328 undated weights. Its 42 columns include two Breeder headings. There are no missing source parents, cycle conflicts, or parent sex conflicts. Warnings include three missing breeds, date chronology for two animals, and one non-integer leg count. With no current herd selected, the isolated import produces 533 archived pedigree-only rabbits, 3 sold rabbits, and 1 deceased rabbit. Repeat import adds zero. Personal sample files and generated JSON stay outside the repository.

Run:

```sh
flutter test --no-pub test/kintraks_csv_test.dart test/kintraks_import_test.dart test/rabbit_register_xml_test.dart test/rabbit_register_import_test.dart test/global_pedigree_import_test.dart test/global_pedigree_collection_test.dart test/record_import_test.dart
node --test tool/offline_workspace_test.cjs
PGLITE_MODULE=/absolute/path/to/@electric-sql/pglite/dist/index.js node supabase/tests/kintraks_import.test.mjs
```

The isolated PGlite fixture uses the production animal validation trigger. It tests owned-herd access, other-owner isolation, anonymous denial, demo-herd denial, source identities, explicit candidate choices, preserved existing details, status and weight validation, parent graphs, late transaction rollback, manual tattoo uniqueness, and repeat imports. It never contacts Supabase.

Optional full sample checks:

```sh
dart run tool/inspect_kintraks.dart /absolute/path/to/Export.csv /private/tmp/kintraks-sample.json
PGLITE_MODULE=/absolute/path/to/@electric-sql/pglite/dist/index.js KINTRAKS_PAYLOAD=/private/tmp/kintraks-sample.json node supabase/tests/kintraks_import.test.mjs
```

Final local checks: all 47 import regression tests and all 42 offline workspace tests passed. The full sample committed and retried successfully only inside the isolated fixture. Kintraks static analysis found no issues. Desktop and 390px phone layouts were rendered using the supplied CSV and real app fonts, with a preview-only gateway that cannot save. The release web build and offline packaging passed. The full-project analyzer reported four existing style notices in the unrelated genetics work; no Kintraks notices remain.

## Deployment — October 18, 2026

Published with user authorization to https://breeder.ringmasterone.com as `463bb47-kintraks-import`; immutable deployment https://97fc23a9.ringmaster-breeder.pages.dev. The release was staged separately from the shared working tree using base commit 463bb47 plus the Rabbit Register and Kintraks importer files. Unrelated unfinished Genetics work was excluded and remains intact locally. This was a direct Cloudflare Pages deployment, not a new Git commit or PR.

Production migration `20261019021943_kintraks_import` corresponds to local `20261019015628_kintraks_import.sql`. Preview, two-rabbit save, a corrected weight, raw/corrected field preservation, pedigree links, archived pedigree status, and retry were verified in a subtransaction that was deliberately rolled back. There remain 632 animals and zero Kintraks sources after deployment verification. Both source tables have owner RLS; the function is invoker and anonymous execution is denied.

All 49 import regression tests and 42 offline tests passed. The full CSV passed the isolated database transaction/retry suite, including corrections and failure rollback. The actual source #100 dialog was rendered and the Legs-to-Weight action exercised at desktop and 390px phone sizes, with a gateway unable to save. Analysis passed after initializing the release copy's dependencies; release build and offline packaging passed (worker revision `b300be5dd0c4d170f1ee`). Production JavaScript matched the packaged release and contained the simplified checkbox and correction controls.

Security advisors have the same baseline findings plus expected [authenticated GraphQL schema discoverability](https://supabase.com/docs/guides/database/database-linter?lint=0027_pg_graphql_authenticated_table_exposed) for the two client-readable Kintraks source tables. Owner RLS still protects their row data. Other advisor findings predate this release.

Export-help follow-up: added a clearly separated instruction card above Step 1 covering opening the source database, Database → Export Records, All records, Comma delimiter, Double Quotes wrapping, saving CSV, and selecting it in RingMaster. The card explains that `.cax` backups are not accepted. No import behavior or database schema changed.

Deployed the export instruction card as `463bb47-kintraks-export-help` at https://108bfd9b.ringmaster-breeder.pages.dev, worker revision `23229f10efa5497dfe21`. Analysis and release build passed. No database changes were needed.

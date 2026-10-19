# Rabbit Register XML import

Account Settings → Import & export → Import from Rabbit Register accepts the XML produced by Evans Rabbit Register's **Other** export. Choose a personally owned, non-demo destination herd and name the source database. Reuse that source name for later exports of the same database; use a different name for another breeder's database. Source names are trimmed and case-insensitive. Filenames are not identities.

The file is parsed locally. Preview and saving require a network connection. Nothing is saved during preview. The final invoker RPC revalidates the payload and saves animals, source identities, source snapshots, dated weights and history in one transaction. Concurrent imports into a herd are serialized. Existing source IDs are reused on retry. Original XML files are never modified. No real user import or production deployment is performed by the implementation tests.

## Supported data

- Animals: source CID, name, tattoo, breed, variety, sex, birth date, registration and grand champion numbers, legs, comments, sire/dam links and status. Active storage remains active. Archive storage becomes deceased when it has a death date, sold when it has a sale date, otherwise archived. Archived animals are never made active just to import them.
- Missing names fall back to the ear number, then the visible label `Rabbit Register #CID`. Original blank fields remain blank in the source snapshot.
- Source IDs remain distinct. An exact existing-animal candidate requires name, tattoo, rabbit species, breed, variety, sex and birth date to match. Users explicitly choose a candidate or a separate new animal; tattoo alone never merges records. Existing animals retain their fields, parent links and weights.
- Dated weight measurements convert from grams to pounds (453.592 grams per pound). The supported XML format stores grams; conversion to pounds is automatic and there is no unit selector. Measurements are added to weight history only for animals created by this transaction. Measurements for linked existing animals stay in source history. Profile weight snapshots have no date and are retained as snapshots, without inventing a measurement date.
- Contacts, show results and litter/breeding records are retained in a separate, owner-private source history with original fields, IDs and available animal links. Nested contact categories remain XML text. Sale fields, cage, storage area, date qualifiers and other unmapped animal fields remain in the rabbit snapshot. Contacts do not become login identities. Source litters/sales do not create active breeding workflows, buyer payment obligations or receipts.
- Rabbit Register history is accessible from Account Settings, animal details and Breedings & litters. It paginates source records and shows original fields and import review decisions.

## Review and validation

The observed Other exporter crashes after a closed `CritterWeights` section without closing `ExportedData`. This exact structural case can be recovered in memory by adding the final root closing tag. A warning requires acknowledgment because other sections may have been omitted by the source crash. XML cut off inside a record or section is rejected. Recovery does not claim the export is complete.

Unknown sex needs an explicit Buck/Doe selection. Missing source parents remain unlinked only after acknowledgment, with the original IDs retained. No placeholder ancestors are invented. Parent-role conflicts and pedigree cycles block saving; the screen offers explicit omissions of the problematic links while retaining their original values. Users may instead correct the source and export again. Server validation independently checks source IDs, dates, weights, parent sexes and cycles even if the client controls are bypassed.

Only UTF-8 XML with the `ExportedData` root and the observed Header/Animals/Contacts/Winnings/Litters/CritterWeights sections is accepted. Unknown sections are rejected rather than silently dropped. DTD/entity declarations, repeated fields/sections/source IDs, malformed XML, invalid/future normalized dates and invalid measurements are rejected. Access's `0100-01-01` date sentinel stays missing in normalized values and remains unchanged in original history. Limits: 10 MB file, 2,000 rabbits, 20,000 history records. The server also bounds payload size.

First imported snapshots are immutable through the importer. Reimports preserve existing details and history; they do not synchronize edits. Changes to a previously imported CID's name, tattoo or breed block the import so the user can check the source identity. Other changes to animal snapshots generate preservation warnings. A new source label is not a substitute for reconciling changes to the same database.

## Initial sample validation

The supplied Other XML contains 592 rabbits (35 active), 17 contacts, 628 show records, 97 litters and 50 dated weights. It has three unknown sexes, eight rabbits with neither name nor tattoo, four missing animal-parent references, and two litters referencing another absent sire. The parser identifies four cycle-closing links for explicit review. These problems were not apparent from the earlier count-only inspection.

The sample was parsed locally and committed/retried only in an isolated PostgreSQL fixture using test-only sex selections and link omissions. Those choices are not user decisions and must not be copied into a real import. The test verifies 592 animal inserts and 792 history inserts with no additions on retry. Personal sample data is not committed to the repository. Another breeder's export is still needed to broaden compatibility validation.

## Setup and verification

Apply `supabase/migrations/20261018215207_rabbit_register_import.sql` before releasing the Flutter client. No Edge Function or new server secret is required. The migration adds source tables with owner RLS and a `SECURITY INVOKER` RPC with a fixed empty search path, explicit grants and an owned-herd check. The ordinary manual-tattoo uniqueness rule continues to apply to manual animals; imported Rabbit Register and Global Pedigree animals have separate source identities.

The importer is online-only. The offline workspace passes this RPC to the server and refreshes the downloaded herd after a successful commit. XML and previews are not silently queued. Source history itself is not added to the offline download in this version.

Run:

```sh
flutter test --no-pub test/rabbit_register_xml_test.dart test/rabbit_register_import_test.dart test/global_pedigree_import_test.dart test/global_pedigree_collection_test.dart test/record_import_test.dart
flutter analyze --no-pub
node --test tool/offline_workspace_test.cjs
flutter build web --release --no-pub --pwa-strategy=none --dart-define=OFFLINE_PILOT=true --dart-define=OFFLINE_FULL=true
```

For the database tests, install `@electric-sql/pglite@0.3.14` in a temporary directory and set `PGLITE_MODULE` to its `dist/index.js`, then run `node supabase/tests/rabbit_register_import.test.mjs`. These tests never connect to Supabase. They check ownership/RLS, anonymous access, demo-herd rejection, parent graphs, candidate decisions, preserved existing animals, invalid dates/weights, retries and a late transaction failure.

Optional local sample inspection (contains personal data; keep JSON outside the repository):

```sh
dart run tool/inspect_rabbit_register.dart /absolute/path/to/export.XML /private/tmp/rabbit-register-sample.json
```

Set `RABBIT_REGISTER_PAYLOAD` to that JSON when running the database test to exercise the initial 592-rabbit sample. The optional sample test intentionally assumes the observed counts and applies test-only decisions to exercise a complete transaction.

## Deployment — October 18, 2026

Deployed with user authorization to [RingMaster Breeder](https://breeder.ringmasterone.com). The release marker is `463bb47-rabbit-register-beta`; the immutable deployment is [77ce884c](https://77ce884c.ringmaster-breeder.pages.dev). This was a direct Cloudflare Pages deployment of the local working tree, not a new Git commit or GitHub release.

The production Supabase migration is recorded as `20261018221950_rabbit_register_import`, corresponding to local migration `20261018215207_rabbit_register_import.sql`. No Edge Functions were changed. The frontend was built with both offline flags and packaged with worker revision `6ad58d331f4e5db5dce6`.

Live verification passed: a caller-authorized preview, two-rabbit commit, historical weight, sire link, archived/deceased status and repeat import were exercised inside a transaction that was rolled back. Production still has 40 animals and zero Rabbit Register sources, mappings or history records after verification. The RPC uses invoker privileges, denies anonymous execution, and all three source tables have RLS enabled. An anonymous HTTP request returned 401 / permission denied for the function.

The custom production domain returns HTTP 200 with no-store headers. Its JavaScript, offline worker and offline config match the local release byte-for-byte; the JavaScript contains the release marker and Rabbit Register entry point. The existing browser compatibility check passed. Security advisors show the expected [authenticated GraphQL schema visibility](https://supabase.com/docs/guides/database/database-linter?lint=0027_pg_graphql_authenticated_table_exposed) notices for the three client-readable source tables; owner RLS still restricts row access. Other findings predate this deployment.

No breeder XML was imported into production. Users must review their unknown sexes and pedigree links before choosing Import into herd. Another breeder's export remains useful for broader format validation.

Account-page follow-up, October 18: moved Rabbit Register, Global Pedigree and RingMaster imported-history links into a separate **Imported history** accordion below Import & export, collapsed by default. Released as `463bb47-import-history-section` at https://d8c74b0a.ringmaster-breeder.pages.dev with offline worker revision `90752959ab63d338df5a`. Changed-file analysis and the release build passed; production JavaScript and worker matched the packaged release. No database changes were needed.

Import-review follow-up, October 18: removed the unverified pounds-input fallback. Supported Rabbit Register XML always uses grams, converted automatically to pounds. Reorganized the form into Choose your export / Review source data / Review import cards; moved source-name guidance outside the field, spaced all review controls, and added the destination/source summary before the save button. Rendered the supplied XML at desktop and phone sizes using the actual app fonts and a preview-only gateway with no database calls. All 32 import regression tests, changed-file analysis, the isolated sample transaction/retry and the release build passed. Deployed `463bb47-rabbit-register-review` at https://aa6d1ce8.ringmaster-breeder.pages.dev; offline worker revision `f0de66356dd4b9e8b8c1`. Production JavaScript and worker matched the release, and the old units selector text was absent. No schema change or user import was performed.

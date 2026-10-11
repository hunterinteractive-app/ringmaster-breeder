# Connected Show reports

Account → Connected show programs → Receive show reports is independent of herd sharing. Enabling it performs a refresh; the report inbox refreshes on opening and offers manual refresh. This is pull-on-open, not a scheduled background job.

The server revalidates both accounts' verified emails on each refresh/download. Family members can read and refresh an authorized family's reports but cannot change the owner's receiving preference. Show exports only current generated exhibitor/leg artifacts authorized by exhibitor ownership, claim, or entry ownership, excluding test/demo shows. Results require an available exhibitor report. Downloads recheck current source access and use a two-minute signed URL.

Snapshots apply atomically. Repeated entry IDs update historical results instead of duplicating them. Exact linked animal IDs or import provenance attach results; unmatched entries remain visible in the inbox. Animal details, manual leg totals and pedigree notes are not overwritten. Missing source artifacts/results remain marked unavailable; disabling receiving retains received history. PDFs remain hosted in Show and require continued source availability.

Server functions are service-role-only; received data uses family RLS. A settings version and start timestamp reject disabled/reconfigured or stale concurrent refreshes. Failed/oversized pagination does not replace the stored snapshot.

Verification: `supabase/tests/connected_show_reports.sql` and Show's `supabase/tests/breeder_report_export.sql` run in rollback transactions. Widget coverage is in `test/show_reports_test.dart`.

Show history presents placements and award badges from current entry fields, entry awards, and legacy result details. Missing placements remain explicitly unrecorded. Eligible major wins on matched animals are composed separately from manual show notes and included beneath the animal block in the shared pedigree layout (preview, tree, and PDF). Withdrawn, scratched, disqualified, and no-show results are excluded. Refreshing a correction replaces generated wins without editing manual notes or leg totals.

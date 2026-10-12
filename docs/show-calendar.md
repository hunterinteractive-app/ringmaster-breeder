# Entered shows on the herd calendar

The calendar refreshes active Show entries on open and manual refresh. It uses the herd owner's existing verified Show account link, including when an authorized family member opens that herd. No separate report opt-in is needed because this is entry scheduling, not report import.

Shows appear once on their opening date, with the full date range, location, and active entry details. These are account-wide shows, not limited to animals matched to the selected herd. The UI labels this scope explicitly. The snapshot is replaced on each refresh, so withdrawn entries disappear without duplicates. No background push or offline persistence is claimed. On service failure the calendar shows herd dates and an explicit show-refresh warning.

Show's breeder_calendar_export is SECURITY INVOKER, service-role only. It scopes entries by exhibitor account ownership or claim and allows only active/submitted/entered statuses, excluding scratched, test, demo and closed shows. Draft cart entries are not exported. The show-calendar Edge Function authenticates with getUser, resolves the requested herd through caller-scoped RLS, checks the active owner and both verified account emails, and never accepts a caller-supplied Show user ID. It uses existing server-only integration secrets.

Tests: Show rollback fixture verifies ownership, active statuses, pagination, one show per event, scratch removal, closed shows and client RPC denial. Flutter tests verify calendar event deduplication, multi-day display, and entry details.

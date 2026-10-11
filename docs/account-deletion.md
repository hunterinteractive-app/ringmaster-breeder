# Account deletion

Account → Account management → Delete account asks for an emailed sign-in code and the literal DELETE. The Edge Function verifies the current JWT with Auth, derives the target from that verified identity, verifies the email code with a separate client, and checks that both identities match. It never accepts an owner ID from the caller. No email is sent until the user requests a code.

`begin_account_deletion` records durable scope and storage paths, locks the profile, revokes family access, and disables Show sharing/report receiving. Only service_role may execute cleanup functions. Deletion is limited to owned herds. References from other households and uploaded files owned by the user outside their own herds require ownership review before anything starts.

Show's existing snapshot API receives an empty snapshot with an infinite version, retiring the connection against in-flight older updates. Managed picker animals are hidden; original Show animals, show entries/reports, and the independent Show account remain. Uploaded animal photos and health files are removed via the Storage API. Related rows are then removed in one transaction, followed by Auth Admin deletion. The inactive public profile remains until Auth deletion cascades it, preventing accidental identity recreation on partial failure. Shared breed/variety catalogs remain.

A persisted deletion can be resumed by the same authenticated user without another code. On app reload, the account-deletion gate displays recovery before normal account access. A failure never reports success. After successful Auth deletion the request row is also removed. No actual customer account is deleted as part of deployment/testing.

Stripe is not yet connected. If STRIPE_SECRET_KEY is configured, new deletion requests fail closed until billing cancellation is implemented; integrate cancellation before enabling paid subscriptions. A CSV export contains only the advertised animal fields, not a complete backup. Provider backups follow their existing retention policy.

Validation: `supabase/tests/account_deletion.sql` uses fictional accounts in a rolled-back transaction to verify shared-reference refusal, owned-data cleanup, retry idempotency, other-household preservation, function grants, and final identity cascades. Existing app test suite and analyzer also pass. Full email delivery and external Storage/Auth API success require testing with a disposable account.

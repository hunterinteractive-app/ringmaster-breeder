# Super-admin support access

Account → Super Admin → View As User provides read-only account, herd, and animal inspection. It never replaces the signed-in session or selected household. Target account views are recorded in breeder_private.support_audit.

Only auth user IDs explicitly added to breeder_private.super_admins can access the support RPC. The account must remain active, verified, and unbanned. Grant and revoke access through trusted database administration; the application has no self-grant endpoint. Initial production access is limited to the owner-approved account. Do not seed grants in migrations.

Ordinary household RLS is unchanged. Both private tables deny client access. The authenticated SECURITY DEFINER RPCs intentionally check the private allowlist on every request and use an empty search path. The security advisor notices for their authenticated execution and policy-free private tables are intentional. The rollback test in supabase/tests/super_admin_support.sql verifies denial, self-grant prevention, authorized reads, audit logging, unchanged ordinary RLS, and revocation.

Audit entries retain actor and target identifiers after account deletion for support accountability. No contact details or animal contents are copied into audit rows.

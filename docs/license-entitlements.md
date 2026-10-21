# License plans and animal usage

Released as 0.21.0. The migration and buyer-email Edge Function were applied to the existing Breeder project; no animal, herd, user or license assignment was removed.

| Plan | Annual USD | Active animals, account total | Herds |
| --- | --- | --- | --- |
| Hobby | $49 | 50 | 1 |
| Professional | $99 | 250 | 1 |
| Top | $179 | 1,000 | 5 |

`license_tiers` is the catalogue. Prices are integer cents and do not initiate charges. Checkout, payment processing and automatic subscription renewal are not implemented. Existing testing enrollment and non-expiring licenses remain intact.

An animal counts only when `status='active' AND NOT pedigree_only` in a non-demo herd. Sold, deceased, retired, archived, and pedigree-only ancestors do not count. Active young animals count. All herds belonging to an owner share one allowance, including work performed by accepted family members. The highest current active plan is selected consistently; multiple licenses do not stack. Future-starting, expired and cancelled licenses do not qualify.

## Enforcement and grace

`breeder_license_usage` stores a locked per-owner counter and the first at-limit timestamp. Clients have family-filtered SELECT only; they cannot edit counts, grace dates or tiers. An AFTER-row animal trigger covers direct REST writes, creation/breeding RPCs, imports, pedigree promotions and offline replay, including writes performed using a service role. Transactions roll back failed changes and counter updates together. Normal creation still enforces herd limits through the guarded RPC.

At exactly the animal limit, the server starts 30 days. Growth during grace is allowed, including births and imports. Additional growth or revisiting the page does not renew the deadline. After the deadline, increases to the active count are rejected. Existing records remain accessible and editable under normal record rules, and sold/deceased updates and exports remain available. Reducing the count below the limit clears the continuous at-limit period; reaching the limit again starts a new period. Upgrading above current usage clears it as well. At exactly the limit after expiry, growth remains blocked. There is no automatic deletion or forced data conversion.

Accounts without a qualifying license cannot increase their active count. Existing herd access is preserved. Downgrades do not delete existing herds. Existing accounts at/over capacity at migration receive a fresh 30 days.

## Features

Every paid plan retains core records, health, breeding, basic sales, pedigrees, imports, exports, household sharing, calendars, Show integration and offline access. Buyer pedigree emails require Professional or Top; the deployed email Edge Function calls `breeder_require_feature` after resolving the animal's actual owner and before preparing or delivering email. Queued email jobs invoke the same function and are rechecked at processing time.

`custom_pedigree_branding` and `saved_pedigree_layouts` are reserved Professional/Top entitlements. The authenticated, owner-checked feature guard is available for their future endpoints. No custom editor, saved-layout persistence, or unfinished UI was added; the plan dialog explicitly identifies them as planned.

## Offline and recovery

The existing RLS-filtered offline snapshot includes the authoritative usage/grace table. Local usage counts include provisional queued changes, are labeled accordingly, and never invent or extend a server deadline. Expired downloaded grace blocks local growth. The server rechecks every replay against its current plan and clock; rejected drafts remain on the device. Old downloaded workspaces must sync to acquire the new plan/usage data.

Service backups classify the new usage table as preserved operational state. Complete backups include it. Individual-owner recovery preserves current licenses/grace and reconciles the current active counter after restoring animal rows with user triggers disabled.

## Validation

- 478 Flutter tests passed; new tests cover warning thresholds, grace messaging and narrow-screen layouts with enlarged text.
- Backup unit tests passed (11 executed; 7 database integration tests require a separately configured backup fixture).
- 46 offline repository tests passed, including license selection, exclusions, grace-clock preservation and growth blocking.
- Code analysis and production web build passed; browser startup/rotation compatibility checks passed.
- New SQL entitlement tests passed locally and against live Supabase inside a rolled-back transaction, covering catalogue prices, warning boundaries, 30-day clock, family isolation, expiry, promotions, exclusions, features and multi-herd totals.
- Concurrent local writes preserve exact counts and expired grace rejects privileged import writes.
- Existing family, pedigree, testing enrollment, revision, sales, calendar and offline replay/import SQL regressions passed on the isolated local schema.
- Production verification found all 632 animal rows, 3 herds and 4 license rows retained, no counter mismatches, and no authenticated EXECUTE grant on internal counter functions.

An existing offline default mismatch (`genotype` missing locally versus `{}` on the server) was corrected because it prevented sale-payment replay from marking an animal sold. That workflow passed after correction.

Supabase advisors report existing restricted-table/no-policy informational notices and intentional authenticated schema/function visibility warnings. The new usage table has family RLS, public API wrappers use SECURITY INVOKER, and privileged implementation functions live in the private schema with explicit grants. GraphQL visibility of the usage table is expected for authorized SELECT and remains subject to its family policy. Reference: https://supabase.com/docs/guides/database/database-linter?lint=0027_pg_graphql_authenticated_table_exposed

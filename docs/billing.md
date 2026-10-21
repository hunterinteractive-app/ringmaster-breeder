# RingMaster Breeder billing

Live merchant: **Hunter Interactive LLC**, account `acct_1T85ZRLAhl5IBJ5k`. Breeder has its own products, prices, customers, portal configuration and webhook; existing RingMaster Show resources are untouched.

| Tier | Monthly USD | Yearly USD | Active animals | Herds |
| --- | ---: | ---: | ---: | ---: |
| Hobby Breeder | $5 | $49 | 50 | 1 |
| Professional Breeder | $10 | $99 | 250 | 1 |
| Top Tier | $18 | $179 | 1,000 total | 5 |

`license_tiers` defines capabilities and capacity. Its original annual-price column is a legacy baseline; `breeder_billing_prices` contains the actual immutable price offers. The account screen shows the subscriber's actual offer, including older locked prices. Capacity and feature enforcement still use `user_licenses`, including the existing active-animal/grace-period triggers. Planned pedigree branding and saved layouts are still unavailable.

## Customer controls

Account → **Manage membership & billing** (also My Herds → View plans). Billing always uses the signed-in account's own owner ID, irrespective of the selected shared household. All billing calls bypass offline storage and queues. They require an internet connection.

Customers can purchase monthly or yearly plans, manage their payment methods and invoices, cancel future renewals, and schedule tier or billing-interval changes. **All plan changes take effect at the next renewal**, including upgrades. The current paid term is preserved without immediate proration. A new tier activates only after its renewal invoice is paid. Canceled memberships keep access through the paid-through date. Unpaid renewals do not extend access. Purchases explicitly replace complimentary legacy/testing licenses; lifetime grants remain independent.

Returning from Checkout does not grant access. Stripe events are signed and checked against canonical Stripe objects, known offers, recorded customers and server-owned checkout/invitation mappings. Auth is verified with `getUser`; admin permissions are checked against the database, never editable metadata. Public clients cannot select or write any billing tables or execute the service-only transaction functions. Raw card details and the Stripe key never reach the app.

## Administrator controls

Account → **Super Admin** → **Global billing settings** contains the early-adopter limits and recurring prices for all accounts. These controls do not select or target an individual account.

For personal membership changes: Account → **Super Admin** → search for the intended person → the **credit-card icon** beside that account opens **Membership administration**. Clicking the account itself still opens the separate read-only support view.

- Grant Professional or Top Tier lifetime access with a reason; revoke a particular grant with a reason. Grants are audited. Future recurring renewals are stopped, without issuing automatic refunds. Pending purchases must first be closed, and private purchase links are disabled during manual grants.
- Grant/remove a price lock for an existing continuous subscription or its next initial subscription. A card update preserves a lock. Changing tier or billing interval removes it after explicit customer confirmation. Ending a subscription ends its lock. A consumed manual grant is not automatically reused on a later subscription.
- Configure the **first-customer count per tier**, or 0 to disable. All three start disabled because counts have not been chosen. Checkout reserves an eligible slot for up to Stripe's checkout lifetime, under a serialized quota lock. Only confirmed-expired/failed checkouts release reservations; paid awards count permanently and cannot be claimed twice by the same owner/tier. Pending reservations therefore count toward a tier's quota.
- Create a **private, single-purchase lifetime Payment Link** for the selected Professional/Top Tier account by entering an explicit one-time USD amount. No lifetime prices or purchase links are preconfigured. The invitation, not email or a buyer-editable URL parameter, determines who receives access. Someone may pay on behalf of the intended account; the link cannot grant a different account access. Disable links to stop new checkouts; a checkout already begun can still complete.
- Publish a new recurring price after confirming renewal notices have been handled. Unlocked subscribers on the matching tier/interval get a Stripe schedule preserving the existing paid period and applying the new price at renewal. Locked subscriptions and a customer's already scheduled plan choice are skipped. Inspect the reported results; retry the **same price** if any subscriptions could not be scheduled. Notice confirmation is an operator acknowledgment; this integration does not send price-change emails.

Lifetime fulfillment is independent of recurring subscriptions. Full lifetime refunds and payment disputes block/revoke that receipt's grant. Reversal and fulfillment share a database lock so event order cannot recreate refunded lifetime access. Partial refunds do not remove access. Dispute resolution requires administrator review for any reinstatement. Other independent grants remain effective. A lifetime purchase also stops future recurring renewals.

## Operations and verification

Supabase secrets: `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET`. The live key's account is checked before billing mutations. The webhook endpoint uses raw-body HMAC validation with a five-minute timestamp window; it does not rely on a Supabase JWT. Billing verifies each user internally. Neither endpoint is an anonymous billing API.

`breeder_billing_settings.checkout_enabled` is the purchase switch. On launch, new complimentary test-license grants are disabled; existing four legacy/testing licenses are preserved until an explicit paid purchase/lifetime grant replaces the relevant owner's access. No existing user is enrolled or charged automatically. Schema migrations and Stripe catalogue seeding are separate: copy the live price IDs into offer rows using the returned Stripe objects, never regenerate prices during database restore.

Webhooks include checkout completion/asynchronous outcomes/expiry, subscription creation/update/deletion, paid/failed invoices, full refunds and disputes. Event receipts are idempotent; state is refreshed from Stripe and serialized. Each owner's billing changes use a short lease. Stripe creates use stable idempotency keys. Interrupted checkouts can be resumed or closed; old unidentified sessions are reconciled against that customer's Stripe sessions before a reservation is released.

Deletion verifies a fresh email code, holds the same billing lease, expires open checkouts, disables private purchase links and cancels Breeder subscriptions before deleting the account. It rechecks Stripe to catch a checkout finishing concurrently. Failures leave the account available for retry, or the existing deletion job resumable. Other RingMaster applications' subscriptions are excluded. Receipt/audit rows remain with owner references cleared. Owner-level herd recovery preserves current billing and grants; it never restores an old price, membership or webhook state.

Tests: `supabase/tests/billing.sql` runs rollback-only against an isolated Breeder schema with both billing migrations. It checks quota reservations, unpaid/paid access, failed payments, lifetime isolation, revocation/reversal order, stale events, concurrent-operation exclusion, and client privilege denial. `billing/core_test.ts` tests HMAC validation, paid-invoice line matching and renewal schedules; `billing/handler_test.ts` tests real-handler Auth rejection, owner-ID forgery and admin authorization using mocked HTTP. Flutter tests cover both intervals, purchase consent, lifetime display and phone layout. Existing offline tests verify animal-limit enforcement remains intact.

Live validation created one uncompleted subscription Checkout Session, then expired it without payment. Signed/unsigned webhook checks and unauthenticated billing denial were verified. No real customer charge was made. A completed real-card purchase/refund cycle is deliberately not part of unattended validation.

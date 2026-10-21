# Optional registration feedback and referrals

New accounts created after this feature's database launch see three optional questions after their verified-email/profile setup: how they previously tracked their herd, who referred them, and which features they would like added. All questions can be left blank or skipped together. This version asks the feature question at signup; it does not send a 14-day reminder.

Account → Feedback & referrals lets members revisit their tracking answer and feature ideas, supply a referral if initially blank, copy their personal referral code, and see linked signup totals. Once a referral has been supplied it is preserved; support can review corrections. These answers belong to the signed-in person, regardless of a selected shared household.

Super Admin → Registration insights lists saved responses, matched referrers and linked signup totals, with pagination. Access is verified on the server and reads are audited. Members can access only their own answers and code/count; they cannot inspect the referred people's identities. Direct client table access is denied, including shared-family access.

`breeder_registration_feedback` stores answers with bounded lengths and an owner foreign key that cascades on account deletion. Its RPC delegates to an authenticated, private function with a fixed search path. It derives the owner from the verified identity, never request-supplied IDs. Exact referral code or current verified email matches resolve to an active account, excluding self-referrals. Free-text names remain self-reported for administrator review. Referral codes are random, unique and account-specific.

Counts are **active linked signups**, not qualified paying referrals or earned rewards. There are no automatic Stripe credits/free months, no six-referral threshold, and no promises of a reward in this release. A future rewards program needs qualification, fraud checks and redemption rules before enabling billing credits.

The optional first-run check times out after three seconds and fails open; a survey outage must not prevent access to existing herd records. Saves require an internet connection, retain typed answers on failure, and do not silently claim offline success. A failed skip still allows continuing, with answers available later in Account.

Validation: `supabase/tests/registration_feedback.sql` runs in a rolled-back transaction to check ownership, referral matching/counts, self-referral prevention, frozen attribution, length bounds, admin authorization, anonymous denial and no repeated signup prompt. `test/registration_feedback_test.dart` covers skip/save, existing-account bypass, outages, mobile scrolling and admin response display.

import { APP, refId, schedulePhases, StripeClient } from "../_shared/stripe.ts";
import { checked } from "../_shared/billing-state.ts";
import { noticeText, priceChangeRenewal } from "../_shared/price-notice.ts";
const row = async (db: any, table: string, column: string, value: any) =>
  checked<any>(
    await db.from(table).select("*").eq(column, value).maybeSingle(),
  );
export async function processPriceNotice(
  db: any,
  stripe: StripeClient,
  notice: any,
  send: (n: any) => Promise<string>,
  now = Date.now(),
) {
  const s = await row(
    db,
    "breeder_billing_subscriptions",
    "stripe_subscription",
    notice.stripe_subscription,
  );
  const campaign = await row(
    db,
    "breeder_price_changes",
    "id",
    notice.change_id,
  );
  const offer = await row(
    db,
    "breeder_billing_prices",
    "id",
    campaign.offer_id,
  );
  const old = await row(
    db,
    "breeder_billing_prices",
    "id",
    notice.old_offer_id,
  );
  const save = async (values: any) =>
    checked(
      await db.from("breeder_price_notices").update(values).eq("id", notice.id),
    );
  const grants = checked<any[]>(
    await db.from("breeder_membership_grants").select("id").eq(
      "owner_id",
      s?.owner_id,
    ).eq("active", true),
  );
  if (
    !s?.owner_id || s.status !== "active" || s.cancel_at_period_end ||
    s.price_locked || grants.length || campaign.state === "superseded" ||
    (s.offer_id !== notice.old_offer_id && s.offer_id !== offer.id) ||
    (s.pending_offer_id && s.pending_offer_id !== offer.id)
  ) {
    await save({
      state: "skipped",
      last_error: "Membership changed, protected, or no longer renewing.",
    });
    return;
  }
  if (s.offer_id === offer.id) {
    await save({ state: "complete" });
    return;
  }
  const live = await stripe.request(`subscriptions/${s.stripe_subscription}`);
  if (
    live.metadata?.application !== APP || live.metadata?.owner !== s.owner_id ||
    live.status !== "active" || live.cancel_at_period_end ||
    refId(live.items?.data?.[0]?.price) !== old.stripe_price
  ) {
    await save({
      state: "skipped",
      last_error: "Live subscription no longer eligible.",
    });
    return;
  }
  const account = await row(db, "users", "id", s.owner_id);
  if (
    !account?.is_active || !account.auth_user_id ||
    await row(db, "account_deletions", "user_id", account.auth_user_id)
  ) {
    await save({ state: "skipped", last_error: "Account unavailable." });
    return;
  }
  let schedule = live.schedule
    ? await stripe.request(`subscription_schedules/${refId(live.schedule)}`)
    : null;
  if (
    schedule && schedule.metadata?.application !== APP &&
    schedule.id !== s.schedule_id
  ) throw Error("Existing Stripe schedule requires review.");
  // Freeze recipient, text and renewal together; retries reuse exactly the same mail payload/key.
  if (!notice.effective_at) {
    const identity = await db.auth.admin.getUserById(account.auth_user_id);
    if (
      identity.error || !identity.data.user?.email_confirmed_at ||
      !identity.data.user.email
    ) throw Error("Verified billing email unavailable.");
    notice.recipient = identity.data.user.email;
    // Never promise a change at a renewal already in progress. Late catch-up notices get 30 days.
    const cutoff = Math.max(
      Date.parse(campaign.starts_at),
      now + 31 * 86400000,
    );
    notice.effective_at = new Date(
      priceChangeRenewal(live, new Date(cutoff).toISOString()) * 1000,
    ).toISOString();
    notice.message = noticeText(notice, old, offer);
    await save({
      recipient: notice.recipient,
      effective_at: notice.effective_at,
      message: notice.message,
    });
  }
  if (Date.parse(notice.effective_at) <= now + 60000) {
    await save({
      state: "review",
      last_error:
        "Announced renewal is too close or has passed. No late price change was scheduled.",
    });
    return;
  }
  if (!notice.email_accepted_at) {
    if (
      notice.last_attempt_at &&
      now - Date.parse(notice.last_attempt_at) > 23 * 3600000
    ) {
      await save({
        state: "review",
        last_error:
          "Email acceptance uncertain beyond safe retry window. Review before retrying.",
      });
      return;
    }
    await save({
      last_attempt_at: notice.last_attempt_at ?? new Date(now).toISOString(),
    });
    notice.provider_id = await send(notice);
    notice.email_accepted_at = new Date(now).toISOString();
    await save({
      provider_id: notice.provider_id,
      email_accepted_at: notice.email_accepted_at,
    });
  }
  if (!schedule) {
    schedule = await stripe.request("subscription_schedules", "POST", {
      from_subscription: live.id,
    }, `schedule:${live.id}`);
    checked(
      await db.from("breeder_billing_subscriptions").update({
        schedule_id: schedule.id,
      }).eq("stripe_subscription", live.id),
    );
  }
  // Stripe keeps billing the original price on its regular cycle until this regular renewal.
  const phases = schedulePhases(
    live,
    schedule,
    offer.stripe_price,
    offer.interval,
  );
  const end = Date.parse(notice.effective_at) / 1000;
  phases.phases[0].end_date = end;
  phases.phases[1].start_date = end;
  await stripe.request(
    `subscription_schedules/${schedule.id}`,
    "POST",
    phases,
    `notice-change:${notice.id}`,
  );
  checked(
    await db.from("breeder_billing_subscriptions").update({
      schedule_id: schedule.id,
      pending_offer_id: offer.id,
      pending_effective_at: notice.effective_at,
    }).eq("stripe_subscription", live.id),
  );
  await save({
    state: "complete",
    scheduled_at: new Date(now).toISOString(),
    last_error: null,
  });
}

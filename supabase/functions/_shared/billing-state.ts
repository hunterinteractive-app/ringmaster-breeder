import { APP, iso, paidPeriod, refId, StripeClient } from "./stripe.ts";
export function checked<T = any>(result: any): T {
  if (result.error) {
    throw Error("Billing records could not be updated. Please retry.");
  }
  return result.data;
}
export async function transaction(db: any, action: string, data: any) {
  return checked(
    await db.rpc("breeder_billing_transaction", {
      p_action: action,
      p_data: data,
    }),
  );
}
export async function syncSubscription(
  db: any,
  stripe: StripeClient,
  id: string,
) {
  const observed = new Date().toISOString();
  const s = await stripe.request(`subscriptions/${id}`, "GET", {
    "expand": ["latest_invoice"],
  });
  if (s.metadata?.application !== APP || !s.livemode) return;
  const customer = checked<any>(
    await db.from("breeder_billing_customers").select("*").eq(
      "stripe_customer",
      refId(s.customer),
    ).maybeSingle(),
  );
  if (!customer?.owner_id || customer.owner_id !== s.metadata.owner) return;
  if (s.items.data.length !== 1 || s.items.data[0].quantity !== 1) {
    throw Error("Unexpected subscription configuration");
  }
  const result = await transaction(db, "subscription", {
    id: s.id,
    owner: customer.owner_id,
    checkout: s.metadata.checkout,
    price: refId(s.items.data[0].price),
    status: s.status,
    paid_through: paidPeriod(s),
    period_end: iso(s.items.data[0].current_period_end ?? s.current_period_end),
    cancel: s.cancel_at_period_end,
    observed_at: observed,
  });
  if (["canceled", "incomplete_expired"].includes(s.status)) {
    checked(
      await db.from("breeder_billing_checkouts").update({ state: "expired" })
        .eq("id", s.metadata.checkout).in("state", ["creating", "open"]),
    );
  }
  return result;
}
export async function cancelOwnerSubscriptions(
  db: any,
  stripe: StripeClient,
  owner: string,
  immediate: boolean,
) {
  const customer = checked<any>(
    await db.from("breeder_billing_customers").select("*").eq("owner_id", owner)
      .maybeSingle(),
  );
  if (!customer?.stripe_customer) return;
  // Query Stripe too: a just-completed checkout may precede its webhook.
  const all = await stripe.request("subscriptions", "GET", {
    customer: customer.stripe_customer,
    status: "all",
    limit: 100,
  });
  if (all.has_more) {
    throw Error("Contact support to review this billing account.");
  }
  for (const s of all.data) {
    if (
      s.metadata?.application !== APP || s.metadata.owner !== owner ||
      ["canceled", "incomplete_expired"].includes(s.status)
    ) continue;
    if (s.schedule) {
      const schedule = await stripe.request(
        `subscription_schedules/${refId(s.schedule)}`,
      );
      if (schedule.metadata?.application !== APP) {
        throw Error("Contact support to review this subscription schedule.");
      }
      await stripe.request(
        `subscription_schedules/${schedule.id}/release`,
        "POST",
        {},
        `release:${schedule.id}`,
      );
    }
    await stripe.request(
      `subscriptions/${s.id}`,
      immediate ? "DELETE" : "POST",
      immediate
        ? { prorate: false, invoice_now: false }
        : { cancel_at_period_end: true },
      `cancel:${s.id}:${immediate}`,
    );
    await syncSubscription(db, stripe, s.id);
  }
}

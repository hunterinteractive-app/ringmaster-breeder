import { APP, iso, refId, StripeClient } from "./stripe.ts";
import { checked } from "./billing-state.ts";
type Reader = Pick<StripeClient, "request" | "verifyAccount">;
type Page = { kind?: "transactions" | "invoices"; after?: string };
export function transactionSummary(charge: any, source = "Membership payment") {
  return {
    id: charge.id,
    created_at: iso(charge.created),
    amount_cents: charge.amount,
    refunded_cents: charge.amount_refunded ?? 0,
    currency: charge.currency,
    status: charge.disputed
      ? "disputed"
      : charge.amount_refunded > 0
      ? charge.amount_refunded >= charge.amount
        ? "refunded"
        : "partially_refunded"
      : charge.status === "succeeded" && charge.captured === false
      ? "authorized"
      : charge.status,
    description: source,
    receipt_url: charge.receipt_url ?? null,
    failure_message: charge.failure_message ?? null,
  };
}
export async function readAccountBilling(
  database: any,
  owner: string,
  page: Page = {},
  makeStripe: () => Reader = () => new StripeClient(),
) {
  if (
    page.kind && page.after &&
    !(page.kind === "invoices" ? /^in_[A-Za-z0-9]+$/ : /^(ch|py)_[A-Za-z0-9]+$/)
      .test(page.after)
  ) {
    throw Error("Invalid history page. Refresh this account and try again.");
  }
  const results = await Promise.all([
    database.from("breeder_billing_customers").select("*").eq("owner_id", owner)
      .maybeSingle(),
    database.from("breeder_billing_subscriptions").select("*").eq(
      "owner_id",
      owner,
    ),
    database.from("breeder_membership_grants").select("*").eq(
      "owner_id",
      owner,
    ),
    database.from("breeder_lifetime_invitations").select(
      "id,paid_session,offer_id",
    ).eq("owner_id", owner),
    database.from("breeder_billing_prices").select("*"),
    database.from("user_licenses").select(
      "tier_code,status,source,started_at,expires_at",
    ).eq("user_id", owner),
    database.from("license_tiers").select(
      "code,name,max_active_animals,max_rings",
    ),
  ]);
  const [customer, records, grants, invitations, prices, licenses, tiers] =
    results.map(checked) as any[];
  const byTier = new Map(tiers.map((t: any) => [t.code, t]));
  const byPrice = new Map(prices.map((p: any) => [p.stripe_price, p]));
  const byOffer = new Map(prices.map((p: any) => [p.id, p]));
  function plan(price: any, saved?: any) {
    const id = refId(price);
    const offer: any = (id ? byPrice.get(id) : saved) ?? null;
    const expanded = typeof price === "object" ? price : null;
    return {
      tier_code: offer?.tier_code ?? null,
      name: (byTier.get(offer?.tier_code) as any)?.name ??
        "Unrecognized Stripe plan",
      amount_cents: expanded?.unit_amount ?? offer?.amount_cents ?? null,
      currency: expanded?.currency ?? offer?.currency ?? "usd",
      interval: expanded?.recurring?.interval ?? offer?.interval ?? null,
      interval_count: expanded?.recurring?.interval_count ?? 1,
    };
  }
  function subscription(saved: any, live?: any) {
    const future = typeof live?.schedule === "object"
      ? live.schedule?.phases?.filter((p: any) =>
        p.start_date > Date.now() / 1000
      ).sort((a: any, b: any) => a.start_date - b.start_date)[0]
      : null;
    const pending: any = !live && saved.pending_offer_id
      ? byOffer.get(saved.pending_offer_id)
      : null;
    return {
      id: saved.stripe_subscription,
      status: live?.status ?? saved.status,
      plan: plan(
        live?.items?.data?.[0]?.price ?? null,
        byOffer.get(saved.offer_id),
      ),
      period_end: live
        ? iso(
          live.items?.data?.[0]?.current_period_end ?? live.current_period_end,
        )
        : saved.period_end,
      paid_through: saved.paid_through,
      cancel_at_period_end: live?.cancel_at_period_end ??
        saved.cancel_at_period_end,
      price_locked: ["canceled", "incomplete_expired"].includes(
          live?.status ?? saved.status,
        )
        ? false
        : saved.price_locked,
      scheduled_plan:
        (live?.cancel_at_period_end ?? saved.cancel_at_period_end) ||
          ["canceled", "incomplete_expired"].includes(
            live?.status ?? saved.status,
          )
          ? null
          : future
          ? {
            ...plan(future.items?.[0]?.price),
            effective_at: iso(future.start_date),
          }
          : pending
          ? { ...plan(null, pending), effective_at: saved.period_end }
          : null,
      verified_live: !!live,
      saved_at: saved.observed_at,
    };
  }
  const active = licenses.filter((l: any) =>
    l.status === "active" &&
    (!l.started_at || Date.parse(l.started_at) <= Date.now()) &&
    (!l.expires_at || Date.parse(l.expires_at) > Date.now())
  )
    .sort((a: any, b: any) =>
      ((byTier.get(b.tier_code) as any)?.max_active_animals ?? 0) -
        ((byTier.get(a.tier_code) as any)?.max_active_animals ?? 0) ||
      ((byTier.get(b.tier_code) as any)?.max_rings ?? 0) -
        ((byTier.get(a.tier_code) as any)?.max_rings ?? 0)
    );
  const current = active[0];
  const relevant = [...records].sort((a: any, b: any) =>
    Number(["canceled", "incomplete_expired"].includes(a.status)) -
      Number(["canceled", "incomplete_expired"].includes(b.status)) ||
    (Date.parse(b.period_end) || 0) - (Date.parse(a.period_end) || 0)
  ).slice(0, 10);
  const output: any = {
    access: current
      ? {
        ...current,
        name: (byTier.get(current.tier_code) as any)?.name ?? current.tier_code,
      }
      : null,
    subscriptions: relevant.map((s: any) => subscription(s)),
    membership_activity: grants.map((g: any) => ({
      id: g.id,
      tier_code: g.tier_code,
      source: g.source,
      active: g.active,
      note: g.note,
      created_at: g.created_at,
      revoked_at: g.revoked_at,
    })),
    transactions: [],
    invoices: [],
    transactions_next: null,
    invoices_next: null,
    transactions_available: true,
    invoices_available: true,
    warnings: [],
    checked_at: new Date().toISOString(),
  };
  const lifetimeGrants = grants.filter((g: any) => g.stripe_payment_intent);
  const lifetimeInvitations = invitations.filter((i: any) => i.paid_session);
  if (
    !customer?.stripe_customer && !records.length && !lifetimeGrants.length &&
    !lifetimeInvitations.length
  ) return output;
  let stripe: Reader;
  try {
    stripe = makeStripe();
    await stripe.verifyAccount(false);
    if (customer?.stripe_customer) {
      const remote = await stripe.request(
        `customers/${customer.stripe_customer}`,
      );
      if (
        remote.deleted || remote.metadata?.application !== APP ||
        remote.metadata?.owner !== owner ||
        remote.id !== customer.stripe_customer
      ) throw Error("Customer mismatch");
    }
  } catch {
    output.transactions_available = false;
    output.invoices_available = false;
    output.warnings.push(
      "Live Stripe details are unavailable. Showing saved membership information; refresh to retry.",
    );
    return output;
  }
  const tasks: Promise<unknown>[] = [];
  if (!page.kind) {
    for (const saved of relevant) {
      tasks.push((async () => {
        try {
          const live = await stripe.request(
            `subscriptions/${saved.stripe_subscription}`,
            "GET",
            { expand: ["schedule"] },
          );
          if (
            live.metadata?.application !== APP ||
            live.metadata?.owner !== owner ||
            refId(live.customer) !== customer?.stripe_customer || !live.livemode
          ) throw Error("Subscription mismatch");
          const at = output.subscriptions.findIndex((s: any) =>
            s.id === saved.stripe_subscription
          );
          output.subscriptions[at] = subscription(saved, live);
        } catch {
          output.warnings.push(
            "Some renewal details could not be refreshed. Saved details are marked below.",
          );
        }
      })());
    }
  }
  if (customer?.stripe_customer && page.kind !== "invoices") {
    tasks.push((async () => {
      try {
        const list = await stripe.request("charges", "GET", {
          customer: customer.stripe_customer,
          limit: 20,
          ...(page.after ? { starting_after: page.after } : {}),
        });
        const owned = list.data.filter((c: any) =>
          refId(c.customer) === customer.stripe_customer && c.livemode
        );
        output.transactions.push(
          ...owned.map((c: any) => transactionSummary(c)),
        );
        output.transactions_next = list.has_more
          ? owned.at(-1)?.id ?? null
          : null;
      } catch {
        output.transactions_available = false;
        output.warnings.push(
          "Transaction history could not be loaded. Refresh to retry.",
        );
      }
    })());
  }
  if (customer?.stripe_customer && page.kind !== "transactions") {
    tasks.push((async () => {
      try {
        const list = await stripe.request("invoices", "GET", {
          customer: customer.stripe_customer,
          limit: 20,
          ...(page.after ? { starting_after: page.after } : {}),
        });
        output.invoices = list.data.filter((i: any) =>
          refId(i.customer) === customer.stripe_customer && i.livemode
        ).map((i: any) => ({
          id: i.id,
          number: i.number,
          created_at: iso(i.created),
          status: i.status,
          currency: i.currency,
          total_cents: i.total,
          paid_cents: i.amount_paid,
          remaining_cents: i.amount_remaining,
          attempt_count: i.attempt_count,
          next_attempt_at: iso(i.next_payment_attempt),
          invoice_url: i.hosted_invoice_url ?? null,
          pdf_url: i.invoice_pdf ?? null,
        }));
        output.invoices_next = list.has_more
          ? output.invoices.at(-1)?.id ?? null
          : null;
      } catch {
        output.invoices_available = false;
        output.warnings.push("Invoices could not be loaded. Refresh to retry.");
      }
    })());
  }
  // Private lifetime purchases can use a different Stripe customer. Follow only server-owned receipts.
  if (page.kind !== "invoices") {
    tasks.push((async () => {
      const receipts = new Map<
        string,
        { invitation?: string; payment?: string; tier?: string }
      >();
      for (const g of lifetimeGrants) {
        receipts.set(g.stripe_payment_intent, {
          payment: g.stripe_payment_intent,
          tier: g.tier_code,
        });
      }
      for (const i of lifetimeInvitations) {
        if (
          grants.some((g: any) =>
            g.stripe_session === i.paid_session && g.stripe_payment_intent
          )
        ) continue;
        receipts.set(i.paid_session, {
          invitation: i.id,
          tier: (byOffer.get(i.offer_id) as any)?.tier_code,
        });
      }
      // Memberships are deliberately limited offers; bound concurrent Stripe requests.
      const entries = [...receipts.entries()];
      for (let start = 0; start < entries.length; start += 4) {
        await Promise.all(
          entries.slice(start, start + 4).map(async ([id, receipt]) => {
            try {
              let payment = receipt.payment;
              if (!payment) {
                const session = await stripe.request(`checkout/sessions/${id}`);
                if (
                  session.metadata?.application !== APP ||
                  session.metadata?.invitation !== receipt.invitation ||
                  !session.livemode
                ) throw Error("Receipt mismatch");
                payment = refId(session.payment_intent) ?? undefined;
              }
              if (!payment) return;
              const intent = await stripe.request(`payment_intents/${payment}`);
              if (
                !intent.livemode || intent.metadata?.application !== APP ||
                (receipt.invitation &&
                  intent.metadata?.invitation !== receipt.invitation)
              ) throw Error("Payment mismatch");
              const charges = await stripe.request("charges", "GET", {
                payment_intent: intent.id,
                limit: 100,
              });
              for (const charge of charges.data) {
                if (
                  refId(charge.payment_intent) !== intent.id || !charge.livemode
                ) continue;
                output.transactions.push(
                  transactionSummary(
                    charge,
                    `${
                      (byTier.get(receipt.tier) as any)?.name ?? "Breeder"
                    } lifetime purchase`,
                  ),
                );
              }
              if (charges.has_more) {
                output.warnings.push(
                  "Additional lifetime payment attempts are available in Stripe beyond the first 100 for that receipt.",
                );
              }
            } catch {
              output.warnings.push(
                "Some recorded lifetime receipts could not be loaded. Refresh to retry.",
              );
            }
          }),
        );
      }
    })());
  }
  await Promise.all(tasks);
  output.transactions = [
    ...new Map(output.transactions.map((t: any) => [t.id, t])).values(),
  ].sort((a: any, b: any) =>
    Date.parse(b.created_at) - Date.parse(a.created_at)
  );
  output.warnings = [...new Set(output.warnings)];
  return output;
}

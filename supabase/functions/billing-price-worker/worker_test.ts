import { noticeText, priceChangeRenewal } from "../_shared/price-notice.ts";
import { processPriceNotice } from "./worker.ts";
const assert = (v: unknown, m = "assertion failed") => {
  if (!v) throw Error(m);
};
const sec = (s: string) => Date.parse(s) / 1000;
const sub = (end: string, interval = "month", anchor = end) => ({
  id: "sub_1",
  status: "active",
  metadata: { application: "ringmaster_breeder", owner: "owner" },
  billing_cycle_anchor: sec(anchor),
  items: {
    data: [{
      quantity: 1,
      current_period_end: sec(end),
      price: { id: "price_old", recurring: { interval, interval_count: 1 } },
    }],
  },
});
Deno.test("future monthly changes use original day-31 anchor across February", () => {
  const s = sub("2027-01-31T15:00:00Z");
  assert(
    priceChangeRenewal(s, "2027-03-01T00:00:00Z") ===
      sec("2027-03-31T15:00:00Z"),
  );
  assert(
    priceChangeRenewal(s, "2027-02-01T00:00:00Z") ===
      sec("2027-02-28T15:00:00Z"),
  );
  assert(
    priceChangeRenewal(s, "2027-01-31T15:00:00Z") ===
      sec("2027-01-31T15:00:00Z"),
  );
});
Deno.test("annual change never interrupts a paid term and handles leap-day renewals", () => {
  assert(
    priceChangeRenewal(
      sub("2027-03-15T15:00:00Z", "year"),
      "2026-12-01T00:00:00Z",
    ) === sec("2027-03-15T15:00:00Z"),
  );
  assert(
    priceChangeRenewal(
      sub("2027-03-15T15:00:00Z", "year"),
      "2027-04-01T00:00:00Z",
    ) === sec("2028-03-15T15:00:00Z"),
  );
  assert(
    priceChangeRenewal(
      sub("2027-02-28T15:00:00Z", "year", "2024-02-29T15:00:00Z"),
      "2028-01-01T00:00:00Z",
    ) === sec("2028-02-29T15:00:00Z"),
  );
});
function scenario(options: any = {}) {
  const now = Date.parse("2027-01-01T00:00:00Z");
  const tables: any = {
    breeder_billing_subscriptions: {
      stripe_subscription: "sub_1",
      owner_id: "owner",
      status: "active",
      offer_id: "old",
      price_locked: !!options.locked,
      pending_offer_id: options.pending,
    },
    breeder_price_changes: {
      id: "change",
      offer_id: "new",
      starts_at: "2027-03-01T00:00:00Z",
      state: "scheduled",
    },
    breeder_billing_prices: [{
      id: "old",
      stripe_price: "price_old",
      amount_cents: 4900,
      tier_code: "HOBBY",
      interval: "year",
    }, {
      id: "new",
      stripe_price: "price_new",
      amount_cents: 5900,
      tier_code: "HOBBY",
      interval: "year",
    }],
    users: { is_active: true, auth_user_id: "auth" },
    account_deletions: null,
    breeder_membership_grants: options.lifetime ? [{ id: "grant" }] : [],
  };
  const n: any = {
    id: "notice",
    change_id: "change",
    stripe_subscription: "sub_1",
    old_offer_id: "old",
  };
  const events: string[] = [];
  const updates: any[] = [];
  const db: any = {
    auth: {
      admin: {
        getUserById: async () => ({
          data: {
            user: {
              email: "verified@example.test",
              email_confirmed_at: "2026-01-01",
            },
          },
        }),
      },
    },
    from: (name: string) => {
      let filter: any;
      let values: any;
      const q: any = {
        select: () => q,
        eq: (k: string, v: any) => {
          if (k === "id") filter = v;
          return q;
        },
        update: (v: any) => {
          values = v;
          return q;
        },
        maybeSingle: async () => ({
          data: Array.isArray(tables[name])
            ? tables[name].find((v: any) => v.id === filter)
            : tables[name],
        }),
        then: (resolve: any) => {
          if (values) {
            updates.push({ name, values });
            if (name === "breeder_price_notices") Object.assign(n, values);
            resolve({ data: null });
          } else resolve({ data: tables[name] });
        },
      };
      return q;
    },
  };
  const live = sub("2027-03-15T15:00:00Z", "year");
  const stripe: any = {
    request: async (path: string, method = "GET", body?: any) => {
      events.push(method + ":" + path);
      if (path === "subscriptions/sub_1") return live;
      if (path === "subscription_schedules") {
        return {
          id: "sched",
          current_phase: { start_date: sec("2026-03-15T15:00:00Z") },
        };
      }
      if (method === "POST") {
        assert(n.email_accepted_at, "Stripe update before notice accepted");
        assert(
          body.phases[1].start_date === sec(n.effective_at),
          "email date differs from Stripe",
        );
        return {};
      }
    },
  };
  const send = async (mail: any) => {
    events.push("email");
    assert(mail.recipient === "verified@example.test", "unverified email");
    if (options.emailFails) throw Error("mail failed");
    return "provider";
  };
  return { db, stripe, n, send, now, events, updates };
}
Deno.test("notice is accepted before Stripe scheduling, with exact date and old/new amounts", async () => {
  const x = scenario();
  await processPriceNotice(x.db, x.stripe, x.n, x.send, x.now);
  assert(x.n.state === "complete");
  assert(
    x.n.message.includes("$49.00 USD/year") &&
      x.n.message.includes("$59.00 USD/year") &&
      x.n.message.includes("March 15, 2027"),
  );
  assert(
    x.events.indexOf("email") < x.events.indexOf("POST:subscription_schedules"),
  );
});
Deno.test("email failure prevents any Stripe write", async () => {
  const x = scenario({ emailFails: true });
  let failed = false;
  try {
    await processPriceNotice(x.db, x.stripe, x.n, x.send, x.now);
  } catch {
    failed = true;
  }
  assert(failed);
  assert(!x.events.some((v) => v.startsWith("POST:")));
});
Deno.test("price locks, lifetime access and customer-scheduled plan changes receive no notice or Stripe changes", async () => {
  for (
    const options of [{ locked: true }, { lifetime: true }, {
      pending: "different-plan",
    }]
  ) {
    const x = scenario(options);
    await processPriceNotice(x.db, x.stripe, x.n, x.send, x.now);
    assert(x.n.state === "skipped");
    assert(x.events.length === 0);
  }
});
Deno.test("unconfirmed email beyond idempotency window stops for review without resending", async () => {
  const x = scenario();
  x.n.effective_at = "2027-03-15T15:00:00Z";
  x.n.last_attempt_at = "2026-12-30T00:00:00Z";
  await processPriceNotice(x.db, x.stripe, x.n, x.send, x.now);
  assert(x.n.state === "review");
  assert(!x.events.includes("email"));
  assert(!x.events.some((v) => v.startsWith("POST:")));
});
Deno.test("email includes cancellation route and explicit Eastern time", () => {
  const text = noticeText({ effective_at: "2027-03-15T15:00:00Z" }, {
    amount_cents: 500,
    interval: "month",
  }, { tier_code: "PRO", amount_cents: 1000, interval: "month" });
  assert(
    text.includes("Eastern Time") && text.includes("cancel future renewals") &&
      text.includes("Professional Breeder"),
  );
});

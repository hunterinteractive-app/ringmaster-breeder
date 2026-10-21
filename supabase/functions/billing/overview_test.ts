import {
  readAccountBilling,
  transactionSummary,
} from "../_shared/billing-overview.ts";
import { APP } from "../_shared/stripe.ts";
function assert(v: unknown, label: string) {
  if (!v) throw Error(label);
}
const future = Math.floor(Date.now() / 1000) + 86400 * 100;
const tiers = [{
  code: "HOBBY",
  name: "Hobby Breeder",
  max_active_animals: 50,
  max_rings: 1,
}, {
  code: "PRO",
  name: "Professional Breeder",
  max_active_animals: 250,
  max_rings: 1,
}];
const prices = [{
  id: "offer1",
  stripe_price: "price1",
  tier_code: "HOBBY",
  amount_cents: 4900,
  currency: "usd",
  interval: "year",
}, {
  id: "offer2",
  stripe_price: "price2",
  tier_code: "PRO",
  amount_cents: 9900,
  currency: "usd",
  interval: "year",
}];
function database(extra: Record<string, any[]> = {}) {
  const rows: Record<string, any[]> = {
    breeder_billing_customers: [],
    breeder_billing_subscriptions: [],
    breeder_membership_grants: [],
    breeder_lifetime_invitations: [],
    breeder_billing_prices: prices,
    user_licenses: [],
    license_tiers: tiers,
    ...extra,
  };
  const reads: any[] = [];
  return {
    reads,
    from(table: string) {
      const filters: [string, unknown][] = [];
      const query: any = {
        select() {
          return query;
        },
        eq(key: string, value: unknown) {
          filters.push([key, value]);
          reads.push({ table, key, value });
          return query;
        },
        maybeSingle() {
          return Promise.resolve({
            data: (rows[table] ?? []).find((r) =>
              filters.every(([k, v]) =>
                r[k] === v
              )
            ) ?? null,
          });
        },
        then(resolve: any, reject: any) {
          return Promise.resolve({
            data: (rows[table] ?? []).filter((r) =>
              filters.every(([k, v]) => r[k] === v)
            ),
          }).then(resolve, reject);
        },
      };
      return query;
    },
  };
}
const customer = { owner_id: "owner1", stripe_customer: "cus_owner1" };
const subscription = {
  owner_id: "owner1",
  stripe_subscription: "sub_owner1",
  offer_id: "offer1",
  status: "active",
  period_end: new Date(future * 1000).toISOString(),
  paid_through: new Date(future * 1000).toISOString(),
  cancel_at_period_end: false,
  price_locked: false,
};
function reader(overrides: Record<string, any> = {}) {
  const requests: any[] = [];
  const stripe = {
    verifyAccount: async (requirePayments?: boolean) => {
      assert(requirePayments === false, "history required charge capability");
    },
    request: async (path: string, method = "GET", params: any = {}) => {
      requests.push({ path, method, params });
      assert(method === "GET", "history mutated Stripe");
      if (path === "customers/cus_owner1") {
        return {
          id: "cus_owner1",
          metadata: { application: APP, owner: "owner1" },
        };
      }
      if (path === "subscriptions/sub_owner1") {
        return {
          id: "sub_owner1",
          livemode: true,
          customer: "cus_owner1",
          metadata: { application: APP, owner: "owner1" },
          status: "active",
          cancel_at_period_end: false,
          items: {
            data: [{
              price: {
                id: "price1",
                unit_amount: 4900,
                currency: "usd",
                recurring: { interval: "year" },
              },
              current_period_end: future,
            }],
          },
          schedule: {
            phases: [{
              start_date: future - 31536000,
              items: [{ price: "price1" }],
            }, { start_date: future, items: [{ price: "price2" }] }],
          },
        };
      }
      if (path === "charges") {
        return {
          data: [{
            id: "ch_valid",
            customer: "cus_owner1",
            livemode: true,
            amount: 4900,
            amount_refunded: 2000,
            currency: "usd",
            status: "succeeded",
            created: future - 86400,
            receipt_url: "https://pay.stripe.com/receipt/example",
          }, {
            id: "ch_other",
            customer: "cus_other",
            livemode: true,
            amount: 999999,
            currency: "usd",
            status: "succeeded",
            created: future,
          }],
          has_more: true,
        };
      }
      if (path === "invoices") {
        return {
          data: [{
            id: "in_valid",
            customer: "cus_owner1",
            livemode: true,
            total: 4900,
            amount_paid: 4900,
            amount_remaining: 0,
            status: "paid",
            created: future - 86400,
            currency: "usd",
            number: "RMB-1",
          }],
          has_more: false,
        };
      }
      throw Error("Unexpected read " + path);
    },
    ...overrides,
  };
  return { stripe, requests };
}
Deno.test("legacy and manual lifetime access are not fabricated payment transactions", async () => {
  const db = database({
    user_licenses: [{
      user_id: "owner1",
      tier_code: "PRO",
      status: "active",
      source: "manual_lifetime",
    }],
    breeder_membership_grants: [{
      id: "gift",
      owner_id: "owner1",
      tier_code: "PRO",
      source: "manual_lifetime",
      active: true,
      created_at: "2026-01-01",
    }],
  });
  const result = await readAccountBilling(db, "owner1", {}, () => {
    throw Error("No Stripe history should be queried");
  });
  assert(result.access.source === "manual_lifetime", "lifetime access missing");
  assert(result.transactions.length === 0, "manual grant invented a charge");
  assert(result.membership_activity.length === 1, "grant history missing");
});
Deno.test("account history is customer-scoped, includes refunds, and shows the actual next renewal plan", async () => {
  const db = database({
    breeder_billing_customers: [customer, {
      owner_id: "other",
      stripe_customer: "cus_other",
    }],
    breeder_billing_subscriptions: [subscription],
  });
  const mock = reader();
  const result = await readAccountBilling(db, "owner1", {}, () => mock.stripe);
  assert(
    result.transactions.length === 1 &&
      result.transactions[0].id === "ch_valid",
    "foreign payment leaked",
  );
  assert(
    result.transactions[0].status === "partially_refunded",
    "partial refund missing",
  );
  assert(
    result.subscriptions[0].scheduled_plan.name === "Professional Breeder",
    "scheduled tier missing",
  );
  assert(
    result.subscriptions[0].scheduled_plan.amount_cents === 9900,
    "renewal amount wrong",
  );
  assert(
    result.invoices[0].paid_cents === 4900,
    "invoice actual total missing",
  );
  assert(
    mock.requests.filter((r) => r.path === "charges" || r.path === "invoices")
      .every((r) => r.params.customer === "cus_owner1"),
    "unscoped Stripe history",
  );
});
Deno.test("unverified Stripe customer mapping cannot reveal payment history", async () => {
  const db = database({
    breeder_billing_customers: [customer],
    breeder_billing_subscriptions: [subscription],
  });
  const mock = reader({
    request: async () => ({
      id: "cus_owner1",
      metadata: { application: "other_app", owner: "other" },
    }),
  });
  const result = await readAccountBilling(db, "owner1", {}, () => mock.stripe);
  assert(result.transactions_available === false, "wrong customer accepted");
  assert(result.transactions.length === 0, "payments exposed");
  assert(result.warnings.length > 0, "unavailable history reported as empty");
  assert(
    !result.subscriptions[0].verified_live,
    "saved plan presented as live",
  );
});
Deno.test("history pages retain the owner filter and use Stripe cursors", async () => {
  const db = database({ breeder_billing_customers: [customer] });
  const mock = reader();
  await readAccountBilling(db, "owner1", {
    kind: "transactions",
    after: "ch_older",
  }, () => mock.stripe);
  assert(
    mock.requests.find((r) => r.path === "charges").params.starting_after ===
      "ch_older",
    "cursor lost",
  );
  assert(
    !mock.requests.some((r) => r.path === "invoices"),
    "wrong history page queried",
  );
  let rejected = false;
  try {
    await readAccountBilling(db, "owner1", {
      kind: "transactions",
      after: "../../customers/other",
    }, () => mock.stripe);
  } catch {
    rejected = true;
  }
  assert(rejected, "invalid cursor accepted");
});
Deno.test("recorded lifetime purchase receipts can belong to a separate Stripe customer", async () => {
  const db = database({
    breeder_membership_grants: [{
      id: "life",
      owner_id: "owner1",
      tier_code: "PRO",
      source: "stripe_lifetime",
      stripe_payment_intent: "pi_life",
      active: true,
    }],
  });
  const mock = reader({
    request: async (path: string, method = "GET", params: any = {}) => {
      assert(method === "GET", "lifetime history mutated payments");
      if (path === "payment_intents/pi_life") {
        return {
          id: "pi_life",
          livemode: true,
          metadata: { application: APP },
        };
      }
      assert(
        path === "charges" && params.payment_intent === "pi_life",
        "unrelated payment queried",
      );
      return {
        data: [{
          id: "ch_life",
          payment_intent: "pi_life",
          livemode: true,
          amount: 100000,
          amount_refunded: 100000,
          currency: "usd",
          created: future,
          status: "succeeded",
        }, {
          id: "ch_attempt",
          payment_intent: "pi_life",
          livemode: true,
          amount: 100000,
          currency: "usd",
          created: future - 100,
          status: "failed",
        }],
        has_more: false,
      };
    },
  });
  const result = await readAccountBilling(db, "owner1", {}, () => mock.stripe);
  assert(
    result.transactions[0].status === "refunded",
    "lifetime refund missing",
  );
  assert(
    result.transactions[0].description.includes("lifetime"),
    "lifetime receipt mislabeled",
  );
});
Deno.test("transaction statuses distinguish authorization, payment failure, full refunds and disputes", () => {
  assert(
    transactionSummary({ status: "succeeded", captured: false }).status ===
      "authorized",
    "uncaptured authorization shown as paid",
  );
  assert(
    transactionSummary({ status: "failed" }).status === "failed",
    "failed payment hidden",
  );
  assert(
    transactionSummary({
      amount: 100,
      amount_refunded: 100,
      status: "succeeded",
    }).status === "refunded",
    "refund hidden",
  );
  assert(
    transactionSummary({ status: "succeeded", disputed: true }).status ===
      "disputed",
    "dispute hidden",
  );
});

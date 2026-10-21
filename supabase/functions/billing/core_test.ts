import {
  encodeForm,
  paidPeriod,
  schedulePhases,
  StripeClient,
  verifySignature,
} from "../_shared/stripe.ts";
function assert(value: unknown, label = "assertion failed") {
  if (!value) throw Error(label);
}
async function signed(raw: string, t: number, secret: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return Array.from(
    new Uint8Array(
      await crypto.subtle.sign(
        "HMAC",
        key,
        new TextEncoder().encode(`${t}.${raw}`),
      ),
    ),
  ).map((v) => v.toString(16).padStart(2, "0")).join("");
}
Deno.test("webhook verifies raw payload and rejects tampering, stale and future signatures", async () => {
  const raw = '{"id":"evt_example","livemode":true}',
    t = 2000000000,
    secret = "whsec_test";
  const sig = await signed(raw, t, secret);
  assert(await verifySignature(raw, `t=${t},v1=${sig}`, secret, t));
  assert(!await verifySignature(raw + " ", `t=${t},v1=${sig}`, secret, t));
  assert(!await verifySignature(raw, `t=${t},v1=${sig}`, secret, t + 301));
  assert(!await verifySignature(raw, `t=${t},v1=${sig}`, secret, t - 301));
  assert(!await verifySignature(raw, `t=${t},v1=${sig}`, "wrong", t));
  assert(await verifySignature(raw, `t=${t},v1=invalid,v1=${sig}`, secret, t));
});
Deno.test("paid access requires a paid invoice line matching this exact subscription item and price", () => {
  const sub: any = {
    items: { data: [{ id: "si_1", price: { id: "price_1" } }] },
    latest_invoice: {
      status: "open",
      lines: {
        data: [{
          parent: {
            subscription_item_details: {
              subscription_item: "si_1",
              proration: false,
            },
          },
          pricing: { price_details: { price: "price_1" } },
          period: { end: 2000000000 },
        }],
      },
    },
  };
  assert(paidPeriod(sub) === null);
  sub.latest_invoice.status = "paid";
  assert(paidPeriod(sub) === "2033-05-18T03:33:20.000Z");
  sub.latest_invoice.lines.data[0].pricing.price_details.price = "price_wrong";
  assert(paidPeriod(sub) === null);
  sub.latest_invoice.lines.data[0].pricing.price_details.price = "price_1";
  sub.latest_invoice.lines.data[0].parent.subscription_item_details.proration =
    true;
  assert(paidPeriod(sub) === null);
});
Deno.test("renewal schedule preserves paid annual term and disables immediate proration", () => {
  const end = Math.floor(Date.now() / 1000) + 86400 * 300;
  const phases = schedulePhases(
    {
      items: {
        data: [{ price: { id: "old_annual" }, current_period_end: end }],
      },
    },
    { current_phase: { start_date: end - 31536000 } },
    "new_monthly",
    "month",
  );
  assert(phases.phases[0].end_date === end);
  assert(phases.phases[0].items[0].price === "old_annual");
  assert(phases.phases[1].start_date === end);
  assert(phases.phases[1].duration?.interval === "month");
  assert(phases.proration_behavior === "none");
  assert(phases.end_behavior === "release");
});
Deno.test("form encoding preserves nested Stripe fields and multiple line items", () => {
  const form = encodeForm({
    metadata: { application: "ringmaster_breeder" },
    line_items: [{ price: "p1", quantity: 1 }],
    disabled: false,
  });
  assert(form.get("line_items[0][price]") === "p1");
  assert(form.get("disabled") === "false");
});
Deno.test("test keys cannot initialize a live billing client", () => {
  let rejected = false;
  try {
    new StripeClient("sk_test_example");
  } catch {
    rejected = true;
  }
  assert(rejected);
});

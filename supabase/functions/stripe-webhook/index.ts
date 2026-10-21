import { createClient } from "npm:@supabase/supabase-js@2.110.2";
import {
  APP,
  refId,
  StripeClient,
  verifySignature,
} from "../_shared/stripe.ts";
import {
  cancelOwnerSubscriptions,
  checked,
  syncSubscription,
  transaction,
} from "../_shared/billing-state.ts";
Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  const raw = await req.text();
  if (
    !await verifySignature(
      raw,
      req.headers.get("stripe-signature") ?? "",
      Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "",
    )
  ) return new Response("Invalid signature", { status: 400 });
  try {
    const event = JSON.parse(raw);
    if (!event.livemode || event.account) {
      return new Response("Wrong mode or account", { status: 400 });
    }
    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    if (
      checked<any>(
        await db.from("breeder_billing_events").select("id").eq("id", event.id)
          .maybeSingle(),
      )
    ) return Response.json({ received: true });
    const stripe = new StripeClient();
    const object = event.data.object;
    if (event.type.startsWith("customer.subscription.")) {
      await syncSubscription(db, stripe, object.id);
    } else if (event.type.startsWith("invoice.")) {
      const sub = refId(object.parent?.subscription_details?.subscription) ??
        refId(object.subscription);
      if (sub) await syncSubscription(db, stripe, sub);
    } else if (event.type.startsWith("checkout.session.")) {
      const session = await stripe.request(
        `checkout/sessions/${object.id}`,
        "GET",
        { expand: ["line_items"] },
      );
      if (session.metadata?.application === APP && session.livemode) {
        if (session.mode === "subscription" && session.subscription) {
          await syncSubscription(db, stripe, refId(session.subscription)!);
        }
        if (session.status === "expired") {
          checked(
            await db.from("breeder_billing_checkouts").update({
              state: "expired",
            }).eq("stripe_session", session.id).in("state", [
              "creating",
              "open",
            ]),
          );
        }
        if (
          session.mode === "payment" && session.payment_status === "paid" &&
          session.metadata.invitation
        ) {
          const inv = checked<any>(
            await db.from("breeder_lifetime_invitations").select("*").eq(
              "id",
              session.metadata.invitation,
            ).single(),
          );
          const offer = checked<any>(
            await db.from("breeder_billing_prices").select("*").eq(
              "id",
              inv.offer_id,
            ).single(),
          );
          if (
            !inv.owner_id || refId(session.payment_link) !== inv.stripe_link ||
            session.line_items.data.length !== 1 ||
            session.line_items.data[0].quantity !== 1 ||
            refId(session.line_items.data[0].price) !== offer.stripe_price ||
            session.amount_total !== offer.amount_cents ||
            session.currency !== "usd"
          ) throw Error("Lifetime receipt mismatch");
          const intent = await stripe.request(
            `payment_intents/${refId(session.payment_intent)}`,
            "GET",
            { expand: ["latest_charge"] },
          );
          if (intent.status !== "succeeded") {
            throw Error("Lifetime payment is not settled");
          }
          if (
            intent.latest_charge?.refunded || intent.latest_charge?.disputed
          ) {
            await transaction(db, "block_payment", {
              payment_intent: intent.id,
              reason: "Full refund or dispute",
            });
          }
          // Acquiring lifetime stops future recurring charges, including manual grants.
          await cancelOwnerSubscriptions(db, stripe, inv.owner_id, false);
          await transaction(db, "lifetime_paid", {
            owner: inv.owner_id,
            invitation: inv.id,
            price: offer.stripe_price,
            session: session.id,
            payment_intent: refId(session.payment_intent),
          });
        }
      }
    } else if (
      ["charge.refunded", "charge.dispute.created"].includes(event.type)
    ) {
      const charge = event.type === "charge.refunded"
        ? object
        : await stripe.request(`charges/${refId(object.charge)}`);
      if (charge.refunded || charge.disputed) {
        const intentId = refId(charge.payment_intent);
        if (intentId) {
          const intent = await stripe.request(`payment_intents/${intentId}`);
          if (
            intent.metadata?.application === APP && intent.metadata.invitation
          ) {
            await transaction(db, "block_payment", {
              payment_intent: intentId,
              reason: charge.disputed ? "Payment dispute" : "Full refund",
            });
          }
        }
      }
    }
    checked(
      await db.from("breeder_billing_events").upsert({
        id: event.id,
        type: event.type,
      }, { onConflict: "id", ignoreDuplicates: true }),
    );
    return Response.json({ received: true });
  } catch {
    console.error("stripe-webhook failed; event will be retried");
    return new Response("Please retry", { status: 503 });
  }
});

import { createClient } from "npm:@supabase/supabase-js@2.110.2";
import {
  APP,
  refId,
  RETURN_URL,
  schedulePhases,
  StripeClient,
} from "../_shared/stripe.ts";
import {
  cancelOwnerSubscriptions,
  checked,
  syncSubscription,
  transaction,
} from "../_shared/billing-state.ts";
const cors = {
  "Access-Control-Allow-Origin": "https://breeder.ringmasterone.com",
  "Access-Control-Allow-Headers":
    "authorization,apikey,content-type,x-client-info",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
};
const reply = (data: unknown, status = 200) =>
  Response.json(data, { status, headers: cors });
const db = () =>
  createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
async function row(database: any, table: string, column: string, value: any) {
  return checked<any>(
    await database.from(table).select("*").eq(column, value).maybeSingle(),
  );
}
async function audit(
  database: any,
  actor: string,
  owner: string | null,
  action: string,
  details: any,
) {
  checked(
    await database.from("breeder_billing_audit").insert({
      actor_id: actor,
      owner_id: owner,
      action,
      details,
    }),
  );
}
async function customer(
  database: any,
  stripe: StripeClient,
  owner: string,
  email: string,
) {
  checked(
    await database.from("breeder_billing_customers").upsert(
      { owner_id: owner },
      { onConflict: "owner_id", ignoreDuplicates: true },
    ),
  );
  const c = await row(database, "breeder_billing_customers", "owner_id", owner);
  if (!c.stripe_customer) {
    const remote = await stripe.request("customers", "POST", {
      email,
      metadata: { application: APP, owner },
    }, `customer:${c.id}`);
    checked(
      await database.from("breeder_billing_customers").update({
        stripe_customer: remote.id,
      }).eq("id", c.id),
    );
    c.stripe_customer = remote.id;
  }
  return c;
}
async function scheduleChange(
  database: any,
  stripe: StripeClient,
  s: any,
  offer: any,
  loseLock: boolean,
) {
  const current = await stripe.request(
    `subscriptions/${s.stripe_subscription}`,
  );
  if (
    current.metadata?.application !== APP ||
    current.metadata.owner !== s.owner_id || current.status !== "active" ||
    current.cancel_at_period_end
  ) throw Error("An active, renewing subscription is required.");
  let schedule = current.schedule
    ? await stripe.request(`subscription_schedules/${refId(current.schedule)}`)
    : null;
  if (
    schedule && schedule.metadata?.application !== APP &&
    schedule.id !== s.schedule_id
  ) throw Error("Contact support to review the existing schedule.");
  if (!schedule) {
    schedule = await stripe.request("subscription_schedules", "POST", {
      from_subscription: current.id,
    }, `schedule:${current.id}`);
    // Record ownership before changing phases, so a failed update can be retried.
    checked(
      await database.from("breeder_billing_subscriptions").update({
        schedule_id: schedule.id,
      }).eq("stripe_subscription", current.id),
    );
  }
  await stripe.request(
    `subscription_schedules/${schedule.id}`,
    "POST",
    schedulePhases(current, schedule, offer.stripe_price, offer.interval),
    `change:${schedule.id}:${offer.id}`,
  );
  checked(
    await database.from("breeder_billing_subscriptions").update({
      schedule_id: schedule.id,
      pending_offer_id: offer.id,
      ...(loseLock ? { price_locked: false, lock_reason: "changed_plan" } : {}),
    }).eq("stripe_subscription", current.id),
  );
  return {
    effective_at: new Date(
      (current.items.data[0].current_period_end ?? current.current_period_end) *
        1000,
    ).toISOString(),
  };
}
async function createHostedCheckout(
  database: any,
  stripe: StripeClient,
  owner: string,
  email: string,
  offer: any,
  c: any,
) {
  const cust = await customer(database, stripe, owner, email);
  const session = await stripe.request("checkout/sessions", "POST", {
    mode: "subscription",
    customer: cust.stripe_customer,
    integration_identifier: "ringmaster_breeder_abcdefgh",
    line_items: [{ price: offer.stripe_price, quantity: 1 }],
    success_url: RETURN_URL,
    cancel_url: RETURN_URL,
    expires_at: Math.floor(new Date(c.created_at).getTime() / 1000) + 86400,
    metadata: { application: APP, owner, checkout: c.id },
    subscription_data: {
      billing_mode: { type: "flexible" },
      metadata: { application: APP, owner, checkout: c.id },
    },
    custom_text: {
      submit: {
        message:
          "Recurring membership. Cancel future renewals in Account > Manage billing. Existing complimentary access is replaced by this plan. Price locks apply while the same plan and billing interval remain continuously subscribed.",
      },
    },
  }, `checkout:${c.id}`);
  checked(
    await database.from("breeder_billing_checkouts").update({
      stripe_session: session.id,
      url: session.url,
      state: "open",
    }).eq("id", c.id),
  );
  return {
    url: session.url,
    id: session.id,
    price_locked: c.early_reserved || cust.manual_price_lock,
  };
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return reply({});
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);
  let database: any, lease: string | undefined;
  try {
    database = db();
    const token = (req.headers.get("authorization") ?? "").replace(
      /^Bearer /i,
      "",
    );
    const verified = await database.auth.getUser(token);
    const user = verified.data.user;
    if (verified.error || !user?.email_confirmed_at) {
      return reply({ error: "Sign in again to manage billing." }, 401);
    }
    const own = await row(database, "users", "auth_user_id", user.id);
    if (
      !own?.is_active ||
      await row(database, "account_deletions", "user_id", user.id)
    ) return reply({ error: "Account unavailable" }, 403);
    const input = await req.json();
    const action = input.action ?? "status";
    const isAdminAction = action.startsWith("admin-");
    if (isAdminAction) {
      const auth = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_ANON_KEY")!,
        {
          global: { headers: { Authorization: `Bearer ${token}` } },
          auth: { persistSession: false, autoRefreshToken: false },
        },
      );
      if (checked(await auth.rpc("breeder_is_super_admin")) !== true) {
        return reply({ error: "Administrator access required." }, 403);
      }
    }
    const owner = isAdminAction && input.owner ? String(input.owner) : own.id;
    if (
      isAdminAction && input.owner && !await row(database, "users", "id", owner)
    ) throw Error("Account not found");
    const settings = await row(
      database,
      "breeder_billing_settings",
      "id",
      true,
    );
    if (action === "status" || action === "admin-status") {
      const prices = checked<any[]>(
        await database.from("breeder_billing_prices").select("*").order(
          "amount_cents",
        ),
      );
      return reply({
        checkout_enabled: settings.checkout_enabled,
        owner,
        offers: prices.filter((p) =>
          p.available && (isAdminAction || p.interval !== "lifetime")
        ),
        subscriptions: checked(
          await database.from("breeder_billing_subscriptions").select("*").eq(
            "owner_id",
            owner,
          ),
        ),
        grants: checked(
          await database.from("breeder_membership_grants").select(
            "id,tier_code,source,active,created_at",
          ).eq("owner_id", owner),
        ),
        checkouts: checked(
          await database.from("breeder_billing_checkouts").select(
            "id,offer_id,state,url",
          ).eq("owner_id", owner).in("state", ["creating", "open"]),
        ),
        ...(isAdminAction
          ? {
            manual_price_lock: (await row(
              database,
              "breeder_billing_customers",
              "owner_id",
              owner,
            ))?.manual_price_lock ?? false,
            rules: checked(
              await database.from("breeder_early_adopter_rules").select("*"),
            ),
            invitations: checked(
              await database.from("breeder_lifetime_invitations").select("*")
                .eq("owner_id", owner),
            ),
            history: prices,
          }
          : {}),
        prices: prices.filter((p) => isAdminAction || p.interval !== "lifetime")
          .map((p) => ({
            id: p.id,
            tier_code: p.tier_code,
            interval: p.interval,
            amount_cents: p.amount_cents,
          })),
      });
    }
    // Billing operations are never queued offline. Serialize each owner's external changes.
    lease = crypto.randomUUID();
    checked(
      await database.rpc("breeder_billing_lease", {
        p_owner: action === "admin-publish-price"
          ? "catalogue:" + input.tier + ":" + input.interval
          : owner,
        p_token: lease,
        p_release: false,
      }),
    );
    const stripe = new StripeClient();
    await stripe.verifyAccount();
    if (action === "checkout") {
      if (input.confirm !== true) {
        throw Error("Confirm the selected plan and recurring charge.");
      }
      const offer = await row(
        database,
        "breeder_billing_prices",
        "id",
        input.offer,
      );
      if (!offer?.available || offer.interval === "lifetime") {
        throw Error("Plan unavailable");
      }
      const c = await transaction(database, "reserve", {
        owner,
        offer: offer.id,
      });
      if (
        !c.stripe_session &&
        Date.now() - new Date(c.created_at).getTime() > 23 * 3600000
      ) {
        const stored = await row(
          database,
          "breeder_billing_customers",
          "owner_id",
          owner,
        );
        const sessions = stored?.stripe_customer
          ? await stripe.request("checkout/sessions", "GET", {
            customer: stored.stripe_customer,
            limit: 100,
          })
          : { data: [] };
        if (sessions.has_more) {
          throw Error("Contact support to review unfinished billing.");
        }
        const remote = sessions.data.find((x: any) =>
          x.metadata?.checkout === c.id && x.metadata?.application === APP
        );
        if (remote) {
          c.stripe_session = remote.id;
          checked(
            await database.from("breeder_billing_checkouts").update({
              stripe_session: remote.id,
              url: remote.url,
            }).eq("id", c.id),
          );
        } else {
          checked(
            await database.from("breeder_billing_checkouts").update({
              state: "expired",
            }).eq("id", c.id),
          );
          return reply({ refresh: true });
        }
      }
      if (c.stripe_session) {
        const existing = await stripe.request(
          `checkout/sessions/${c.stripe_session}`,
        );
        if (existing.status === "open") {
          return reply({ url: existing.url, price_locked: c.early_reserved });
        }
        if (existing.subscription) {
          await syncSubscription(
            database,
            stripe,
            refId(existing.subscription)!,
          );
        }
        if (existing.status === "expired") {
          checked(
            await database.from("breeder_billing_checkouts").update({
              state: "expired",
            }).eq("id", c.id),
          );
        }
        return reply({ refresh: true });
      }
      return reply(
        await createHostedCheckout(
          database,
          stripe,
          owner,
          user.email!,
          offer,
          c,
        ),
      );
    }
    if (action === "cancel-checkout") {
      const c = await row(
        database,
        "breeder_billing_checkouts",
        "id",
        input.checkout,
      );
      if (c?.owner_id !== owner || !["creating", "open"].includes(c.state)) {
        throw Error("Checkout unavailable.");
      }
      if (!c.stripe_session) {
        if (Date.now() - new Date(c.created_at).getTime() > 23 * 3600000) {
          const cust = await row(
            database,
            "breeder_billing_customers",
            "owner_id",
            owner,
          );
          const sessions = cust?.stripe_customer
            ? await stripe.request("checkout/sessions", "GET", {
              customer: cust.stripe_customer,
              limit: 100,
            })
            : { data: [] };
          if (sessions.has_more) {
            throw Error("Contact support to review unfinished billing.");
          }
          const remote = sessions.data.find((x: any) =>
            x.metadata?.checkout === c.id && x.metadata?.application === APP
          );
          if (!remote) {
            checked(
              await database.from("breeder_billing_checkouts").update({
                state: "expired",
              }).eq("id", c.id),
            );
            return reply({ updated: true });
          }
          c.stripe_session = remote.id;
        } else {
          const originalOffer = await row(
            database,
            "breeder_billing_prices",
            "id",
            c.offer_id,
          );
          const recovered = await createHostedCheckout(
            database,
            stripe,
            owner,
            user.email!,
            originalOffer,
            c,
          );
          c.stripe_session = recovered.id;
        }
      }
      let remote = await stripe.request(
        `checkout/sessions/${c.stripe_session}`,
      );
      if (remote.status === "open") {
        remote = await stripe.request(
          `checkout/sessions/${c.stripe_session}/expire`,
          "POST",
          {},
          `expire:${c.id}`,
        );
      }
      if (remote.status === "expired") {
        checked(
          await database.from("breeder_billing_checkouts").update({
            state: "expired",
          }).eq("id", c.id).in("state", ["creating", "open"]),
        );
      } else if (remote.subscription) {
        await syncSubscription(database, stripe, refId(remote.subscription)!);
      }
      return reply({ updated: true });
    }
    if (action === "portal") {
      const c = await row(
        database,
        "breeder_billing_customers",
        "owner_id",
        owner,
      );
      if (!c?.stripe_customer || !settings.portal_configuration) {
        throw Error("No Stripe billing account yet.");
      }
      const portal = await stripe.request("billing_portal/sessions", "POST", {
        customer: c.stripe_customer,
        configuration: settings.portal_configuration,
        return_url: RETURN_URL,
      });
      return reply({ url: portal.url });
    }
    if (action === "cancel-subscription") {
      if (input.confirm !== true) throw Error("Confirm cancellation.");
      await cancelOwnerSubscriptions(database, stripe, owner, false);
      await audit(database, user.id, owner, action, {});
      return reply({ updated: true });
    }
    if (action === "change-plan") {
      const s = await row(
        database,
        "breeder_billing_subscriptions",
        "stripe_subscription",
        input.subscription,
      );
      const offer = await row(
        database,
        "breeder_billing_prices",
        "id",
        input.offer,
      );
      if (
        s?.owner_id !== owner || !offer?.available ||
        offer.interval === "lifetime"
      ) throw Error("Subscription or plan unavailable");
      if (
        input.confirm !== true ||
        (s.price_locked && input.accept_lock_loss !== true)
      ) throw Error("Confirm the change and loss of any current price lock.");
      if (offer.id === s.offer_id) {
        throw Error("This is already your current plan.");
      }
      const result = await scheduleChange(database, stripe, s, offer, true);
      await audit(database, user.id, owner, action, {
        offer: offer.id,
        ...result,
      });
      return reply(result);
    }
    if (action === "admin-grant") {
      if (!["PRO", "TOP"].includes(input.tier) || !input.note?.trim()) {
        throw Error("Choose Professional or Top Tier and enter a reason.");
      }
      const pending = checked<any[]>(
        await database.from("breeder_billing_checkouts").select("*").eq(
          "owner_id",
          owner,
        ).in("state", ["creating", "open"]),
      );
      for (const checkout of pending) {
        if (!checkout.stripe_session) {
          throw Error(
            "Ask this account to close its unfinished checkout before granting lifetime access.",
          );
        }
        const session = await stripe.request(
          `checkout/sessions/${checkout.stripe_session}`,
        );
        if (session.status === "open") {
          await stripe.request(
            `checkout/sessions/${session.id}/expire`,
            "POST",
            {},
            `grant-expire:${checkout.id}`,
          );
        }
        if (session.status !== "complete") {
          checked(
            await database.from("breeder_billing_checkouts").update({
              state: "expired",
            }).eq("id", checkout.id),
          );
        } else if (session.subscription) {
          await syncSubscription(
            database,
            stripe,
            refId(session.subscription)!,
          );
        }
      }
      const invitations = checked<any[]>(
        await database.from("breeder_lifetime_invitations").select("*").eq(
          "owner_id",
          owner,
        ).eq("active", true),
      );
      for (const invitation of invitations) {
        if (invitation.stripe_link) {
          await stripe.request(
            `payment_links/${invitation.stripe_link}`,
            "POST",
            { active: false },
            `grant-disable:${invitation.id}`,
          );
        }
        checked(
          await database.from("breeder_lifetime_invitations").update({
            active: false,
          }).eq("id", invitation.id),
        );
      }
      await cancelOwnerSubscriptions(database, stripe, owner, false);
      const result = await transaction(database, "grant", {
        owner,
        tier: input.tier,
        note: input.note,
        actor: user.id,
      });
      return reply(result);
    }
    if (action === "admin-revoke") {
      if (!input.note?.trim()) {
        throw Error("Enter a reason for removing lifetime access.");
      }
      return reply(
        await transaction(database, "revoke", {
          owner,
          grant: input.grant,
          note: input.note,
          actor: user.id,
        }),
      );
    }
    if (action === "admin-rule") {
      if (
        !["HOBBY", "PRO", "TOP"].includes(input.tier) ||
        !Number.isInteger(input.quota) || input.quota < 0 ||
        input.quota > 100000
      ) throw Error("Enter a valid first-customer limit.");
      checked(
        await database.from("breeder_early_adopter_rules").update({
          quota: input.quota,
          enabled: input.quota > 0,
        }).eq("tier_code", input.tier),
      );
      await audit(database, user.id, null, action, {
        tier: input.tier,
        quota: input.quota,
      });
      return reply({ updated: true });
    }
    if (action === "admin-lock") {
      checked(
        await database.from("breeder_billing_customers").upsert({
          owner_id: owner,
        }, { onConflict: "owner_id", ignoreDuplicates: true }),
      );
      const subs = checked<any[]>(
        await database.from("breeder_billing_subscriptions").select("*").eq(
          "owner_id",
          owner,
        ).not("status", "in", "(canceled,incomplete_expired)"),
      );
      if (subs.some((s) => s.pending_offer_id)) {
        throw Error(
          "Resolve scheduled plan changes before changing a price lock.",
        );
      }
      checked(
        await database.from("breeder_billing_customers").update({
          manual_price_lock: input.enabled === true,
        }).eq("owner_id", owner),
      );
      checked(
        await database.from("breeder_billing_subscriptions").update({
          price_locked: input.enabled === true,
          lock_reason: "manual",
        }).eq("owner_id", owner).not(
          "status",
          "in",
          "(canceled,incomplete_expired)",
        ),
      );
      await audit(database, user.id, owner, action, {
        enabled: input.enabled === true,
      });
      return reply({ updated: true });
    }
    if (action === "admin-lifetime-link") {
      if (
        !["PRO", "TOP"].includes(input.tier) ||
        !Number.isInteger(input.amount_cents) || input.amount_cents < 100 ||
        input.amount_cents > 99999999
      ) throw Error("Enter the one-time lifetime price in USD.");
      // Prevent selling a second lifetime membership or making concurrent links.
      if (
        checked<any[]>(
          await database.from("breeder_membership_grants").select("id").eq(
            "owner_id",
            owner,
          ).eq("active", true),
        ).length
      ) throw Error("Lifetime membership already active.");
      if (
        checked<any[]>(
          await database.from("breeder_lifetime_invitations").select("id").eq(
            "owner_id",
            owner,
          ).eq("active", true).neq("id", input.operation),
        ).length
      ) throw Error("Disable the existing private link first.");
      const operation = String(input.operation ?? "");
      if (!/^[a-f0-9-]{36}$/.test(operation)) {
        throw Error("Refresh and try again.");
      }
      const product = await stripe.request("products", "POST", {
        name: `RingMaster Breeder ${
          input.tier === "PRO" ? "Professional" : "Top Tier"
        } Lifetime`,
        metadata: { application: APP, tier_code: input.tier },
      }, `lifetime-product:${operation}`);
      const price = await stripe.request("prices", "POST", {
        product: product.id,
        currency: "usd",
        unit_amount: input.amount_cents,
        metadata: { application: APP },
      }, `lifetime-price:${operation}`);
      let offer = await row(
        database,
        "breeder_billing_prices",
        "stripe_price",
        price.id,
      );
      if (!offer) {
        offer = checked<any>(
          await database.from("breeder_billing_prices").insert({
            tier_code: input.tier,
            interval: "lifetime",
            amount_cents: input.amount_cents,
            stripe_product: product.id,
            stripe_price: price.id,
          }).select().single(),
        );
      }
      let inv = await row(
        database,
        "breeder_lifetime_invitations",
        "id",
        operation,
      );
      if (inv && (inv.owner_id !== owner || inv.offer_id !== offer.id)) {
        throw Error("Invitation changed; refresh before retrying.");
      }
      if (!inv) {
        inv = checked<any>(
          await database.from("breeder_lifetime_invitations").insert({
            id: operation,
            owner_id: owner,
            offer_id: offer.id,
          }).select().single(),
        );
      }
      const link = await stripe.request("payment_links", "POST", {
        line_items: [{ price: price.id, quantity: 1 }],
        restrictions: { completed_sessions: { limit: 1 } },
        metadata: { application: APP, invitation: inv.id },
        payment_intent_data: {
          metadata: { application: APP, invitation: inv.id },
        },
        after_completion: { type: "redirect", redirect: { url: RETURN_URL } },
        custom_text: {
          submit: {
            message:
              "This private lifetime purchase grants access only to the RingMaster Breeder account named by your invitation. Any existing recurring Breeder membership will stop renewing.",
          },
        },
      }, `lifetime-link:${inv.id}`);
      checked(
        await database.from("breeder_lifetime_invitations").update({
          stripe_link: link.id,
          url: link.url,
        }).eq("id", inv.id),
      );
      await audit(database, user.id, owner, action, {
        invitation: inv.id,
        amount_cents: input.amount_cents,
        tier: input.tier,
      });
      return reply({ url: link.url });
    }
    if (action === "admin-disable-link") {
      const inv = await row(
        database,
        "breeder_lifetime_invitations",
        "id",
        input.invitation,
      );
      if (inv?.owner_id !== owner || !inv.stripe_link) {
        throw Error("Link unavailable");
      }
      await stripe.request(`payment_links/${inv.stripe_link}`, "POST", {
        active: false,
      }, `disable:${inv.id}`);
      checked(
        await database.from("breeder_lifetime_invitations").update({
          active: false,
        }).eq("id", inv.id),
      );
      await audit(database, user.id, owner, action, { invitation: inv.id });
      return reply({ updated: true });
    }
    if (action === "admin-publish-price") {
      if (
        !["HOBBY", "PRO", "TOP"].includes(input.tier) ||
        !["month", "year"].includes(input.interval) ||
        !Number.isInteger(input.amount_cents) || input.amount_cents < 100 ||
        input.amount_cents > 99999999 || input.confirm_notice !== true
      ) {
        throw Error(
          "Enter a valid price and confirm renewal notices have been handled.",
        );
      }
      const existing = checked<any>(
        await database.from("breeder_billing_prices").select("*").eq(
          "tier_code",
          input.tier,
        ).eq("interval", input.interval).eq("available", true).single(),
      );
      let offer = existing;
      if (existing.amount_cents !== input.amount_cents) {
        const price = await stripe.request("prices", "POST", {
          product: existing.stripe_product,
          currency: "usd",
          unit_amount: input.amount_cents,
          recurring: { interval: input.interval },
          metadata: { application: APP },
        }, `price:${existing.id}:${input.amount_cents}`);
        offer = checked(
          await database.rpc("breeder_publish_price", {
            p_previous: existing.id,
            p_price: price.id,
            p_amount: input.amount_cents,
            p_actor: user.id,
          }),
        );
      }
      const subscriptions = checked<any[]>(
        await database.from("breeder_billing_subscriptions").select("*").eq(
          "status",
          "active",
        ).eq("price_locked", false).eq("cancel_at_period_end", false),
      );
      const results = [];
      for (const s of subscriptions) {
        const old = await row(
          database,
          "breeder_billing_prices",
          "id",
          s.offer_id,
        );
        if (
          old.tier_code !== input.tier || old.interval !== input.interval ||
          s.offer_id === offer.id ||
          s.pending_offer_id && s.pending_offer_id !== offer.id
        ) continue;
        const subLease = crypto.randomUUID();
        try {
          checked(
            await database.rpc("breeder_billing_lease", {
              p_owner: s.owner_id,
              p_token: subLease,
              p_release: false,
            }),
          );
          const fresh = await row(
            database,
            "breeder_billing_subscriptions",
            "stripe_subscription",
            s.stripe_subscription,
          );
          if (
            fresh.price_locked ||
            fresh.pending_offer_id && fresh.pending_offer_id !== offer.id
          ) continue;
          results.push({
            subscription: s.stripe_subscription,
            ...await scheduleChange(database, stripe, fresh, offer, false),
          });
        } catch {
          results.push({
            subscription: s.stripe_subscription,
            error: "Retry publishing this same price to finish scheduling.",
          });
        } finally {
          await database.rpc("breeder_billing_lease", {
            p_token: subLease,
            p_release: true,
          });
        }
      }
      await audit(database, user.id, null, action, {
        offer: offer.id,
        notice_confirmed: true,
        results,
      });
      return reply({ updated: true, results });
    }
    if (action === "refresh") {
      const subs = checked<any[]>(
        await database.from("breeder_billing_subscriptions").select("*").eq(
          "owner_id",
          owner,
        ),
      );
      for (const s of subs) {
        await syncSubscription(database, stripe, s.stripe_subscription);
      }
      const open = checked<any[]>(
        await database.from("breeder_billing_checkouts").select("*").eq(
          "owner_id",
          owner,
        ).in("state", ["creating", "open"]),
      );
      for (const c of open) {
        if (c.stripe_session) {
          const session = await stripe.request(
            `checkout/sessions/${c.stripe_session}`,
          );
          if (session.subscription) {
            await syncSubscription(
              database,
              stripe,
              refId(session.subscription)!,
            );
          }
          if (session.status === "expired") {
            checked(
              await database.from("breeder_billing_checkouts").update({
                state: "expired",
              }).eq("id", c.id),
            );
          }
        }
      }
      return reply({ updated: true });
    }
    return reply({ error: "Unknown billing action" }, 400);
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Billing unavailable. Please retry.";
    console.error("billing request failed");
    return reply({ error: message }, 400);
  } finally {
    if (database && lease) {
      await database.rpc("breeder_billing_lease", {
        p_owner: undefined,
        p_token: lease,
        p_release: true,
      });
    }
  }
});

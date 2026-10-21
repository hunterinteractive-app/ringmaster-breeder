import { createClient } from "npm:@supabase/supabase-js@2.110.2";
import { checked } from "../_shared/billing-state.ts";
import { StripeClient } from "../_shared/stripe.ts";
import { processPriceNotice } from "./worker.ts";
Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Use POST" }, { status: 405 });
  }
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  try {
    if (
      checked(
        await db.rpc("breeder_price_worker_authorized", {
          p_token: req.headers.get("x-worker-token") ?? "",
        }),
      ) !== true
    ) return Response.json({ error: "Unauthorized" }, { status: 401 });
    const lease = crypto.randomUUID();
    checked(
      await db.rpc("breeder_billing_lease", {
        p_owner: "price-worker",
        p_token: lease,
        p_release: false,
      }),
    );
    try {
      const relayUrl = Deno.env.get("SHOW_SUPABASE_URL"),
        relayKey = Deno.env.get("BREEDER_SUPABASE_SERVICE_ROLE_KEY");
      if (!relayUrl || !relayKey) throw Error("Email relay not configured");
      const health = await fetch(
        `${relayUrl}/functions/v1/send-breeder-billing`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${relayKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ action: "status" }),
          signal: AbortSignal.timeout(10000),
        },
      );
      if (!health.ok || (await health.json()).configured !== true) {
        throw Error("Email service not ready");
      }
      checked(await db.rpc("breeder_price_tick"));
      const jobs = checked<any[]>(
        await db.from("breeder_price_notices").select("*").eq("state", "queued")
          .lte("retry_at", new Date().toISOString()).order("retry_at").limit(2),
      );
      if (!jobs.length) {
        return Response.json({ processed: 0, email_configured: true });
      }
      const stripe = new StripeClient();
      await stripe.verifyAccount();
      const send = async (n: any) => {
        const url = Deno.env.get("SHOW_SUPABASE_URL"),
          key = Deno.env.get("BREEDER_SUPABASE_SERVICE_ROLE_KEY");
        if (!url || !key) {
          throw Error("Billing email delivery is not configured.");
        }
        const response = await fetch(
          `${url}/functions/v1/send-breeder-billing`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${key}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              request_id: n.id,
              recipient: n.recipient,
              message: n.message,
            }),
            signal: AbortSignal.timeout(25000),
          },
        );
        const result = await response.json();
        if (!response.ok || typeof result.provider_id !== "string") {
          throw Error("Email provider acceptance not confirmed.");
        }
        return result.provider_id;
      };
      let processed = 0;
      const started = Date.now();
      for (const n of jobs) {
        if (Date.now() - started > 40000) break;
        const ownerLease = crypto.randomUUID();
        let acquired = false;
        try {
          checked(
            await db.rpc("breeder_billing_lease", {
              p_owner: n.owner_id ?? "deleted:" + n.id,
              p_token: ownerLease,
              p_release: false,
            }),
          );
          acquired = true;
          await processPriceNotice(db, stripe, n, send);
          processed++;
        } catch (e) {
          checked(
            await db.from("breeder_price_notices").update({
              attempts: n.attempts + 1,
              retry_at: new Date(Date.now() + 15 * 60000).toISOString(),
              last_error: e instanceof Error
                ? e.message.slice(0, 250)
                : "Retry required",
            }).eq("id", n.id),
          );
        } finally {
          if (acquired) {
            await db.rpc("breeder_billing_lease", {
              p_token: ownerLease,
              p_release: true,
            });
          }
        }
      }
      return Response.json({ processed });
    } finally {
      await db.rpc("breeder_billing_lease", {
        p_token: lease,
        p_release: true,
      });
    }
  } catch {
    return Response.json({ error: "Price worker unavailable" }, {
      status: 503,
    });
  }
});

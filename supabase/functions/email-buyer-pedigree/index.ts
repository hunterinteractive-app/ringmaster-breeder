import { createClient } from "npm:@supabase/supabase-js@2.110.2";
import {
  digest,
  pdfBytes,
  publicPedigree,
  readBody,
  validEmail,
} from "./core.ts";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization,apikey,content-type,x-client-info",
  "Cache-Control": "no-store",
  "Content-Type": "application/json",
};
const reply = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), { status, headers: cors });
const uuid = /^[a-f\d]{8}(-[a-f\d]{4}){3}-[a-f\d]{12}$/i;
const options = { auth: { persistSession: false, autoRefreshToken: false } };
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: { ...cors, "Access-Control-Allow-Methods": "POST,OPTIONS" },
    });
  }
  if (req.method !== "POST") return reply({ error: "Use POST." }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!,
      anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const client = createClient(url, anon, {
      ...options,
      global: {
        headers: { Authorization: req.headers.get("Authorization") ?? "" },
      },
    });
    const verified = await client.auth.getUser();
    const actor = verified.data.user;
    if (verified.error || !actor?.email_confirmed_at) {
      return reply({ error: "Sign in again to email a pedigree." }, 401);
    }
    let body;
    try {
      body = await readBody(req);
    } catch {
      return reply({
        error: "Invalid request or attachment. Maximum PDF size is 4 MB.",
      }, 400);
    }
    if (
      !uuid.test(body.request_id ?? "") || !uuid.test(body.animal_id ?? "") ||
      !["prepare", "send"].includes(body.action)
    ) return reply({ error: "Invalid pedigree request." }, 400);
    const animal = await client.from("animals").select("id,ring_id,status").eq(
      "id",
      body.animal_id,
    ).maybeSingle();
    if (animal.error || !animal.data) {
      return reply({
        error: "Animal is unavailable or family access has ended.",
      }, 403);
    }
    if (animal.data.status !== "sold") {
      return reply({
        error: "Mark the animal Sold before emailing its sale pedigree.",
      }, 409);
    }
    const farm = await client.from("farms").select("owner_id").eq(
      "id",
      animal.data.ring_id,
    ).single();
    if (farm.error) {
      return reply({ error: "Family access is unavailable." }, 403);
    }
    const admin = createClient(
      url,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      options,
    );
    const showUrl = Deno.env.get("SHOW_SUPABASE_URL"),
      showKey = Deno.env.get("BREEDER_SUPABASE_SERVICE_ROLE_KEY");
    if (!showUrl || !showKey) {
      return reply({
        error:
          "Pedigree email delivery is not configured. Your sale remains saved.",
      }, 503);
    }
    const relay = async (payload: unknown) =>
      fetch(`${showUrl}/functions/v1/send-breeder-pedigree`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${showKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(25000),
      });
    let found = await admin.from("pedigree_buyer_emails").select("*").eq(
      "id",
      body.request_id,
    ).maybeSingle();
    if (found.error) throw new Error("Request unavailable");
    if (
      found.data &&
      (found.data.actor_id !== actor.id ||
        found.data.animal_id !== body.animal_id)
    ) return reply({ error: "Request is unavailable." }, 403);
    if (body.action === "prepare") {
      let job = found.data;
      if (!job) {
        const recent = await admin.from("pedigree_buyer_emails").select("id", {
          count: "exact",
          head: true,
        }).eq("actor_id", actor.id).gte(
          "created_at",
          new Date(Date.now() - 3600000).toISOString(),
        );
        if (recent.error) throw new Error("Request unavailable");
        if ((recent.count ?? 0) >= 50) {
          return reply({
            error: "Please wait before preparing more pedigree emails.",
          }, 429);
        }
        const owner = await client.from("users").select(
          "auth_user_id,display_name,username",
        ).eq("id", farm.data.owner_id).single();
        if (owner.error || !owner.data.auth_user_id) {
          return reply({
            error:
              "The account owner must verify their email before sending pedigrees.",
          }, 409);
        }
        const identity = await admin.auth.admin.getUserById(
          owner.data.auth_user_id,
        );
        if (
          identity.error || !identity.data.user?.email_confirmed_at ||
          !validEmail(identity.data.user.email)
        ) {
          return reply({
            error: "The account owner needs a verified email address.",
          }, 409);
        }
        const snapshot = await client.rpc("breeder_pedigree_snapshot", {
          p_animal_id: body.animal_id,
        });
        if (snapshot.error || !snapshot.data?.animal) {
          return reply({ error: "Unable to prepare this pedigree." }, 409);
        }
        let saleId = null;
        let suggestedRecipient = "";
        if (body.sale_id) {
          if (!uuid.test(body.sale_id)) {
            return reply({ error: "Invalid sale." }, 400);
          }
          const sale = await client.from("animal_sales").select(
            "id,animal_id,status,buyer_email",
          ).eq("id", body.sale_id).single();
          if (
            sale.error || sale.data.animal_id !== body.animal_id ||
            sale.data.status !== "sold"
          ) return reply({ error: "Sale is unavailable." }, 403);
          saleId = sale.data.id;
          suggestedRecipient = sale.data.buyer_email ?? "";
        }
        if (!saleId) {
          const recentSale = await client.from("animal_sales").select(
            "id,buyer_email",
          ).eq("animal_id", body.animal_id).eq("status", "sold").order(
            "created_at",
            { ascending: false },
          ).limit(1);
          if (recentSale.error) throw new Error("Sale unavailable");
          if (recentSale.data.length) {
            saleId = recentSale.data[0].id;
            suggestedRecipient = recentSale.data[0].buyer_email ?? "";
          }
        }
        const exportJson = {
          format: "ringmaster-pedigree",
          version: 1,
          exported_at: new Date().toISOString(),
          pedigree: publicPedigree(snapshot.data),
        };
        const row = {
          id: body.request_id,
          actor_id: actor.id,
          animal_id: body.animal_id,
          sale_id: saleId,
          suggested_recipient: suggestedRecipient,
          owner_name: String(
            owner.data.display_name || owner.data.username || "Breeder",
          ).replace(/[\r\n<>"\\]/g, "").slice(0, 100),
          owner_email: identity.data.user.email,
          export_json: exportJson,
        };
        const inserted = await admin.from("pedigree_buyer_emails").insert(row)
          .select("*").single();
        if (inserted.error) {
          if (inserted.error.code !== "23505") {
            throw new Error("Request unavailable");
          }
          found = await admin.from("pedigree_buyer_emails").select("*").eq(
            "id",
            body.request_id,
          ).single();
          job = found.data;
          if (
            !job || job.actor_id !== actor.id ||
            job.animal_id !== body.animal_id
          ) return reply({ error: "Request unavailable." }, 403);
        } else job = inserted.data;
      }
      const health = await relay({ action: "status" });
      if (!health.ok) {
        return reply({
          error:
            "Pedigree email delivery is temporarily unavailable. Your sale remains saved.",
        }, 503);
      }
      return reply({
        request_id: job.id,
        pedigree: job.export_json.pedigree,
        owner_name: job.owner_name,
        owner_email: job.owner_email,
        buyer_email: job.suggested_recipient,
      });
    }
    const job = found.data;
    if (!job) {
      return reply({ error: "Prepare the pedigree before sending." }, 409);
    }
    const recipient = typeof body.recipient === "string"
      ? body.recipient.trim().toLowerCase()
      : "";
    if (!validEmail(recipient)) {
      return reply({ error: "Enter one valid buyer email address." }, 400);
    }
    let pdf: string;
    try {
      pdf = pdfBytes(body.pdf);
    } catch {
      return reply({ error: "Invalid PDF attachment." }, 400);
    }
    const hash = await digest(`${recipient}|${pdf}`);
    if (job.payload_hash && job.payload_hash !== hash) {
      return reply({
        error:
          "This request was already submitted with different details. Check its status before starting another email.",
      }, 409);
    }
    if (
      job.status !== "accepted" &&
      Date.now() - Date.parse(job.created_at) > 23 * 3600000
    ) {
      return reply({
        error:
          "This email request is too old to retry safely. Check with the buyer before sending again.",
      }, 409);
    }
    if (job.status === "draft") {
      const claimed = await admin.from("pedigree_buyer_emails").update({
        recipient,
        payload_hash: hash,
        status: "pending",
      }).eq("id", job.id).eq("status", "draft").select("id");
      if (claimed.error) throw new Error("Request unavailable");
      if (claimed.data.length === 0) {
        const current = await admin.from("pedigree_buyer_emails").select(
          "payload_hash",
        ).eq("id", job.id).single();
        if (current.error || current.data.payload_hash !== hash) {
          return reply({ error: "Another send is already in progress." }, 409);
        }
      }
    }
    let providerId = job.provider_id;
    if (job.status !== "accepted") {
      const sent = await relay({
        action: "send",
        request_id: job.id,
        recipient,
        owner_name: job.owner_name,
        owner_email: job.owner_email,
        export_json: job.export_json,
        pdf,
      });
      if (!sent.ok) {
        return reply({
          error:
            "The email was not confirmed. Retry this same request; your sale is saved.",
        }, 503);
      }
      const data = await sent.json();
      providerId = data.provider_id;
      if (typeof providerId !== "string") {
        throw new Error("Provider confirmation unavailable");
      }
      const saved = await admin.from("pedigree_buyer_emails").update({
        status: "accepted",
        accepted_at: new Date().toISOString(),
        provider_id: providerId,
      }).eq("id", job.id);
      if (saved.error) throw new Error("Request unavailable");
    }
    if (job.sale_id) {
      const audit = await admin.from("animal_sale_history").insert({
        sale_id: job.sale_id,
        event: "pedigree_email_accepted",
        created_by: actor.id,
        details: {
          email_request_id: job.id,
          recipient,
          attachments: ["pedigree.pdf", "pedigree.json"],
          provider_id: providerId,
        },
      });
      if (audit.error && audit.error.code !== "23505") {
        throw new Error("History unavailable");
      }
    }
    return reply({ status: "accepted", provider_id: providerId });
  } catch {
    return reply({
      error:
        "Pedigree email is temporarily unavailable. Your sale remains saved; retry the same request.",
    }, 503);
  }
});

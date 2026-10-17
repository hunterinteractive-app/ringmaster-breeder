import { createClient } from "npm:@supabase/supabase-js@2.110.2";
import { canonical, validateJob } from "./core.ts";
import { publicPedigree } from "../email-buyer-pedigree/core.ts";
declare const EdgeRuntime: { waitUntil(task: Promise<unknown>): void };
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization,apikey,content-type,x-client-info",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
const reply = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: cors });
const uuid = /^[a-f\d]{8}(-[a-f\d]{4}){3}-[a-f\d]{12}$/i;
const fingerprint = async (value: unknown) =>
  Array.from(
    new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(canonical(value)),
      ),
    ),
    (v) => v.toString(16).padStart(2, "0"),
  ).join("");
const metadata = (payload: Record<string, unknown>) =>
  Object.fromEntries(
    Object.entries(payload).filter(([k]) =>
      !["pdf", "approved_snapshot", "p_animals", "p_history"].includes(k)
    ),
  );
const options = { auth: { persistSession: false, autoRefreshToken: false } };
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return reply({});
  if (request.method !== "POST") return reply({ error: "Use POST" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!,
    key = Deno.env.get("SUPABASE_ANON_KEY")!;
  const authorization = request.headers.get("Authorization") || "";
  const scoped = createClient(url, key, {
    ...options,
    global: { headers: { Authorization: authorization } },
  });
  const auth = await scoped.auth.getUser();
  if (auth.error || !auth.data.user?.email_confirmed_at) {
    return reply({ error: "Sign in again to submit this request" }, 401);
  }
  const actor = auth.data.user.id;
  const admin = createClient(
    url,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    options,
  );
  try {
    const raw = await request.text();
    if (raw.length > 12 * 1024 * 1024) {
      return reply({ error: "This queued request is too large" }, 413);
    }
    const body = JSON.parse(raw);
    if (!["enqueue", "retry", "cancel"].includes(body.action)) {
      return reply({ error: "Unsupported queue action" }, 400);
    }
    if (!uuid.test(body.id || "")) {
      return reply({ error: "Invalid request identity" }, 400);
    }
    const found = await admin.from("breeder_offline_jobs").select("*").eq(
      "id",
      body.id,
    ).maybeSingle();
    if (found.error) throw found.error;
    if (found.data && found.data.actor !== actor) {
      return reply({ error: "Request identity is already in use" }, 409);
    }
    if (body.action === "cancel") {
      const cancelled = await admin.from("breeder_offline_jobs").update({
        state: "cancelled",
        ...(found.data ? { payload: metadata(found.data.payload) } : {}),
      }).eq("id", body.id).eq("actor", actor).in("state", [
        "queued",
        "needs_input",
        "review",
        "failed",
      ]).select("id,state").maybeSingle();
      if (cancelled.error) throw cancelled.error;
      if (!cancelled.data) {
        return reply({
          error: "This request has started and cannot be cancelled",
        }, 409);
      }
      return reply(cancelled.data);
    }
    const staleBefore = new Date(Date.now() - 5 * 60 * 1000).toISOString();
    const retryableState = found.data &&
      (["failed", "queued"].includes(found.data.state) ||
        found.data.state === "running" && found.data.started_at < staleBefore);
    const storedRetry = found.data && body.action === "retry" &&
      body.target == null;
    if (found.data) {
      if (body.action === "retry" && body.target == null) {
        body.target = found.data.target;
        body.payload = found.data.payload;
      }
      if (
        body.target !== found.data.target ||
        !storedRetry &&
          await fingerprint(body.payload) !==
            (found.data.payload_hash || await fingerprint(found.data.payload))
      ) {
        return reply(
          { error: "A different request already uses this ID" },
          409,
        );
      }
      if (body.action !== "retry" || !retryableState) {
        return reply({
          id: found.data.id,
          state: found.data.state,
          result: found.data.result,
          error: found.data.error,
        }, 202);
      }
    } else {
      validateJob(body.target, body.payload);
      const inserted = await admin.from("breeder_offline_jobs").insert({
        id: body.id,
        actor,
        target: body.target,
        payload: body.payload,
        payload_hash: await fingerprint(body.payload),
        state: body.payload.requires_sign_in ? "needs_input" : "queued",
      });
      if (inserted.error) {
        if (inserted.error.code === "23505") {
          return reply({
            error:
              "This request identity is being confirmed. Retry the same request.",
          }, 503);
        }
        throw inserted.error;
      }
    }
    const run = async () => {
      const claimed = await admin.from("breeder_offline_jobs").update({
        state: "running",
        started_at: new Date().toISOString(),
        error: null,
      }).eq("id", body.id).eq("actor", actor).or(
        body.action === "retry"
          ? `state.in.(failed,queued),and(state.eq.running,started_at.lt.${staleBefore})`
          : "state.eq.queued",
      ).select("*").maybeSingle();
      if (claimed.error || !claimed.data) return;
      const job = claimed.data;
      try {
        // The caller's verified JWT is held only in this invocation. Existing
        // services recheck family access before performing their work.
        const invoke = async (target: string, payload: unknown) => {
          const response = await fetch(url + "/functions/v1/" + target, {
            method: "POST",
            headers: {
              apikey: key,
              Authorization: authorization,
              "Content-Type": "application/json",
            },
            body: JSON.stringify(payload),
            signal: AbortSignal.timeout(90000),
          });
          const data = await response.json();
          if (!response.ok || data.error) {
            throw Error(
              data.error || data.message ||
                "The service could not complete this request",
            );
          }
          return data;
        };
        let result: any;
        if (job.target === "email-buyer-pedigree") {
          const approved = job.payload.approved_snapshot;
          const prepared = await invoke("email-buyer-pedigree", {
            action: "prepare",
            request_id: job.payload.request_id,
            animal_id: job.payload.animal_id,
            ...(job.payload.sale_id ? { sale_id: job.payload.sale_id } : {}),
          });
          if (
            job.payload.approved_owner_email &&
              job.payload.approved_owner_email !== prepared.owner_email ||
            job.payload.approved_owner_name &&
              job.payload.approved_owner_name !== prepared.owner_name
          ) {
            throw Error(
              "The sender details changed before sending. Review and prepare a new email.",
            );
          }
          if (
            approved &&
            canonical(publicPedigree(prepared.pedigree)) !==
              canonical(publicPedigree(approved))
          ) {
            throw Error(
              "The pedigree changed before the email was sent. Review it and prepare a new email. Your approved PDF is retained.",
            );
          }
          result = await invoke("email-buyer-pedigree", {
            action: "send",
            request_id: job.payload.request_id,
            animal_id: job.payload.animal_id,
            recipient: job.payload.recipient,
            pdf: job.payload.pdf,
          });
        } else if (job.target === "global-pedigree-import") {
          const imported = await scoped.rpc("breeder_offline_apply", {
            p_operation: {
              id: job.id,
              request: {
                type: "rpc",
                target: "import_global_pedigree_with_sales",
                body: job.payload,
              },
              expects: [],
              mutations: [],
            },
          });
          if (imported.error) throw imported.error;
          result = imported.data.result;
        } else {
          result = await invoke(
            job.target,
            job.target === "import-ringmaster-records" &&
              job.payload.action === "import"
              ? { ...job.payload, offline_request_id: job.id }
              : job.payload,
          );
          if (
            job.target === "show-reports" &&
            job.payload.action === "download" && typeof result.url === "string"
          ) {
            const response = await fetch(result.url, {
              signal: AbortSignal.timeout(30000),
            });
            if (!response.ok) throw Error("Unable to download this report");
            const file = new Uint8Array(await response.arrayBuffer());
            if (file.length > 10 * 1024 * 1024) {
              throw Error("This report exceeds the 10 MB offline file limit");
            }
            const path = actor + "/" + body.id + ".pdf";
            const uploaded = await admin.storage.from("offline_results").upload(
              path,
              file,
              { contentType: "application/pdf", upsert: true },
            );
            if (uploaded.error) throw uploaded.error;
            result = {
              file: {
                bucket: "offline_results",
                path,
                type: "application/pdf",
              },
            };
          }
        }
        const review = job.target === "import-ringmaster-records" &&
            job.payload.action === "lookup" ||
          job.target === "show-reports" && job.payload.action === "download";
        const saved = await admin.from("breeder_offline_jobs").update({
          state: review ? "review" : "complete",
          payload: metadata(job.payload),
          result,
          completed_at: new Date().toISOString(),
        }).eq("id", body.id).eq("state", "running").eq(
          "started_at",
          job.started_at,
        );
        if (saved.error) throw saved.error;
      } catch (error) {
        await admin.from("breeder_offline_jobs").update({
          state: "failed",
          error: error instanceof Error
            ? error.message
            : "The request did not complete. Retry the same request to check its result.",
        }).eq("id", body.id).eq("state", "running").eq(
          "started_at",
          job.started_at,
        );
      }
    };
    EdgeRuntime.waitUntil(run());
    return reply({
      id: body.id,
      state: body.payload.requires_sign_in ? "needs_input" : "queued",
    }, 202);
  } catch (error) {
    return reply({
      error: error instanceof Error
        ? error.message
        : "Unable to save this request",
    }, 400);
  }
});

import { createClient } from "npm:@supabase/supabase-js@2.110.2";
import { batch, historyBatch, open, seal, start } from "./collector.ts";
import { inspectSales, salesRecords } from "./sales.ts";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (request.method !== "POST") return reply({ message: "Use POST." }, 405);
  const authorization = request.headers.get("authorization");
  if (!authorization) {
    return reply({ message: "Sign in to Breeder before importing." }, 401);
  }
  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    },
  );
  const { data: { user }, error } = await client.auth.getUser();
  if (error || !user?.email_confirmed_at) {
    return reply({
      message: "Sign in with a verified Breeder account before importing.",
    }, 401);
  }
  const secret = Deno.env.get("GLOBAL_PEDIGREE_SESSION_KEY") ||
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!secret) {
    return reply({ message: "The importer is not configured yet." }, 503);
  }
  try {
    if (Number(request.headers.get("content-length") || 0) > 1100000) {
      return reply({ message: "Request too large." }, 413);
    }
    const raw = await request.text();
    if (raw.length > 1100000) {
      return reply({ message: "Request too large." }, 413);
    }
    const body = JSON.parse(raw);
    let state;
    if (body.token) {
      if (typeof body.token !== "string") {
        throw new Error("Invalid import session.");
      }
      state = await open(body.token, secret, user.id);
    } else {
      if (
        typeof body.username !== "string" ||
        typeof body.password !== "string" || !body.username.trim() ||
        !body.password || body.username.length > 320 ||
        body.password.length > 1024
      ) throw new Error("Enter your Global Pedigree username and password.");
      state = await start(user.id, body.username.trim(), body.password);
      const page = await inspectSales(state);
      state.salesRecords = salesRecords(page);
      state.salesComplete = true;
      for (const sale of state.salesRecords) {
        const id = String(sale.animal_source_id);
        if (!state.queue.includes(id)) state.queue.push(id);
        if (!state.owned.includes(id)) state.owned.push(id);
      }
      // Login and listing have their own request budget; detail collection starts next.
      return reply({
        status: state.queue.length ? "collecting" : "collected",
        account: state.account,
        animals: [],
        token: state.queue.length ? await seal(state, secret) : null,
      });
    }
    if (!Array.isArray(state.historyQueue) || !Array.isArray(state.live)) {
      throw new Error(
        "The import session needs a fresh connection for live herd status.",
      );
    }
    const animals = state.queue.length ? await batch(state) : [];
    const history = animals.length ? [] : await historyBatch(state);
    if (
      !state.queue.length && !state.historyQueue?.length &&
      state.salesRecords?.length
    ) {
      history.push(...state.salesRecords);
      state.salesRecords = [];
    }
    const complete = !state.queue.length && !state.historyQueue?.length;
    return reply({
      status: complete ? "collected" : "collecting",
      account: state.account,
      animals,
      history,
      history_complete: complete,
      sales_complete: complete && state.salesComplete === true,
      show_results_available: false,
      token: complete ? null : await seal(state, secret),
    });
  } catch (error) {
    // Do not log upstream HTML, cookies, passwords, or request bodies.
    const message = error instanceof Error &&
        /^(Global Pedigree|Unable to|A rabbit|A Global Pedigree|An unsupported|This importer|The import session|Enter your|Too many|Empty response|Invalid import)/
          .test(error.message)
      ? error.message
      : "Unable to read Global Pedigree. Please reconnect and try again.";
    return reply({ message }, 400);
  }
});

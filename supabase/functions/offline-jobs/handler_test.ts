// Exercise the actual HTTP handler with a fully isolated Supabase/service fixture.
// Every unrecognized outbound URL fails; no live Auth, database or email calls.
const actor = "11111111-1111-4111-8111-111111111111";
const jobs = new Map<string, Record<string, any>>(),
  calls: { target: string; body: any }[] = [],
  tasks: Promise<unknown>[] = [];
let handler: (request: Request) => Response | Promise<Response>;
const assert = (v: unknown, m = "Assertion failed") => {
  if (!v) throw Error(m);
};
const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json" },
  });
let failService = false, mismatchedPedigree = false;
const fixtureFetch: typeof fetch = async (input, init) => {
  const request = new Request(input, init), url = new URL(request.url);
  if (url.origin !== "https://offline-job-fixture.invalid") {
    throw Error("Unexpected outbound request: " + url.origin);
  }
  if (url.pathname === "/auth/v1/user") {
    return json({
      id: actor,
      email: "owner@example.test",
      email_confirmed_at: "2026-01-01T00:00:00Z",
    });
  }
  if (url.pathname === "/rest/v1/breeder_offline_jobs") {
    const id = url.searchParams.get("id")?.replace(/^eq\./, ""),
      found = id ? jobs.get(id) : undefined;
    if (request.method === "GET") {
      return json(
        request.headers.get("accept")?.includes("object")
          ? (found || null)
          : found
          ? [found]
          : [],
      );
    }
    const body = await request.json();
    if (request.method === "POST") {
      if (jobs.has(body.id)) {
        return json({ code: "23505", message: "Already exists" }, 409);
      }
      jobs.set(body.id, structuredClone(body));
      return json(null, 201);
    }
    if (request.method === "PATCH") {
      let allowed = !!found;
      for (const key of ["actor", "state", "started_at"]) {
        const filter = url.searchParams.get(key);
        if (!filter || !found) continue;
        if (filter.startsWith("eq.")) {
          allowed &&= String(found[key]) === filter.slice(3);
        } else if (filter.startsWith("in.(")) {
          allowed &&= filter.slice(4, -1).split(",").includes(found[key]);
        }
      }
      const or = url.searchParams.get("or");
      if (or && found) {
        allowed &&= or.includes("failed,queued")
          ? ["failed", "queued"].includes(found.state) ||
            found.state === "running" &&
              Date.parse(found.started_at) < Date.now() - 300000
          : found.state === "queued";
      }
      if (allowed && found) Object.assign(found, body);
      if (request.headers.get("accept")?.includes("object")) {
        return allowed ? json(found) : json({
          code: "PGRST116",
          details: "The result contains 0 rows",
          message: "No rows",
        }, 406);
      }
      return json(allowed ? [found] : []);
    }
  }
  if (url.pathname === "/rest/v1/rpc/breeder_offline_apply") {
    return json({ state: "applied", result: { status: "imported" } });
  }
  if (url.pathname.startsWith("/functions/v1/")) {
    const target = url.pathname.split("/").at(-1)!, body = await request.json();
    calls.push({ target, body });
    if (failService) return json({ error: "Fixture service unavailable" }, 503);
    if (target === "email-buyer-pedigree" && body.action === "prepare") {
      return json({
        owner_name: "Fixture",
        owner_email: "owner@example.test",
        pedigree: mismatchedPedigree ? { animal: { name: "Changed" } } : {},
      });
    }
    return json({ status: "imported", provider_accepted: true });
  }
  throw Error("Unexpected fixture path: " + url.pathname);
};
Deno.test("offline job HTTP lifecycle, delivery identity and safe retries", async (t) => {
  const originalFetch = globalThis.fetch, serve = Deno.serve;
  const env = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"]
    .map((k) => [k, Deno.env.get(k)] as const);
  try {
    Deno.env.set("SUPABASE_URL", "https://offline-job-fixture.invalid");
    Deno.env.set("SUPABASE_ANON_KEY", "fixture-public");
    Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fixture-service");
    globalThis.fetch = fixtureFetch;
    Object.defineProperty(Deno, "serve", {
      value: (fn: typeof handler) => {
        handler = fn;
      },
      configurable: true,
    });
    Object.assign(globalThis, {
      EdgeRuntime: { waitUntil: (task: Promise<unknown>) => tasks.push(task) },
    });
    await import("./index.ts");
    const request = async (body: unknown) => {
      const response = await handler(
        new Request(
          "https://offline-job-fixture.invalid/functions/v1/offline-jobs",
          {
            method: "POST",
            headers: {
              Authorization: "Bearer fixture-user",
              "Content-Type": "application/json",
            },
            body: JSON.stringify(body),
          },
        ),
      );
      await Promise.all(tasks.splice(0));
      return response;
    };
    await t.step(
      "accepts once and returns the original job after a lost response",
      async () => {
        const id = crypto.randomUUID(),
          body = {
            id,
            action: "enqueue",
            target: "import-ringmaster-records",
            payload: {
              action: "import",
              source: "club",
              profile_ids: ["fixture"],
            },
          };
        assert((await request(body)).status === 202);
        assert(jobs.get(id)?.state === "complete");
        const sent = calls.length;
        assert((await request(body)).status === 202);
        assert(calls.length === sent, "Duplicate external invocation");
        assert(
          calls.at(-1)?.body.offline_request_id === id,
          "Import did not receive its receipt identity",
        );
        assert(
          (await request({
            ...body,
            payload: { ...body.payload, profile_ids: ["changed"] },
          })).status === 409,
        );
      },
    );
    await t.step(
      "a failed job retries using its saved immutable payload",
      async () => {
        const id = crypto.randomUUID();
        failService = true;
        await request({
          id,
          action: "enqueue",
          target: "import-ringmaster-records",
          payload: { action: "lookup" },
        });
        assert(jobs.get(id)?.state === "failed");
        failService = false;
        await request({ id, action: "retry" });
        assert(jobs.get(id)?.state === "review");
      },
    );
    await t.step(
      "an interrupted invocation can be reclaimed after its lease",
      async () => {
        const id = crypto.randomUUID();
        jobs.set(id, {
          id,
          actor,
          target: "import-ringmaster-records",
          payload: { action: "lookup" },
          state: "running",
          started_at: new Date(Date.now() - 360000).toISOString(),
        });
        await request({ id, action: "retry" });
        assert(jobs.get(id)?.state === "review");
      },
    );
    await t.step("an active invocation cannot be started again", async () => {
      const id = crypto.randomUUID();
      jobs.set(id, {
        id,
        actor,
        target: "import-ringmaster-records",
        payload: { action: "lookup" },
        state: "running",
        started_at: new Date().toISOString(),
      });
      const before = calls.length;
      await request({ id, action: "retry" });
      assert(calls.length === before);
    });
    await t.step("cancels a request that has not started", async () => {
      const id = crypto.randomUUID();
      jobs.set(id, {
        id,
        actor,
        target: "import-ringmaster-records",
        payload: { action: "lookup" },
        state: "queued",
      });
      await request({ id, action: "cancel" });
      assert(jobs.get(id)?.state === "cancelled");
      const before = calls.length;
      await request({ id, action: "retry" });
      assert(calls.length === before);
    });
    await t.step("credentials never enter the server ledger", async () => {
      const id = crypto.randomUUID();
      assert(
        (await request({
          id,
          action: "enqueue",
          target: "import-ringmaster-records",
          payload: { action: "lookup", password: "do-not-store" },
        })).status === 400,
      );
      assert(!jobs.has(id));
    });
    await t.step(
      "sends only the approved email recipient and PDF",
      async () => {
        const id = crypto.randomUUID(),
          payload = {
            action: "send",
            request_id: id,
            animal_id: crypto.randomUUID(),
            recipient: "buyer@example.test",
            pdf: "approved-pdf",
            approved_snapshot: {},
            approved_owner_name: "Fixture",
            approved_owner_email: "owner@example.test",
          };
        await request({
          id,
          action: "enqueue",
          target: "email-buyer-pedigree",
          payload,
        });
        assert(jobs.get(id)?.state === "complete");
        assert(
          jobs.get(id)?.payload.pdf === undefined,
          "Completed PDF was not pruned",
        );
        assert(calls.at(-1)?.body.pdf === payload.pdf);
        assert(calls.at(-1)?.body.recipient === payload.recipient);
        const sent = calls.length;
        assert(
          (await request({
            id,
            action: "enqueue",
            target: "email-buyer-pedigree",
            payload,
          })).status === 202,
        );
        assert(
          calls.length === sent,
          "Pruning a completed PDF broke immutable retry reconciliation",
        );
      },
    );
    await t.step(
      "a changed pedigree retains the job and prevents sending",
      async () => {
        const id = crypto.randomUUID();
        mismatchedPedigree = true;
        const before = calls.filter((c) => c.body.action === "send").length;
        await request({
          id,
          action: "enqueue",
          target: "email-buyer-pedigree",
          payload: {
            action: "send",
            request_id: id,
            animal_id: crypto.randomUUID(),
            recipient: "buyer@example.test",
            pdf: "approved-pdf",
            approved_snapshot: {},
          },
        });
        assert(jobs.get(id)?.state === "failed");
        assert(calls.filter((c) => c.body.action === "send").length === before);
        mismatchedPedigree = false;
      },
    );
    await t.step(
      "another actor cannot reuse, cancel or retry this request identity",
      async () => {
        const id = crypto.randomUUID();
        jobs.set(id, { id, actor: crypto.randomUUID(), state: "queued" });
        assert((await request({ id, action: "cancel" })).status === 409);
      },
    );
  } finally {
    globalThis.fetch = originalFetch;
    Object.defineProperty(Deno, "serve", { value: serve, configurable: true });
    for (const [k, value] of env) {
      if (value === undefined) Deno.env.delete(k);
      else Deno.env.set(k, value);
    }
  }
});

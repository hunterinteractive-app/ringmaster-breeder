// Exercise the real handler against a mocked Auth/Data API, without a network or any Stripe key.
let handler: (req: Request) => Promise<Response>;
const originalServe = Deno.serve;
(Deno as any).serve = (fn: any) => {
  handler = fn;
  return {};
};
Deno.env.set("SUPABASE_URL", "https://billing-tests.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "synthetic-service-key");
Deno.env.set("SUPABASE_ANON_KEY", "synthetic-anon-key");
await import("./index.ts");
Deno.serve = originalServe;
const originalFetch = globalThis.fetch;
function assert(value: unknown, message: string) {
  if (!value) throw Error(message);
}
const user = {
  id: "e6102100-0000-4000-8000-000000000101",
  email: "owner@example.test",
  email_confirmed_at: "2026-01-01T00:00:00Z",
  app_metadata: {},
  user_metadata: {},
  aud: "authenticated",
  created_at: "2026-01-01T00:00:00Z",
};
async function run(input: any, valid = true) {
  const requests: string[] = [];
  globalThis.fetch = (async (url: any) => {
    const target = String(url);
    requests.push(target);
    if (target.includes("/auth/v1/user")) {
      return Response.json(valid ? user : { message: "Invalid JWT" }, {
        status: valid ? 200 : 401,
      });
    }
    if (target.includes("/rpc/breeder_is_super_admin")) {
      return Response.json(false);
    }
    if (target.includes("/rest/v1/users")) {
      return Response.json({
        id: "real-owner",
        is_active: true,
        auth_user_id: user.id,
      });
    }
    if (target.includes("/rest/v1/account_deletions")) {
      return Response.json(null);
    }
    if (target.includes("/rest/v1/breeder_billing_settings")) {
      return Response.json({ checkout_enabled: true });
    }
    return Response.json([]);
  }) as typeof fetch;
  try {
    const response = await handler(
      new Request("https://example.test/billing", {
        method: "POST",
        headers: {
          Authorization: "Bearer valid-user",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(input),
      }),
    );
    return { response, data: await response.json(), requests };
  } finally {
    globalThis.fetch = originalFetch;
  }
}
Deno.test("billing rejects an invalid or expired Auth identity before querying membership", async () => {
  const r = await run({ action: "status" }, false);
  assert(r.response.status === 401, "invalid token accepted");
  assert(r.requests.length === 1, "invalid identity reached database");
});
Deno.test("owner identity cannot be forged through the request body", async () => {
  const r = await run({ action: "status", owner: "victim-owner" });
  assert(r.response.status === 200, "status failed");
  assert(r.data.owner === "real-owner", "body overrode authenticated owner");
  assert(
    !r.requests.some((x) => x.includes("victim-owner")),
    "queried victim billing",
  );
});
Deno.test("admin grants require database-backed super-admin permission", async () => {
  const r = await run({
    action: "admin-grant",
    owner: "victim-owner",
    tier: "TOP",
    note: "forged",
    is_admin: true,
  });
  assert(r.response.status === 403, "non-admin accepted");
  assert(
    !r.requests.some((x) => x.includes("breeder_billing_transaction")),
    "grant attempted",
  );
});

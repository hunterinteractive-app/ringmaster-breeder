import { createClient } from "npm:@supabase/supabase-js@2.110.2";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
const fields = [
  "id",
  "first_name",
  "last_name",
  "display_name",
  "showing_name",
  "email",
  "phone",
  "address_line1",
  "address_line2",
  "city",
  "state",
  "zip",
  "birth_date",
  "arba_number",
  "type",
  "account_type",
  "group_members",
  "imported_from",
  "imported_source_id",
];
const publicProfile = (p: Record<string, unknown>) =>
  Object.fromEntries(fields.filter((k) => p[k] != null).map((k) => [k, p[k]]));
async function allRows(
  run: (
    from: number,
    to: number,
  ) => PromiseLike<{ data: Record<string, unknown>[] | null; error: unknown }>,
) {
  const rows: Record<string, unknown>[] = [];
  for (let start = 0;; start += 500) {
    const r = await run(start, start + 499);
    if (r.error) throw r.error;
    rows.push(...r.data ?? []);
    if ((r.data ?? []).length < 500) return rows;
  }
}
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ status: "error" }, 405);
  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization) return json({ status: "unauthorized" }, 401);
    const url = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: { user }, error } = await userClient.auth.getUser();
    if (error || !user?.email_confirmed_at || !user.email) {
      return json({ status: "unauthorized" }, 401);
    }
    const body = await req.json();
    if (!["lookup", "import"].includes(body.action ?? "lookup")) {
      return json({ status: "invalid_action" }, 400);
    }
    const email = user.email.trim().toLowerCase();
    const admin = createClient(
      url,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const offlineId = body.offline_request_id;
    if (
      offlineId != null &&
      !/^[a-f\d]{8}(-[a-f\d]{4}){3}-[a-f\d]{12}$/i.test(offlineId)
    ) return json({ status: "invalid_request_id" }, 400);
    const selection = {
      action: body.action,
      source: body.source,
      profile_ids: body.profile_ids,
      include_animals: body.include_animals === true,
      include_entries: body.include_entries === true,
      ring_id: body.ring_id ?? null,
    };
    // A lost response must return the first committed result even if the source
    // has since changed or is temporarily unavailable. Compare the selection.
    if (offlineId && body.action === "import") {
      const previous = await admin.from("breeder_offline_receipts").select(
        "payload_hash,result",
      ).eq("actor", user.id).eq("operation_id", offlineId).maybeSingle();
      if (previous.error) throw previous.error;
      if (previous.data) {
        const checked = await admin.rpc("breeder_offline_import_once", {
          p_actor: user.id,
          p_id: offlineId,
          p_selection: selection,
          p_source: "ringmaster_" + body.source,
          p_profiles: [],
          p_animals: [],
          p_entries: [],
          p_ring: body.ring_id ?? null,
        });
        if (checked.error) throw checked.error;
        return json(checked.data);
      }
    }
    const sourceClients: Record<string, typeof admin> = {};
    const matches: Record<string, unknown>[] = [];
    for (const source of ["show", "club"]) {
      const prefix = source.toUpperCase();
      const sourceUrl = Deno.env.get(prefix + "_SUPABASE_URL");
      const key = Deno.env.get(prefix + "_SUPABASE_SERVICE_ROLE_KEY");
      if (!sourceUrl || !key) {
        return json({ status: "configuration_required" }, 503);
      }
      const client = createClient(sourceUrl, key, {
        auth: { persistSession: false },
        global: {
          fetch: (input, init) =>
            fetch(input, { ...init, signal: AbortSignal.timeout(12000) }),
        },
      });
      sourceClients[source] = client;
      const { data, error } = await client.rpc(
        source === "show"
          ? "find_exhibitors_for_club_import"
          : "find_exhibitors_for_show_import",
        { p_email: email },
      );
      if (error) throw error;
      for (const p of data ?? []) {
        matches.push({ ...publicProfile(p), source, source_id: p.id });
      }
    }
    if ((body.action ?? "lookup") === "lookup") {
      return json({
        status: matches.length ? "matches" : "not_found",
        matches,
      });
    }
    if (
      !["show", "club"].includes(body.source) ||
      !Array.isArray(body.profile_ids) || !body.profile_ids.length
    ) return json({ status: "invalid_selection" }, 400);
    const selected = matches.filter((p) =>
      p.source === body.source && body.profile_ids.includes(p.id)
    );
    if (new Set(body.profile_ids).size !== selected.length) {
      return json({ status: "selection_not_allowed" }, 403);
    }
    // Re-run the verified-email lookup on every import; never trust client profile data.
    const sourceClient = sourceClients[body.source];
    let animals: Record<string, unknown>[] = [];
    let entries: Record<string, unknown>[] = [];
    if (body.source === "show") {
      const ids = selected.map((p) => p.id as string);
      if (body.include_animals) {
        animals = await allRows((from, to) =>
          sourceClient.from("animals").select(
            "id,exhibitor_id,name,tattoo,species,breed,variety,sex,birth_date",
          ).in("exhibitor_id", ids).eq("is_test", false).is("deleted_at", null)
            .order("id").range(from, to)
        );
      }
      if (body.include_entries) {
        entries = await allRows((from, to) =>
          sourceClient.from("entries").select(
            "id,animal_id,exhibitor_id,show_id,species,animal_name,tattoo,breed,variety,sex,class_name,status,placement,special_awards,is_shown,is_disqualified,disqualified_reason,result_status,is_fur,fur_placement,fur_award,shows(name,start_date,end_date,location_name),entry_awards(award_code)",
          ).in("exhibitor_id", ids).eq("is_test", false).order("id").range(
            from,
            to,
          )
        );
      }
    }
    // Materialize/link the existing legacy Breeder identity before the server write.
    const identity = await userClient.rpc("breeder_family_access", {
      p_action: "list",
    });
    if (identity.error) throw identity.error;
    const params = {
      p_actor: user.id,
      p_source: "ringmaster_" + body.source,
      p_profiles: selected.map(publicProfile),
      p_animals: animals,
      p_entries: entries,
      p_ring: body.ring_id ?? null,
    };
    const result = await admin.rpc(
      offlineId
        ? "breeder_offline_import_once"
        : "apply_breeder_cross_app_import",
      offlineId
        ? { ...params, p_id: offlineId, p_selection: selection }
        : params,
    );
    if (result.error) throw result.error;
    return json(result.data);
  } catch (e) {
    console.error(
      "Cross-app import failed",
      e instanceof Error ? e.name : "database_error",
    );
    return json({
      status: "error",
      message:
        "Unable to import. Check your selected Herd and records, then try again.",
    }, 503);
  }
});

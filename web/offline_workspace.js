/* Account-scoped record repository shared by the page and service worker.
 * Public assets remain in CacheStorage; private records/files/outbox use IDB. */
(function (root) {
  "use strict";
  const Q = root.BreederOfflineQuery || require("./offline_query.js");
  const A = root.BreederOfflineActions || require("./offline_actions.js");
  const json = (value, status = 200, headers = {}) =>
    new Response(JSON.stringify(value), {
      status,
      headers: { "Content-Type": "application/json", ...headers },
    });
  const uuid = () =>
    crypto.randomUUID
      ? crypto.randomUUID()
      : "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
        const v = crypto.getRandomValues(new Uint8Array(1))[0] & 15;
        return (c === "x" ? v : (v & 3) | 8).toString(16);
      });
  const decode = (raw) =>
    raw == null ? null : typeof raw === "string" ? JSON.parse(raw) : raw;
  const encode = (bytes) => {
    let value = "";
    for (let i = 0; i < bytes.length; i += 8192) {
      value += String.fromCharCode(...bytes.subarray(i, i + 8192));
    }
    return btoa(value);
  };
  const bytes = (value) => Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
  async function thumbnail(content, type) {
    const blob = new Blob([content], { type });
    let image, objectUrl;
    if (typeof createImageBitmap === "function") {
      image = await createImageBitmap(blob);
    } else if (typeof document !== "undefined") {
      image = new Image();
      objectUrl = URL.createObjectURL(blob);
      await new Promise((resolve, reject) => {
        image.onload = resolve;
        image.onerror = reject;
        image.src = objectUrl;
      });
    } else throw new Error("Reopen the app to prepare photo thumbnails");
    try {
      const scale = Math.min(1, 256 / Math.max(image.width, image.height)),
        width = Math.max(1, Math.round(image.width * scale)),
        height = Math.max(1, Math.round(image.height * scale));
      const canvas = typeof OffscreenCanvas !== "undefined"
        ? new OffscreenCanvas(width, height)
        : Object.assign(document.createElement("canvas"), { width, height });
      canvas.getContext("2d").drawImage(image, 0, 0, width, height);
      const result = canvas.convertToBlob
        ? await canvas.convertToBlob({ type: "image/jpeg", quality: 0.75 })
        : await new Promise((resolve) =>
          canvas.toBlob(resolve, "image/jpeg", 0.75)
        );
      if (!result) throw new Error("Unable to prepare this photo thumbnail");
      return new Uint8Array(await result.arrayBuffer());
    } finally {
      image.close?.();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    }
  }
  const jsonBody = async (response) => {
    const data = await response.json();
    if (!response.ok) {
      throw Object.assign(
        new Error(data.message || data.error || "Unable to reach the server"),
        { status: response.status, details: data },
      );
    }
    return data;
  };
  function create(api, options = {}) {
    let configuration = null, pulling = null, syncing = null;
    const notify = (...args) => {
        try {
          return Promise.resolve(options.notify?.(...args)).catch(() => {});
        } catch (_) {
          return Promise.resolve();
        }
      },
      fetcher = options.fetch || ((...args) => fetch(...args)),
      clock = options.now || Date.now;
    const read = async (k) => decode(await api.read(k));
    const scan = async (p) => decode(await api.scan(p));
    const commit = async (value) =>
      api.commit(
        JSON.stringify({ expected: {}, puts: {}, deletes: [], ...value }),
      );
    const prefix = () => {
      if (!configuration) throw new Error("Sign in to use downloaded records");
      return "v1:" + encodeURIComponent(configuration.account) + ":";
    };
    const key = (s) => prefix() + s;
    const cache = (s) => key("cache:" + s);
    const hash = async (value) =>
      Array.from(
        new Uint8Array(
          await crypto.subtle.digest(
            "SHA-256",
            new TextEncoder().encode(Q.canonical(value)),
          ),
        ),
        (v) => v.toString(16).padStart(2, "0"),
      ).join("");
    const assetHash = async (base64) =>
      Array.from(
        new Uint8Array(await crypto.subtle.digest("SHA-256", bytes(base64))),
        (v) => v.toString(16).padStart(2, "0"),
      ).join("");
    const responseKey = async (target, body) =>
      cache("external:" + await hash({ target, body }));
    const meta = async () => (await read(cache("workspace")))?.value || null;
    const operations = async () => {
      const rows = (await scan(key("op:"))).map((d) => d.value).sort((a, b) =>
        a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id)
      );
      const byId = new Map(rows.map((o) => [o.id, o])),
        visited = new Set(),
        visiting = new Set(),
        ordered = [];
      function visit(o) {
        if (visited.has(o.id)) return;
        if (visiting.has(o.id)) {
          throw new Error("The queue contains a dependency cycle");
        }
        visiting.add(o.id);
        for (const id of [o.depends_on, ...(o.requires || [])]) {
          const parent = byId.get(id);
          if (parent) visit(parent);
        }
        visiting.delete(o.id);
        visited.add(o.id);
        ordered.push(o);
      }
      rows.forEach(visit);
      return ordered;
    };
    const authHeaders = () => ({
      apikey: configuration.apiKey,
      Authorization: "Bearer " + configuration.token,
      "Content-Type": "application/json",
    });
    async function boundedFetch(input, init = {}, duration = 25000) {
      const controller = new AbortController(),
        external = init.signal ||
          (input instanceof Request ? input.signal : null);
      const abort = () => controller.abort();
      if (external?.aborted) abort();
      else external?.addEventListener("abort", abort, { once: true });
      const timer = setTimeout(abort, duration);
      try {
        const response = await fetcher(input, {
          ...init,
          signal: controller.signal,
        });
        // Keep the deadline through the response body: weak service can stop
        // after headers, leaving an upload acknowledgement half downloaded.
        const body =
          [204, 205, 304].includes(response.status) || init.method === "HEAD"
            ? null
            : await response.arrayBuffer();
        return new Response(body, {
          status: response.status,
          statusText: response.statusText,
          headers: response.headers,
        });
      } finally {
        clearTimeout(timer);
        external?.removeEventListener("abort", abort);
      }
    }
    async function network(path, body, method = "POST", headers = {}) {
      const url = new URL(configuration.url + path);
      url.searchParams.set("__breeder_network", "1");
      return boundedFetch(url.href, {
        method,
        headers: { ...authHeaders(), ...headers },
        body: body == null ? undefined : JSON.stringify(body),
      });
    }
    async function setup(config) {
      if (Q.equal(config, configuration)) return;
      configuration = config;
      if (config) {
        // Credentials are isolated from the account document/export namespace.
        // No refresh token is saved for background work. Expiry requires reopen.
        await commit({
          puts: {
            "workspace:active": { ...config, expires: config.expires || 0 },
          },
        });
      } else await commit({ deletes: ["workspace:active"] });
      notify();
    }
    async function loadConfiguration() {
      configuration = (await read("workspace:active"))?.value || null;
      return configuration;
    }
    async function tables(names = null) {
      const docs = names
        ? (await Promise.all(
          names.map((t) =>
            read(cache("table:" + t)).then((d) =>
              d ? { ...d, key: cache("table:" + t) } : null
            )
          ),
        )).filter(Boolean)
        : await scan(cache("table:"));
      const values = Object.fromEntries(
        docs.map((d) => [d.key.slice(cache("table:").length), d.value.rows]),
      );
      const projected = (await operations()).map((op) => ({
        ...op,
        mutations: (op.mutations || []).filter((m) =>
          Object.hasOwn(values, m.table)
        ),
      }));
      return Q.project(values, projected);
    }
    async function requireLease() {
      const verified = (await read(key("access")))?.value?.verified_at;
      const age = clock() - Date.parse(verified || "");
      if (!Number.isFinite(age) || age < 0 || age >= 7 * 86400000) {
        throw new Error(
          "Reconnect to verify access before making more offline changes. Saved records and recovery remain available.",
        );
      }
    }
    async function queue(request, settings = {}) {
      await requireLease();
      A.validate(request);
      const id = settings.id || uuid(),
        created_at = new Date(clock()).toISOString();
      for (let attempt = 0; attempt < 10; attempt++) {
        const epoch = await read(key("queue-version")), opKey = key("op:" + id);
        const prior = await read(opKey);
        if (prior) return prior.value.result;
        const pending = await operations(), data = await tables();
        const prepared = await A.prepare(
          data,
          request,
          id,
          created_at,
          configuration.account,
        );
        const storedRequest = Q.clone(request), assets = {};
        if (request.type === "file" && typeof request.base64 === "string") {
          const ref = "cache:pending-file:" + id,
            sha256 = await assetHash(request.base64);
          assets[key(ref)] = {
            base64: request.base64,
            type: request.content_type,
            sha256,
          };
          delete storedRequest.base64;
          storedRequest.asset_ref = ref;
          storedRequest.asset_hash = sha256;
        }
        if (
          request.type === "external" && typeof request.body.pdf === "string"
        ) {
          const ref = "cache:pending-file:" + id,
            sha256 = await assetHash(request.body.pdf);
          assets[key(ref)] = {
            base64: request.body.pdf,
            type: "application/pdf",
            sha256,
          };
          delete storedRequest.body.pdf;
          storedRequest.body.pdf_asset_ref = ref;
          storedRequest.body.pdf_asset_hash = sha256;
        }
        const makeOperation = (operationId, request, prepared) => {
          const touched = new Set(
            prepared.mutations.map((m) =>
              m.table + ":" + Q.identity(m.table, m.row)
            ),
          );
          const payload = Q.canonical({ ...request, base64: undefined }),
            first = prepared.mutations[0];
          const existing = first &&
            data[first.table]?.find((r) =>
              Q.identity(first.table, r) === Q.identity(first.table, first.row)
            );
          const saleId = first?.row.sale_id ||
            (first?.table === "animal_sales" ? first.row.id : null);
          const sale = data.animal_sales?.find((s) => s.id === saleId);
          const scope = first?.row.animal_id || existing?.animal_id ||
            sale?.animal_id || request.body?.animal_id ||
            (typeof prepared.result === "string" ? prepared.result : null) ||
            (first?.table === "animals" ? first.row.id : null) ||
            request.body?.p_id || request.body?.p_ring ||
            request.path?.split("/")[0] || request.paths?.[0]?.split("/")[0] ||
            request.target || request.bucket;
          const requires = pending.filter((o) =>
            o.animal_id === scope ||
            o.request?.type === "file" && payload.includes(o.request.path) ||
            (o.mutations || []).some((m) =>
              touched.has(m.table + ":" + Q.identity(m.table, m.row)) ||
              Q.keyFields(m.table).some((k) =>
                typeof m.row[k] === "string" && payload.includes(m.row[k])
              ) ||
              request.target === "show-connection" &&
                request.body.herd_ids?.includes(
                  m.row.ring_id || m.snapshot?.ring_id,
                )
            )
          ).map((o) => o.id);
          const animal = data.animals?.find((a) => a.id === scope) ||
            prepared.mutations.find((m) =>
              m.table === "animals" && m.row.id === scope
            )?.row;
          const label = settings.label || (animal
            ? [animal.name, animal.tattoo].filter(Boolean).join(" • ")
            : null) ||
            first?.row.name || existing?.name || request.body?.recipient ||
            "Saved action";
          return {
            id: operationId,
            kind: "request",
            animal_id: settings.scope || scope,
            label,
            request,
            ...prepared,
            requires,
            state: "pending",
            created_at,
          };
        };
        const newOperations = [];
        if (
          request.type === "table" && request.method === "POST" &&
          Array.isArray(request.body) && request.body.length > 1 &&
          ["animal_weights", "animal_health_records"].includes(request.target)
        ) {
          for (const mutation of prepared.mutations) {
            const body = request.body.find((r) =>
              r.id === mutation.row.id
            );
            const op = makeOperation(mutation.row.id, { ...request, body }, {
              mutations: [mutation],
              expects: [],
              result: [mutation.row],
            });
            newOperations.push(op);
            pending.push(op);
          }
        } else newOperations.push(makeOperation(id, storedRequest, prepared));
        const puts = { ...assets, [key("queue-version")]: {} },
          expected = { [key("queue-version")]: epoch?.version ?? null };
        for (const [ref, asset] of Object.entries(assets)) {
          const existing = await read(ref);
          if (existing && !Q.equal(existing.value, asset)) {
            throw new Error(
              "A different attachment already uses this saved identity",
            );
          }
          expected[ref] = existing?.version ?? null;
        }
        for (const op of newOperations) {
          puts[key("op:" + op.id)] = op;
          expected[key("op:" + op.id)] = null;
        }
        const saved = await commit({ expected, puts });
        if (saved) {
          await notify("queued");
          return prepared.result;
        }
      }
      throw new Error(
        "Another tab is saving. Try again; your form is retained.",
      );
    }
    async function refresh(options = {}) {
      if (pulling) {
        const result = await pulling;
        if (options.fullFiles === true) {
          await downloadFiles(true);
          return status();
        }
        return result;
      }
      pulling = (async () => {
        const account = configuration.account;
        await commit({
          puts: {
            [cache("download")]: {
              state: "downloading",
              started_at: new Date(clock()).toISOString(),
            },
          },
        });
        notify();
        try {
          const user = await jsonBody(
            await network("/auth/v1/user", null, "GET"),
          );
          if (user.id !== account) {
            throw new Error("Sign in again before downloading");
          }
          let committed = false;
          for (let attempt = 0; attempt < 6 && !committed; attempt++) {
            const manifest = await read(cache("workspace")),
              epoch = await read(key("queue-version"));
            const previous = manifest?.value;
            const data = await jsonBody(
              await network("/rest/v1/rpc/breeder_offline_snapshot", {
                p_versions: previous?.versions || {},
              }),
            );
            if (account !== configuration?.account) {
              throw new Error("The signed-in account changed");
            }
            if (data.protocol !== 1) {
              throw new Error(
                "This server needs the Phase 1 offline migration",
              );
            }
            const at = new Date(clock()).toISOString(), puts = {};
            for (const [table, rows] of Object.entries(data.tables)) {
              puts[cache("table:" + table)] = { rows };
            }
            puts[cache("workspace")] = {
              protocol: 1,
              versions: data.versions,
              downloaded_at: at,
              table_counts: { ...previous?.table_counts, ...data.counts },
              files: data.files || [],
              membership: data.membership,
              admin: data.admin === true,
            };
            puts[key("access")] = { verified_at: at };
            puts[cache("family")] = data.membership;
            puts[cache("deletion")] = {
              pending: (data.tables.account_deletions ||
                (await tables()).account_deletions || []).length > 0,
            };
            puts[cache("download")] = { state: "records_ready", at };
            for (const job of data.tables.breeder_offline_jobs || []) {
              puts[cache("job:" + job.id)] = job;
              if (["complete", "review"].includes(job.state) && job.result) {
                puts[await responseKey(job.target, job.payload)] = {
                  data: job.result,
                  downloaded_at: job.completed_at,
                };
              }
            }
            // One transaction replaces changed tables and their version manifest.
            // Missing/deleted rows disappear only with the complete server table.
            committed = await commit({
              expected: {
                [cache("workspace")]: manifest?.version ?? null,
                [key("queue-version")]: epoch?.version ?? null,
              },
              puts,
            });
          }
          if (!committed) {
            throw new Error(
              "Saved work changed during the download. Try Sync again; your drafts are retained.",
            );
          }
          notify();
          if (!options.skipFiles) {
            await downloadFiles(options.fullFiles === true);
          }
          return await status();
        } catch (error) {
          await commit({
            puts: {
              [cache("download")]: { state: "failed", message: error.message },
            },
          });
          notify();
          throw error;
        }
      })().finally(() => pulling = null);
      return pulling;
    }
    async function downloadFiles(full) {
      const metadata = await meta();
      if (!metadata) return;
      const files = metadata.files || [];
      let completed = 0;
      const failed = [];
      for (const f of files) {
        if (!full && !["animal_photos", "offline_results"].includes(f.bucket)) {
          continue;
        }
        const fileKey = cache(
          "file:" + f.bucket + ":" + f.path + ":" +
            (full || f.bucket !== "animal_photos" ? "full" : "thumb"),
        );
        const existing = await read(fileKey);
        if (existing?.value?.updated_at === f.updated_at) {
          completed++;
          continue;
        }
        try {
          const url = new URL(
            configuration.url + "/storage/v1/object/authenticated/" +
              encodeURIComponent(f.bucket) + "/" +
              f.path.split("/").map(encodeURIComponent).join("/"),
          );
          url.searchParams.set("__breeder_network", "1");
          const r = await boundedFetch(url.href, { headers: authHeaders() });
          if (!r.ok) throw new Error("File download failed");
          let content = new Uint8Array(await r.arrayBuffer()),
            type = r.headers.get("content-type") || "application/octet-stream";
          if (!full && f.bucket === "animal_photos") {
            content = await thumbnail(content, type);
            type = "image/jpeg";
          }
          await commit({
            puts: {
              [fileKey]: {
                base64: encode(content),
                type,
                updated_at: f.updated_at,
                size: content.length,
              },
            },
          });
          completed++;
        } catch (_) {
          failed.push(
            encodeURIComponent(f.bucket) + "/" +
              f.path.split("/").map(encodeURIComponent).join("/"),
          );
        }
        await commit({
          puts: {
            [cache("files-status")]: {
              completed,
              failed,
              total: files.filter((f) =>
                full || ["animal_photos", "offline_results"].includes(f.bucket)
              ).length,
              full,
            },
          },
        });
        notify();
      }
      await commit({
        puts: {
          [cache("files-status")]: {
            completed,
            failed,
            total: files.filter((f) =>
              full || ["animal_photos", "offline_results"].includes(f.bucket)
            ).length,
            full,
          },
        },
      });
      notify();
    }
    async function file(bucket, path, full = false) {
      // Pending uploads are already durable and immediately available locally.
      const op = (await operations()).find((o) =>
        o.request?.type === "file" && o.request.bucket === bucket &&
        o.request.path === path
      );
      if (op) {
        const asset = op.request.base64
          ? { base64: op.request.base64, type: op.request.content_type }
          : (await read(key(op.request.asset_ref)))?.value;
        return asset || null;
      }
      return (await read(
        cache("file:" + bucket + ":" + path + ":" + (full ? "full" : "thumb")),
      ))?.value ||
        (await read(cache("file:" + bucket + ":" + path + ":full")))?.value ||
        null;
    }
    async function status() {
      const m = await meta();
      return {
        ready: !!m,
        downloaded_at: m?.downloaded_at,
        counts: m?.table_counts,
        download: (await read(cache("download")))?.value,
        files: (await read(cache("files-status")))?.value,
        optional_bytes: (m?.files || []).reduce(
          (n, f) => n + (Number(f.size) || 0),
          0,
        ),
        jobs: (await scan(cache("job:"))).map((d) => d.value),
        busy: (await scan(cache("inflight:"))).some((d) =>
          d.value.until > clock()
        ),
        paused: !!await read(key("paused")),
      };
    }
    async function pause(paused) {
      if (!paused) {
        await commit({ deletes: [key("paused")] });
        await notify((await operations()).length ? "queued" : "changed");
        return true;
      }
      for (let n = 0; n < 8; n++) {
        const activity = await read(key("activity"));
        if ((await status()).busy) return false;
        if (
          await commit({
            expected: { [key("activity")]: activity?.version ?? null },
            puts: { [key("paused")]: { paused: true }, [key("activity")]: {} },
          })
        ) {
          await notify();
          return true;
        }
      }
      return false;
    }
    function identity(request) {
      const token = request.headers.get("Authorization")?.replace(
        /^Bearer /i,
        "",
      );
      if (!token || !configuration) return false;
      try {
        const part = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
        return JSON.parse(atob(part)).sub === configuration.account;
      } catch (_) {
        return false;
      }
    }
    async function handle(request) {
      if (!configuration || !identity(request) || !(await meta())) return null;
      const url = new URL(request.url), base = configuration.url;
      if (!url.href.startsWith(base + "/")) return null;
      const path = url.pathname.slice(
        new URL(base).pathname.replace(/\/$/, "").length,
      );
      try {
        if (path.startsWith("/rest/v1/")) {
          const target = path.slice("/rest/v1/".length);
          if (target.startsWith("rpc/")) {
            const name = target.slice(4),
              body = request.method === "GET"
                ? Object.fromEntries(url.searchParams)
                : await request.clone().json();
            if (
              name === "breeder_family_access" &&
              (body.p_action == null || body.p_action === "list")
            ) return json((await meta()).membership);
            if (name === "breeder_family_access") {
              const response = await boundedFetch(request.clone());
              if (response.ok) await refresh({ skipFiles: true });
              return response;
            }
            if (name === "breeder_license_status") {
              if (!(await meta()).membership.households.some(h => h.owner_user_id === body.p_owner)) {
                return json({message:"Family access required",code:"42501"},403);
              }
              return json(A.licenseStatus(await tables(["license_tiers","user_licenses","farms","animals","breeder_license_usage"]),body.p_owner,clock()));
            }
            if (name === "breeder_is_super_admin") {
              return json((await meta()).admin === true);
            }
            if (name === "breeder_pedigree_snapshot") {
              return json(
                await pedigree(
                  await tables(["animals", "animal_weights"]),
                  body.p_animal_id,
                ),
              );
            }
            if (name === "import_rabbit_register" || name === "import_kintraks" || name === "link_rabbit_register_history" || name === "use_herd_contact" || ["link_litter_offspring", "save_managed_show_result", "save_production_measurement", "save_herd_contact", "save_wool_settings", "link_rabbit_register_wool"].includes(name)) {
              // Import review/commit requires the authoritative server. Never
              // queue a potentially partial export or reuse an old preview.
              const response = await boundedFetch(request.clone());
              const directWrite = ["use_herd_contact", "link_litter_offspring", "save_managed_show_result", "save_production_measurement", "save_herd_contact", "save_wool_settings", "link_rabbit_register_wool"].includes(name);
              if (response.ok && (body.p_commit === true || directWrite)) {
                const result = await response.clone().json().catch(() => null);
                if (result?.status === "imported" || result?.status === "linked" || directWrite) {
                  await refresh({ skipFiles: true }).catch(() => {});
                }
              }
              return response;
            }
            if (name === "import_global_pedigree_with_sales") {
              if (body.p_commit === true) {
                return await queuedExternal("global-pedigree-import", body);
              }
              const saved =
                (await read(await responseKey("global-pedigree-review", body)))
                  ?.value;
              if (saved) return json(saved.data);
              // Review requires the latest authoritative import matching rules.
              try {
                const response = await boundedFetch(request.clone());
                if (response.ok) {
                  const value = await response.clone().json();
                  await commit({
                    puts: {
                      [await responseKey("global-pedigree-review", body)]: {
                        data: value,
                      },
                    },
                  });
                }
                return response;
              } catch (_) {
                return json({
                  code: "BREEDER_OFFLINE",
                  message:
                    "The collection is saved. Reconnect to review the import before committing it.",
                }, 409);
              }
            }
            if (!A.rpcs.has(name)) return null;
            return json(await queue({ type: "rpc", target: name, body }));
          }
          const data = await tables(
            Q.tablesFor(target, url.searchParams.get("select") || "*"),
          );
          if (!Object.hasOwn(data, target)) return null;
          let rows, count;
          if (request.method === "GET" || request.method === "HEAD") {
            ({ rows, count } = Q.query(data, target, url.searchParams));
          } else {
            if (!A.writable[target]) return null;
            const body = request.method === "DELETE"
              ? null
              : await request.clone().json();
            rows = await queue({
              type: "table",
              target,
              method: request.method,
              query: [...url.searchParams],
              body,
              upsert: request.headers.get("Prefer")?.includes(
                "resolution=merge-duplicates",
              ) === true,
            });
            count = rows.length;
          }
          if (request.headers.get("Accept")?.includes("object")) {
            if (rows.length !== 1) {
              return json({
                code: "PGRST116",
                message:
                  "The downloaded result does not contain exactly one record",
                details: rows.length + " rows",
              }, 406);
            }
            return json(rows[0]);
          }
          return json(rows, 200, {
            "content-range": "0-" + Math.max(0, count - 1) + "/" + count,
          });
        }
        if (
          path.startsWith("/storage/v1/object/") && request.method === "POST" &&
          !path.includes("/sign/")
        ) {
          const [bucket, ...parts] = path.slice("/storage/v1/object/".length)
            .split("/");
          if (!["animal_photos", "health_attachments"].includes(bucket)) {
            return null;
          }
          let content,
            type = request.headers.get("content-type") ||
              "application/octet-stream";
          if (type.startsWith("multipart/")) {
            const form = await request.clone().formData();
            const blob = [...form.values()].find((v) => typeof v !== "string");
            if (!blob) throw new Error("No attachment selected");
            content = new Uint8Array(await blob.arrayBuffer());
            type = blob.type;
          } else content = new Uint8Array(await request.clone().arrayBuffer());
          if (content.length > 10 * 1024 * 1024) {
            throw new Error("Choose an attachment smaller than 10 MB");
          }
          await queue({
            type: "file",
            bucket,
            path: decodeURIComponent(parts.join("/")),
            base64: encode(content),
            content_type: type,
          });
          return json({ Key: bucket + "/" + parts.join("/"), Id: uuid() });
        }
        if (
          path.startsWith("/storage/v1/object/") && request.method === "DELETE"
        ) {
          const bucket = path.slice("/storage/v1/object/".length).split("/")[0];
          const text = await request.clone().text(),
            body = text ? JSON.parse(text) : {};
          await queue({ type: "file_delete", bucket, paths: body.prefixes });
          return json([]);
        }
        if (path.startsWith("/functions/v1/") && request.method === "POST") {
          const target = path.slice("/functions/v1/".length);
          if (
            ![
              "email-buyer-pedigree",
              "global-pedigree",
              "import-ringmaster-records",
              "show-reports",
              "show-calendar",
              "show-connection",
              "sync-breed-catalog",
            ].includes(target)
          ) return null;
          const text = await request.clone().text(),
            body = text ? JSON.parse(text) : {};
          if (
            target === "email-buyer-pedigree" && body.action === "send" &&
            body.approved_snapshot
          ) return await queuedExternal(target, body);
          if (
            target === "import-ringmaster-records" && body.action === "import"
          ) return await queuedExternal(target, body);
          if (target === "show-reports" && body.action === "download") {
            return await queuedExternal(target, body);
          }
          if (target === "show-connection") {
            if (body.action === "sync") {
              return await queuedExternal(target, body);
            }
            if (body.action !== "status") {
              const response = await boundedFetch(request.clone());
              if (response.ok) {
                await refresh({ skipFiles: true }).catch(() => {});
              }
              return response;
            }
            const data = await tables(["users", "farms", "show_connections"]),
              own = data.users.find((u) =>
                u.auth_user_id === configuration.account
              );
            return json({
              connection: data.show_connections?.find((c) =>
                c.user_id === configuration.account
              ) || null,
              herds: data.farms.filter((f) =>
                f.owner_id === own?.id
              ).map((f) => ({ id: f.id, name: f.name })),
            });
          }
          if (
            target === "show-reports" &&
            ["enable", "disable"].includes(body.action)
          ) {
            const response = await boundedFetch(request.clone());
            if (response.ok) await refresh({ skipFiles: true }).catch(() => {});
            return response;
          }
          const responseName = await responseKey(
            target,
            target === "show-connection" ? { action: "status" } : body,
          );
          const saved = (await read(responseName))?.value;
          if (saved && body.action !== "refresh") {
            return json({ ...saved.data, downloaded_at: saved.downloaded_at });
          }
          try {
            const controller = new AbortController(),
              timer = setTimeout(
                () => controller.abort(),
                target === "global-pedigree" ? 25000 : 3000,
              );
            let response;
            try {
              response = await boundedFetch(
                new Request(request.clone(), { signal: controller.signal }),
              );
            } finally {
              clearTimeout(timer);
            }
            if (response.ok) {
              if (target !== "global-pedigree") {
                await commit({
                  puts: {
                    [responseName]: {
                      data: await response.clone().json(),
                      downloaded_at: new Date(clock()).toISOString(),
                    },
                  },
                });
              }
              return response;
            }
            if (response.status < 500) return response;
          } catch (_) {
            /* Save a durable intent after an actual transport failure. */
          }
          if (target === "show-connection") {
            return json({
              error:
                "Connection status has not been downloaded. Reconnect once to prepare it.",
            }, 409);
          }
          if (target === "global-pedigree") {
            return await queuedExternal(target, {
              username: body.username,
              requires_sign_in: true,
            });
          }
          return await queuedExternal(target, body);
        }
        return null;
      } catch (error) {
        return json({
          code: "BREEDER_OFFLINE",
          message: error.message,
          details: "Your downloaded records and pending work are retained.",
        }, 409);
      }
    }
    async function queuedExternal(target, body) {
      const pending = (await operations()).find((o) =>
        o.request?.type === "external" && o.request.target === target &&
        Q.equal(o.request.body, body)
      );
      const jobs = (await status()).jobs;
      const accepted = jobs.find((j) =>
        j.target === target &&
        ["queued", "running", "needs_input"].includes(j.state) &&
        Q.equal(j.payload, body)
      );
      const id = pending?.id || accepted?.id || body.request_id || uuid();
      if (!pending && !accepted) {
        await queue({ type: "external", target, body }, { id });
      }
      return json({
        queued: true,
        request_id: id,
        error:
          "Request saved on this device. Open Sync to track it after reconnection.",
      }, 202);
    }
    async function pedigree(data, id) {
      const slots = [
        "animal",
        "sire",
        "dam",
        "sire_sire",
        "sire_dam",
        "dam_sire",
        "dam_dam",
        "gg1",
        "gg2",
        "gg3",
        "gg4",
        "gg5",
        "gg6",
        "gg7",
        "gg8",
      ];
      const out = {},
        visit = (aid, slot, depth) => {
          if (!aid || depth > 3) return;
          const a = data.animals.find((r) => r.id === aid);
          if (!a) {
            throw new Error(
              "This pedigree relationship has not been downloaded",
            );
          }
          const weights = (data.animal_weights || []).filter((w) =>
            w.animal_id === aid
          ).sort((a, b) => b.recorded_at.localeCompare(a.recorded_at));
          out[slots[slot]] = { ...a, weight: weights[0]?.weight ?? null };
          if (depth < 3) {
            visit(a.sire_id, slot * 2 + 1, depth + 1);
            visit(a.dam_id, slot * 2 + 2, depth + 1);
          }
        };
      visit(id, 0, 0);
      return out;
    }
    async function push(op) {
      A.validate(op.request);
      const original = await read(key("op:" + op.id));
      if (!original) return;
      const leaseKey = cache("inflight:" + op.id), owner = uuid();
      let claimed = false;
      for (let attempt = 0; attempt < 100; attempt++) {
        if (!await read(key("op:" + op.id))) return;
        const activity = await read(key("activity")),
          paused = await read(key("paused")),
          lease = await read(leaseKey);
        if (paused) {
          throw Object.assign(
            new Error(
              "Uploads are paused for a recovery export. Open Sync to resume them.",
            ),
            { status: 503 },
          );
        }
        if (!(lease?.value.until > clock())) {
          claimed = await commit({
            expected: {
              [key("op:" + op.id)]: original.version,
              [key("activity")]: activity?.version ?? null,
              [key("paused")]: null,
              [leaseKey]: lease?.version ?? null,
            },
            puts: {
              [leaseKey]: { owner, until: clock() + 180000 },
              [key("activity")]: {},
            },
          });
        }
        if (claimed) break;
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      if (!claimed) {
        throw Object.assign(
          new Error(
            "Another tab is confirming this operation. Retry to check delivery.",
          ),
          { status: 503 },
        );
      }
      try {
        const r = Q.clone(op.request);
        async function savedAsset(ref, expectedHash) {
          if (
            typeof ref !== "string" ||
            !/^cache:pending-file:[a-f\d-]{36}$/i.test(ref)
          ) {
            throw Object.assign(
              new Error("Invalid saved attachment reference"),
              { status: 409 },
            );
          }
          const asset = (await read(key(ref)))?.value;
          if (!asset || await assetHash(asset.base64) !== expectedHash) {
            throw Object.assign(
              new Error(
                "This saved attachment is missing or damaged. Restore the original recovery file; your other drafts are retained.",
              ),
              { status: 409 },
            );
          }
          return asset;
        }
        if (r.type === "file" && r.asset_ref) {
          r.base64 = (await savedAsset(r.asset_ref, r.asset_hash)).base64;
        }
        if (r.type === "external" && r.body.pdf_asset_ref) {
          const asset = await savedAsset(
            r.body.pdf_asset_ref,
            r.body.pdf_asset_hash,
          );
          r.body.pdf = asset.base64;
          delete r.body.pdf_asset_ref;
          delete r.body.pdf_asset_hash;
        }
        let result;
        if (r.type === "file") {
          const url = new URL(
            configuration.url + "/storage/v1/object/" +
              encodeURIComponent(r.bucket) + "/" +
              r.path.split("/").map(encodeURIComponent).join("/"),
          );
          url.searchParams.set("__breeder_network", "1");
          const response = await boundedFetch(url.href, {
            method: "POST",
            headers: {
              ...authHeaders(),
              "Content-Type": r.content_type,
              "x-upsert": "false",
            },
            body: bytes(r.base64),
          });
          if (!response.ok) {
            // A lost upload acknowledgement may leave this exact immutable path.
            const saved = await boundedFetch(
              url.href.replace("/object/", "/object/authenticated/"),
              { headers: authHeaders() },
            );
            if (
              !saved.ok ||
              !Q.equal([...new Uint8Array(await saved.arrayBuffer())], [
                ...bytes(r.base64),
              ])
            ) {
              throw Object.assign(
                new Error(
                  "Unable to confirm the attachment upload. Your file is retained.",
                ),
                { status: response.status },
              );
            }
          }
          result = {};
        } else if (r.type === "file_delete") {
          result = await jsonBody(
            await network("/storage/v1/object/" + r.bucket, {
              prefixes: r.paths,
            }, "DELETE"),
          );
        } else if (r.type === "external") {
          result = await jsonBody(
            await network("/functions/v1/offline-jobs", {
              action: "enqueue",
              id: op.id,
              target: r.target,
              payload: r.body,
            }),
          );
        } else {
          result = await jsonBody(
            await network("/rest/v1/rpc/breeder_offline_apply", {
              p_operation: {
                id: op.id,
                seed: op.seed || op.id,
                request: r,
                expects: op.expects,
                mutations: op.mutations,
              },
            }),
          );
          if (result.state === "conflict") {
            throw Object.assign(
              new Error(
                "This record changed on another device. Review both versions in Sync.",
              ),
              { conflict: result },
            );
          }
        }
        // Acknowledge the base projection and queue entry in the same CAS batch.
        for (let n = 0; n < 8; n++) {
          const current = await read(key("op:" + op.id));
          if (!current) return;
          if (!Q.equal(current.value, original.value)) return;
          const epoch = await read(key("queue-version")), puts = {};
          const tableNames = new Set((op.mutations || []).map((m) => m.table));
          const expected = {
            [key("op:" + op.id)]: current.version,
            [key("queue-version")]: epoch?.version ?? null,
          };
          const metadata = await read(cache("workspace"));
          if (metadata) {
            expected[cache("workspace")] = metadata.version;
            const value = Q.clone(metadata.value);
            for (const table of tableNames) value.versions[table] = null;
            puts[cache("workspace")] = value;
          }
          for (const table of tableNames) {
            const d = await read(cache("table:" + table));
            expected[cache("table:" + table)] = d?.version ?? null;
            const updated = Q.project({ [table]: d?.value.rows || [] }, [{
              mutations: op.mutations.filter((m) => m.table === table),
            }]);
            // Authoritative table data is pulled after the queue is delivered.
            puts[cache("table:" + table)] = { rows: updated[table] };
          }
          puts[key("queue-version")] = {};
          if (r.type === "file") {
            puts[cache("file:" + r.bucket + ":" + r.path + ":full")] = {
              base64: r.base64,
              type: r.content_type,
              size: bytes(r.base64).length,
            };
          }
          if (r.type === "external") {
            const payload = { ...op.request.body };
            delete payload.pdf;
            delete payload.pdf_asset_ref;
            delete payload.pdf_asset_hash;
            delete payload.approved_snapshot;
            puts[cache("job:" + op.id)] = {
              id: op.id,
              target: r.target,
              payload,
              result: result.result,
              state: result.state || "queued",
              error: result.error,
            };
          }
          const assetRefs = [
            op.request.asset_ref,
            op.request.body?.pdf_asset_ref,
          ].filter(Boolean);
          const deletes = [
            key("op:" + op.id),
            ...assetRefs.map(key),
            ...(r.type === "file_delete"
              ? r.paths.flatMap((path) =>
                ["thumb", "full"].map((kind) =>
                  cache("file:" + r.bucket + ":" + path + ":" + kind)
                )
              )
              : []),
          ];
          if (await commit({ expected, puts, deletes })) {
            notify();
            return;
          }
        }
        throw Object.assign(
          new Error(
            "Another tab changed the queue. Retry to confirm delivery.",
          ),
          { status: 503 },
        );
      } finally {
        const active = await read(leaseKey);
        if (active?.value.owner === owner) {
          await commit({
            expected: { [leaseKey]: active.version },
            deletes: [leaseKey],
          });
        }
      }
    }
    async function sync() {
      if (syncing) return syncing;
      syncing = (async () => {
        const queue = await operations();
        let retryError;
        for (const op of queue) {
          if (op.kind !== "request" || op.state !== "pending") continue;
          if (
            (op.requires || []).some((id) => queue.some((p) => p.id === id))
          ) {
            const remaining = await operations();
            if (op.requires.some((id) => remaining.some((p) => p.id === id))) {
              continue;
            }
          }
          try {
            await push(op);
          } catch (error) {
            if (
              error.conflict ||
              error.status >= 400 && error.status < 500 &&
                ![401, 408, 429].includes(error.status)
            ) {
              const d = await read(key("op:" + op.id));
              if (d) {
                await commit({
                  expected: { [key("op:" + op.id)]: d.version },
                  puts: {
                    [key("op:" + op.id)]: {
                      ...d.value,
                      state: error.conflict ? "conflict" : "rejected",
                      message: error.message,
                      ...(error.conflict ? { server: error.conflict } : {}),
                    },
                  },
                });
              }
              notify();
            } else {
              retryError = error;
              break;
            }
          }
        }
        if (!(await operations()).length) await refresh().catch(() => {});
        if (retryError) throw retryError;
      })().finally(() => syncing = null);
      return syncing;
    }
    async function resolve(id, keep) {
      const doc = await read(key("op:" + id));
      if (!doc) return;
      const leaseKey = cache("inflight:" + id),
        lease = await read(leaseKey),
        activity = await read(key("activity"));
      if (lease?.value.until > clock()) {
        throw new Error(
          "This request has started. Wait for its result before changing it.",
        );
      }
      const op = doc.value, epoch = await read(key("queue-version"));
      const expected = {
        [key("op:" + id)]: doc.version,
        [key("queue-version")]: epoch?.version ?? null,
        [leaseKey]: lease?.version ?? null,
        [key("activity")]: activity?.version ?? null,
      };
      const puts = { [key("queue-version")]: {}, [key("activity")]: {} },
        deletes = [key("op:" + id)];
      const latest = op.server?.current || [];
      // Show the chosen server version immediately, including deletions. This
      // base and the queue decision are one transaction across all open tabs.
      for (const table of new Set(latest.map((v) => v.table))) {
        const stored = await read(cache("table:" + table));
        expected[cache("table:" + table)] = stored?.version ?? null;
        let rows = Q.clone(stored?.value.rows || []);
        for (const current of latest.filter((v) => v.table === table)) {
          rows = rows.filter((r) =>
            !Object.entries(current.key).every(([k, v]) => Q.equal(r[k], v))
          );
          if (current.row) rows.push(current.row);
        }
        puts[cache("table:" + table)] = { rows };
      }
      const metadata = await read(cache("workspace"));
      if (metadata) {
        expected[cache("workspace")] = metadata.version;
        const value = Q.clone(metadata.value);
        for (const m of op.mutations || []) value.versions[m.table] = null;
        puts[cache("workspace")] = value;
      }
      const pending = await operations();
      if (keep) {
        const request = Q.clone(op.request),
          expects = Q.clone(op.expects),
          mutations = Q.clone(op.mutations);
        for (const e of expects) {
          const current = latest.find((r) =>
            r.table === e.table && Q.equal(r.key, e.key)
          );
          if (!current?.row) {
            throw new Error(
              "The record was deleted or access ended. Export your draft for recovery.",
            );
          }
          for (const k of Object.keys(e.before)) {
            e.before[k] = current.row[k] ?? null;
          }
          const mutation = mutations.find((m) =>
            m.table === e.table &&
            Object.entries(e.key).every(([k, v]) => Q.equal(m.row[k], v))
          );
          if (mutation) {
            mutation.before = Q.clone(e.before);
            mutation.snapshot = Q.clone(current.row);
          }
        }
        if (request.target === "save_breeding_tracking") {
          const tracking = latest.find((r) => r.table === "breeding_tracking");
          if (tracking) request.body.p_revision = tracking.row.revision;
        }
        const replacement = {
          ...op,
          id: uuid(),
          seed: op.seed || op.id,
          request,
          expects,
          mutations,
          state: "pending",
          created_at: new Date(clock()).toISOString(),
        };
        delete replacement.server;
        delete replacement.message;
        puts[key("op:" + replacement.id)] = replacement;
        expected[key("op:" + replacement.id)] = null;
        for (const dependent of pending) {
          if (dependent.requires?.includes(id)) {
            const stored = await read(key("op:" + dependent.id));
            expected[key("op:" + dependent.id)] = stored.version;
            puts[key("op:" + dependent.id)] = {
              ...dependent,
              requires: dependent.requires.map((v) =>
                v === id ? replacement.id : v
              ),
            };
          }
        }
      } else {
        if (pending.some((o) => o.requires?.includes(id))) {
          throw new Error(
            "Later changes depend on this draft. Export and resolve those changes before discarding it.",
          );
        }
        deletes.push(
          ...[op.request.asset_ref, op.request.body?.pdf_asset_ref].filter(
            Boolean,
          ).map(key),
        );
      }
      if (!await commit({ expected, puts, deletes })) {
        throw new Error("The queue changed. Review the current version.");
      }
      await notify(keep ? "queued" : "changed");
    }
    async function cancelJob(id) {
      const result = await jsonBody(
        await network("/functions/v1/offline-jobs", { id, action: "cancel" }),
      );
      const prior = await read(cache("job:" + id));
      if (prior) {
        await commit({
          puts: {
            [cache("job:" + id)]: { ...prior.value, state: result.state },
          },
        });
      }
      notify();
    }
    async function retryJob(id) {
      const job = (await read(cache("job:" + id)))?.value;
      if (!job) throw new Error("Download this request status first");
      await jsonBody(
        await network("/functions/v1/offline-jobs", { action: "retry", id }),
      );
      await refresh();
    }
    return {
      setup,
      loadConfiguration,
      configuration: () => configuration,
      meta,
      tables,
      queue,
      refresh,
      downloadFiles,
      file,
      status,
      handle,
      push,
      sync,
      resolve,
      network,
      operations,
      identity,
      pause,
      cancelJob,
      retryJob,
    };
  }
  root.BreederOfflineWorkspace = { create, uuid, encode, bytes };
  if (typeof module !== "undefined") {
    module.exports = root.BreederOfflineWorkspace;
  }
})(globalThis);

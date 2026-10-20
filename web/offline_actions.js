/* Deterministic local projections for Breeder's transactional actions. The
 * server runs the existing validated RPC in a receipt transaction on replay. */
(function (root) {
  "use strict";
  const Q = root.BreederOfflineQuery || require("./offline_query.js");
  const writable = {
    farms: ["name"],
    users: ["display_name", "address", "city", "state", "zip", "phone"],
    animals: [
      "ring_id",
      "name",
      "tattoo",
      "species",
      "breed",
      "variety",
      "sex",
      "dob",
      "status",
      "notes",
      "registration_number",
      "grand_champion_number",
      "sire_id",
      "dam_id",
      "color_details",
      "genotype",
      "leg_details",
      "legs",
      "pedigree_only",
      "photo_path",
    ],
    animal_weights: ["animal_id", "weight", "recorded_at"],
    animal_health_records: [
      "animal_id",
      "record_type",
      "title",
      "description",
      "administered_date",
      "expires_date",
      "veterinarian",
      "medication",
      "dosage",
      "readminister_date",
      "attachment_url",
      "retention",
    ],
    breeding_settings: [
      "ring_id",
      "species",
      "gestation_min",
      "gestation_max",
      "palpation_min",
      "palpation_max",
      "nesting_day",
      "weaning_min",
      "weaning_max",
    ],
    pedigree_drafts: ["ring_id", "data", "updated_at"],
    global_pedigree_import_drafts: ["ring_id", "account", "data"],
    animal_sales: [
      "animal_id",
      "ring_id",
      "animal_name",
      "asking_cents",
      "buyer_name",
      "buyer_email",
      "buyer_phone",
      "buyer_address",
      "notes",
      "status",
      "sale_cents",
      "sale_date",
    ],
    animal_sale_payments: [
      "sale_id",
      "kind",
      "amount_cents",
      "method",
      "reference",
      "notes",
      "paid_on",
    ],
  };
  const related = [
    "species",
    "breed",
    "variety",
    "color_details",
    "genotype",
    "sex",
    "dob",
    "status",
    "sire_id",
    "dam_id",
  ];
  const methods = new Set(["POST", "PATCH", "DELETE"]);
  const rpcs = new Set([
    "create_animal_with_color_details",
    "create_breeder_ring",
    "delete_empty_breeder_ring",
    "record_breeding_with_parents",
    "save_breeding_tracking",
    "create_litter_animals",
    "save_pedigree_draft",
  ]);
  const row = (tables, table, id, field = "id") =>
    Q.tableRows(tables, table).find((r) => r[field] === id);
  function defaults(table, value, now) {
    const base = [
        "farms",
        "users",
        "animals",
        "animal_weights",
        "animal_health_records",
        "breeding_records",
        "animal_sales",
        "animal_sale_payments",
        "animal_sale_history",
      ].includes(table)
      ? { created_at: now }
      : {};
    if (table === "animals") {
      Object.assign(base, {
        status: "active",
        pedigree_only: false,
        revision: 1,
        color_details: {},
        leg_details: "",
        sire_id: null,
        dam_id: null,
      });
    }
    if (table === "pedigree_drafts") {
      Object.assign(base, { updated_at: now, saved_animal_id: null });
    }
    if (table === "animal_sales") {
      Object.assign(base, {
        status: "for_sale",
        version: 1,
        asking_cents: null,
        sale_cents: null,
        buyer_name: "",
        buyer_email: "",
        buyer_phone: "",
        buyer_address: "",
        notes: "",
      });
    }
    if (table === "animal_weights") base.recorded_at = now;
    return { ...base, ...value };
  }
  async function ids(seed) {
    let sequence = 0;
    return async () => {
      const data = new TextEncoder().encode(seed + ":" + ++sequence);
      const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
      const h = Array.from(
        bytes.slice(0, 16),
        (v) => v.toString(16).padStart(2, "0"),
      ).join("");
      return [
        h.slice(0, 8),
        h.slice(8, 12),
        h.slice(12, 16),
        h.slice(16, 20),
        h.slice(20),
      ].join("-");
    };
  }
  function patchMutation(table, before, changes) {
    const compare = new Set(
      Object.keys(changes).filter((k) =>
        !["updated_at", "created_at"].includes(k)
      ),
    );
    if (table === "animals" && related.some((k) => compare.has(k))) {
      related.forEach((k) => compare.add(k));
    }
    if (table === "animal_sales") {
      [
        "status",
        "sale_cents",
        "asking_cents",
        "buyer_name",
        "animal_id",
        "ring_id",
      ].forEach((k) => compare.add(k));
    }
    return {
      table,
      action: "update",
      snapshot: Q.clone(before),
      row: {
        ...Object.fromEntries(Q.keyFields(table).map((k) => [k, before[k]])),
        ...changes,
      },
      before: Object.fromEntries(
        [...compare].map((k) => [k, before[k] ?? null]),
      ),
    };
  }
  const deletionBaseline = (row) =>
    Object.fromEntries(
      Object.entries(row).filter(([k]) =>
        !["created_at", "updated_at"].includes(k)
      ),
    );
  function validate(request) {
    if (!request || typeof request !== "object") {
      throw new Error("Invalid saved request");
    }
    if (request.type === "rpc") {
      if (
        !rpcs.has(request.target) || !request.body ||
        typeof request.body !== "object" || Array.isArray(request.body)
      ) throw new Error("This action requires a connection");
    } else if (request.type === "table") {
      if (!writable[request.target] || !methods.has(request.method)) {
        throw new Error("This action requires a connection");
      }
      if (
        request.method === "DELETE" &&
        ![
          "animal_health_records",
          "pedigree_drafts",
          "global_pedigree_import_drafts",
        ].includes(request.target)
      ) throw new Error("This deletion requires a connection");
      const values = Array.isArray(request.body)
        ? request.body
        : request.body
        ? [request.body]
        : [];
      for (const v of values) {
        if (
          !v ||
          Object.keys(v).some((k) =>
            k !== "id" && !writable[request.target].includes(k)
          )
        ) throw new Error("Unsupported saved fields");
      }
    } else if (request.type === "file" || request.type === "file_delete") {
      if (request.type === "file_delete") {
        if (
          !["animal_photos", "health_attachments"].includes(request.bucket) ||
          !Array.isArray(request.paths) || request.paths.some((p) =>
            typeof p !== "string" || !p || p.split("/").some((s) =>
              s === ".." || s === "."
            )
          )
        ) throw new Error("Invalid saved attachment deletion");
        return;
      }
      if (
        !["animal_photos", "health_attachments"].includes(request.bucket) ||
        typeof request.path !== "string" || !request.path ||
        request.path.split("/").some((s) => s === ".." || s === ".") ||
        !(typeof request.base64 === "string" ||
          typeof request.asset_ref === "string" &&
            /^cache:pending-file:[a-f\d-]{36}$/i.test(request.asset_ref))
      ) throw new Error("Invalid saved attachment");
    } else if (request.type === "external") {
      if (
        ![
          "email-buyer-pedigree",
          "global-pedigree",
          "global-pedigree-import",
          "import-ringmaster-records",
          "show-reports",
          "show-calendar",
          "show-connection",
          "sync-breed-catalog",
        ].includes(request.target) || !request.body ||
        typeof request.body !== "object"
      ) throw new Error("Unsupported queued service");
      const unsafe = (v) =>
        v && typeof v === "object" &&
        Object.entries(v).some(([k, value]) =>
          /^(password|authorization|access_token|refresh_token|service_role_key|secret)$/i
            .test(k) || unsafe(value)
        );
      if (unsafe(request.body)) {
        throw new Error("Credentials cannot be stored in the queue");
      }
    } else throw new Error("Unsupported saved request");
    if (Q.canonical(request).length > 16 * 1024 * 1024) {
      throw new Error("This saved operation is too large");
    }
  }
  async function prepare(tables, request, id, now, actor) {
    validate(request);
    const changes = [], next = await ids(id);
    const add = (table, r) => {
      const v = defaults(table, r, now);
      if (table === "pedigree_drafts" && actor) v.user_id = actor;
      changes.push({ table, action: "insert", row: v });
      return v;
    };
    const update = (table, old, v) => {
      if (!old) {
        throw new Error(
          "These records have not been downloaded or are no longer available",
        );
      }
      changes.push(patchMutation(table, old, v));
    };
    const animal = async (v, weight) => {
      const a = add("animals", { ...v, id: await next() });
      if (
        !["rabbit", "cavy"].includes(a.species) ||
        !["Buck", "Doe", "Boar", "Sow"].includes(a.sex)
      ) throw new Error("Check the species and sex");
      if (weight != null) {
        if (!Number.isFinite(Number(weight)) || Number(weight) <= 0) {
          throw new Error("Weight must be positive");
        }
        add("animal_weights", {
          id: await next(),
          animal_id: a.id,
          weight: Number(weight),
          recorded_at: now,
        });
      }
      return a;
    };
    let result = null;
    if (request.type === "table") {
      const table = request.target,
        params = new URLSearchParams(request.query || []);
      if (request.method === "POST") {
        result = [];
        for (
          const v of Array.isArray(request.body) ? request.body : [request.body]
        ) {
          if (
            ["animals", "pedigree_drafts", "animal_sales", "breeding_settings"]
              .includes(table) && !row(tables, "farms", v.ring_id)
          ) {
            throw new Error(
              "Herd access changed. Reconnect before creating this record.",
            );
          }
          if (
            ["animal_weights", "animal_health_records"].includes(table) &&
            !row(tables, "animals", v.animal_id)
          ) {
            throw new Error(
              "Animal access changed. Reconnect before creating this record.",
            );
          }
          const keys = Q.keyFields(table);
          if (keys.length === 1 && keys[0] === "id" && !v.id) {
            v.id = await next();
          }
          const old = Q.tableRows(tables, table).find((r) =>
            Q.identity(table, r) === Q.identity(table, v)
          );
          if (old && request.upsert) {
            update(table, old, v);
            result.push({ ...old, ...v });
          } else if (old) {
            if (!Object.entries(v).every(([k, val]) => Q.equal(old[k], val))) {
              throw new Error("A different record already uses this identity");
            }
            result.push(old);
          } else result.push(add(table, v));
        }
      } else {
        const matches = Q.query(
          tables,
          table,
          new URLSearchParams([...params].filter(([k]) => k !== "select")),
        ).rows;
        if (!matches.length) {
          throw new Error("The record changed. Reload it before saving.");
        }
        result = [];
        for (const old of matches) {
          if (request.method === "DELETE") {
            changes.push({
              table,
              action: "delete",
              row: old,
              before: deletionBaseline(old),
            });
            result.push(old);
          } else {
            update(table, old, request.body);
            result.push({ ...old, ...request.body });
          }
        }
      }
    } else if (request.type === "rpc") {
      const p = request.body;
      switch (request.target) {
        case "create_breeder_ring": {
          const farm = add("farms", {
            id: await next(),
            name: p.p_name,
            owner_id: p.p_owner_id,
            is_demo: false,
          });
          result = farm.id;
          break;
        }
        case "delete_empty_breeder_ring": {
          const farm = row(tables, "farms", p.p_ring);
          if (!farm) throw new Error("Download this herd before deleting it");
          for (
            const name of [
              "animals",
              "pedigree_drafts",
              "global_pedigree_import_drafts",
              "global_pedigree_animals",
              "global_pedigree_history",
              "animal_sales",
            ]
          ) {
            if (Q.tableRows(tables, name).some((v) => v.ring_id === p.p_ring)) {
              throw new Error(
                "This herd contains records. Move or retain those records before deleting the herd.",
              );
            }
          }
          changes.push({
            table: "farms",
            action: "delete",
            row: farm,
            before: deletionBaseline(farm),
          });
          for (
            const settings of Q.tableRows(tables, "breeding_settings").filter(
              (v) => v.ring_id === p.p_ring,
            )
          ) {
            changes.push({
              table: "breeding_settings",
              action: "delete",
              row: settings,
              before: deletionBaseline(settings),
            });
          }
          result = p.p_ring;
          break;
        }
        case "create_animal_with_color_details": {
          const a = await animal({
            ring_id: p.p_ring_id,
            name: p.p_name,
            tattoo: p.p_tattoo,
            species: p.p_species,
            breed: p.p_breed,
            variety: p.p_variety,
            sex: p.p_sex,
            status: p.p_status,
            dob: p.p_dob,
            registration_number: p.p_registration,
            grand_champion_number: p.p_gc,
            sire_id: p.p_sire_id,
            dam_id: p.p_dam_id,
            color_details: p.p_color_details,
          }, p.p_weight);
          result = a.id;
          break;
        }
        case "record_breeding_with_parents": {
          const parents = {};
          for (const v of p.p_parents) {
            parents[v.id] = (await animal({
              ...v,
              id: undefined,
              ring_id: p.p_ring,
              status: "active",
              pedigree_only: true,
            }, v.weight)).id;
          }
          for (const v of p.p_records) {
            add("breeding_records", {
              id: await next(),
              ...v,
              sire_id: parents[v.sire_id] || v.sire_id,
              dam_id: parents[v.dam_id] || v.dam_id,
              status: "active",
            });
          }
          result = p.p_records.length;
          break;
        }
        case "save_breeding_tracking": {
          const old = row(tables, "breeding_tracking", p.p_id, "breeding_id");
          if ((old?.revision || 0) !== p.p_revision) {
            throw new Error("This litter changed. Reload before saving.");
          }
          const data = {
            ...p.p_data,
            breeding_id: p.p_id,
            revision: p.p_revision + 1,
          };
          if (old) update("breeding_tracking", old, data);
          else add("breeding_tracking", data);
          update("breeding_records", row(tables, "breeding_records", p.p_id), {
            status: data.status,
          });
          result = "";
          break;
        }
        case "create_litter_animals": {
          const b = row(tables, "breeding_records", p.p_id),
            t = row(tables, "breeding_tracking", p.p_id, "breeding_id");
          if (
            !b || !t || !t.weaned || t.weaned !== p.p_young.length ||
            t.status === "cancelled"
          ) {
            throw new Error(
              "Record the matching weaning count before creating offspring",
            );
          }
          if (
            Q.tableRows(tables, "breeding_offspring").some((v) =>
              v.breeding_id === p.p_id
            )
          ) throw new Error("Offspring records already exist");
          const dam = row(tables, "animals", b.dam_id);
          for (const y of p.p_young) {
            const sex = dam.species === "cavy"
              ? (y.sex === "M" ? "Boar" : "Sow")
              : (y.sex === "M" ? "Buck" : "Doe");
            const a = await animal({
              ...y,
              ring_id: dam.ring_id,
              species: dam.species,
              sex,
              dob: t.birth_date,
              sire_id: b.sire_id,
              dam_id: b.dam_id,
              status: "active",
            }, null);
            changes.push({
              table: "breeding_offspring",
              action: "insert",
              row: { animal_id: a.id, breeding_id: p.p_id },
            });
          }
          update("breeding_tracking", t, {
            status: "completed",
            revision: t.revision + 1,
          });
          update("breeding_records", b, { status: "completed" });
          result = p.p_young.length;
          break;
        }
        case "save_pedigree_draft": {
          const d = row(tables, "pedigree_drafts", p.p_draft);
          if (!d) throw new Error("Download this pedigree draft first");
          if (d.saved_animal_id) {
            result = d.saved_animal_id;
            break;
          }
          const { nodes, root: rootKey, species } = d.data,
            linked = {},
            created = {};
          const visit = (key, path = []) => {
            if (!nodes[key] || path.includes(key)) {
              throw new Error("Check missing ancestors and pedigree cycles");
            }
            for (const field of ["sire", "dam"]) {
              if (nodes[key][field]) visit(nodes[key][field], [...path, key]);
            }
          };
          visit(rootKey);
          // jsonb_each uses byte-length/key ordering. Match the server's ID stream.
          const ordered = Object.keys(nodes).sort((a, b) =>
            new TextEncoder().encode(a).length -
              new TextEncoder().encode(b).length || (a < b ? -1 : a > b ? 1 : 0)
          );
          for (const key of ordered) {
            const n = nodes[key];
            if (n.existing_id) linked[key] = n.existing_id;
            else {
              const a = await animal({
                ...n,
                ring_id: d.ring_id,
                species,
                status: "active",
                pedigree_only: key !== rootKey,
                revision: 2,
              }, n.weight);
              linked[key] = a.id;
              created[key] = a;
            }
          }
          for (const [key, a] of Object.entries(created)) {
            a.sire_id = linked[nodes[key].sire] || null;
            a.dam_id = linked[nodes[key].dam] || null;
          }
          update("pedigree_drafts", d, { saved_animal_id: linked[rootKey] });
          result = linked[rootKey];
          break;
        }
      }
    }
    // Mirror the existing sales triggers for immediate offline views. Derived
    // mutations are display projections; only the server's real triggers write
    // those tables when the original payment/listing is replayed.
    if (
      request.type === "table" &&
      ["animal_sales", "animal_sale_payments"].includes(request.target)
    ) {
      const projected = Q.project(tables, [{ mutations: changes }]);
      const saleIds = new Set(
        request.target === "animal_sales"
          ? changes.map((m) => m.row.id)
          : changes.map((m) => m.row.sale_id),
      );
      for (const saleId of saleIds) {
        const sale = row(projected, "animal_sales", saleId);
        if (!sale) {
          throw new Error("Download the sale before recording a payment");
        }
        const old = row(tables, "animal_sales", saleId),
          a = row(projected, "animals", sale.animal_id);
        if (!old && a) {
          sale.animal_name = [a.name, a.tattoo].filter(Boolean).join(" - ") ||
            "Unnamed animal";
        }
        const payments = projected.animal_sale_payments.filter((p) =>
          p.sale_id === saleId
        );
        const paid = payments.reduce(
          (n, p) => n + (p.kind === "refund" ? -1 : 1) * Number(p.amount_cents),
          0,
        );
        const price = sale.sale_cents ?? sale.asking_cents;
        if (paid < 0 || price != null && paid > price) {
          throw new Error("The payment or refund exceeds the sale balance");
        }
        if (
          ["for_sale", "reserved"].includes(sale.status) &&
          sale.buyer_name?.trim()
        ) {
          if (sale.sale_cents > 0 && paid === sale.sale_cents) {
            sale.status = "sold";
            sale.sale_date = sale.sale_date || payments.map((p) =>
              p.paid_on || now.slice(0, 10)
            ).sort().at(-1) || now.slice(0, 10);
          } else sale.status = "reserved";
        }
        if (sale.status === "cancelled" && paid !== 0) {
          throw new Error("Record refunds before cancelling the sale");
        }
        if (old?.status === "sold" && sale.status !== "sold") {
          throw new Error("Completed sales remain in history");
        }
        if (old?.status === "cancelled") {
          throw new Error("Cancelled listings are read-only");
        }
        const salesUpdate = old
          ? patchMutation("animal_sales", old, {
            status: sale.status,
            sale_date: sale.sale_date ?? null,
            version: (old.version || 1) + 1,
            animal_name: sale.animal_name,
          })
          : {
            table: "animal_sales",
            action: "update",
            row: {
              id: saleId,
              status: sale.status,
              animal_name: sale.animal_name,
            },
          };
        changes.push({ ...salesUpdate, derived: true });
        if (sale.status === "sold" && a) {
          changes.push({
            ...patchMutation("animals", a, { status: "sold" }),
            derived: true,
          });
        }
        changes.push({
          table: "animal_sale_history",
          action: "insert",
          row: {
            id: await next(),
            sale_id: saleId,
            event: request.target === "animal_sale_payments"
              ? request.body.kind
              : old
              ? "updated"
              : "listed",
            created_at: now,
            details: { before: old || null, after: sale },
          },
          derived: true,
        });
      }
      if (Array.isArray(result)) {
        const projected = Q.project(tables, [{ mutations: changes }]);
        result = result.map((r) =>
          projected[request.target].find((v) =>
            Q.identity(request.target, v) === Q.identity(request.target, r)
          ) || r
        );
      }
    }
    // Strip fields used only in a form from provisional animal rows.
    for (const m of changes) {
      if (m.table === "animals") {
        for (const k of ["existing_id", "weight", "sire", "dam"]) {
          delete m.row[k];
        }
      }
    }
    const expects = changes.filter((m) => m.before).map((m) => ({
      table: m.table,
      key: Object.fromEntries(Q.keyFields(m.table).map((k) => [k, m.row[k]])),
      before: m.before,
    }));
    return { mutations: changes, result, expects };
  }
  const api = {
    writable,
    rpcs,
    related,
    validate,
    prepare,
    ids,
    defaults,
    patchMutation,
  };
  root.BreederOfflineActions = api;
  if (typeof module !== "undefined") module.exports = api;
})(globalThis);

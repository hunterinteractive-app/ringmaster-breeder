/* Local queries over an account's authorized download. Never infer an absent
 * table to be empty. Unsupported queries fail explicitly instead of losing data. */
(function (root) {
  "use strict";
  const clone = (v) => JSON.parse(JSON.stringify(v));
  const equal = (a, b) => canonical(a) === canonical(b);
  function canonical(v) {
    if (Array.isArray(v)) return "[" + v.map(canonical).join(",") + "]";
    if (v && typeof v === "object") {
      return "{" + Object.keys(v).sort().map((k) =>
        JSON.stringify(k) + ":" + canonical(v[k])
      ).join(",") + "}";
    }
    return JSON.stringify(v);
  }
  function split(text, delimiter = ",") {
    let depth = 0, quoted = false, escaped = false, start = 0;
    const out = [];
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      if (c === '"' && !escaped) quoted = !quoted;
      if (!quoted) {
        if (c === "(") depth++;
        if (c === ")") depth--;
        if (c === delimiter && depth === 0) {
          out.push(text.slice(start, i));
          start = i + 1;
        }
      }
      escaped = c === "\\" && !escaped;
    }
    out.push(text.slice(start));
    return out.filter(Boolean);
  }
  const relations = {
    animals: {
      sire: ["animals", "sire_id", "id", false],
      dam: ["animals", "dam_id", "id", false],
      animal_weights: ["animal_weights", "id", "animal_id", true],
      animal_health_records: ["animal_health_records", "id", "animal_id", true],
    },
    breeds: { varieties: ["varieties", "id", "breed_id", true] },
    user_licenses: {
      license_tiers: ["license_tiers", "tier_code", "code", false],
    },
    animal_health_records: { animal: ["animals", "animal_id", "id", false] },
    breeding_records: {
      dam: ["animals", "dam_id", "id", false],
      sire: ["animals", "sire_id", "id", false],
      tracking: ["breeding_tracking", "id", "breeding_id", false],
      offspring: ["breeding_offspring", "id", "breeding_id", true],
    },
    breeding_tracking: {
      breeding: ["breeding_records", "breeding_id", "id", false],
    },
    breeding_offspring: { animal: ["animals", "animal_id", "id", false] },
    animal_sales: { animal: ["animals", "animal_id", "id", false] },
  };
  const keys = {
    global_pedigree_import_drafts: ["auth_user_id"],
    breeding_settings: ["ring_id", "species"],
    breeding_tracking: ["breeding_id"],
    breeding_offspring: ["animal_id"],
    license_tiers: ["code"],
    breeder_license_usage: ["owner_id"],
  };
  const keyFields = (table) => keys[table] || ["id"];
  const identity = (table, row) =>
    keyFields(table).map((k) => String(row[k])).join("|");
  function tableRows(tables, table) {
    if (!Object.hasOwn(tables, table)) {
      throw new Error("These records have not been downloaded: " + table);
    }
    return tables[table];
  }
  function project(tables, operations) {
    const result = clone(tables);
    for (const op of operations) {
      // Retain the user's local version while a conflict awaits review.
      for (const m of op.mutations || []) {
        const rows = tableRows(result, m.table);
        const index = rows.findIndex((r) =>
          identity(m.table, r) === identity(m.table, m.row)
        );
        if (m.action === "delete") { if (index >= 0) rows.splice(index, 1); }
        else if (index < 0) {
          rows.push({ ...clone(m.snapshot || {}), ...clone(m.row) });
        } else rows[index] = { ...rows[index], ...clone(m.row) };
      }
      if (op.kind === "animal" && result.animals) {
        const row = result.animals.find((r) => r.id === op.animal_id);
        if (row) Object.assign(row, op.changes);
      }
      if (
        op.kind === "weight" && result.animal_weights &&
        !result.animal_weights.some((r) => r.id === op.row.id)
      ) result.animal_weights.push(clone(op.row));
    }
    return result;
  }
  function selectParts(select) {
    return split(select || "*").map((s) => {
      const i = s.indexOf("(");
      if (i < 0) return { field: s };
      if (!s.endsWith(")")) throw new Error("Unsupported offline selection");
      const head = s.slice(0, i), colon = head.indexOf(":");
      return {
        alias: (colon < 0 ? head : head.slice(0, colon)).split("!")[0],
        target: (colon < 0 ? head : head.slice(colon + 1)).split("!")[0],
        head,
        children: s.slice(i + 1, -1),
        inner: head.includes("!inner"),
      };
    });
  }
  function relation(table, part) {
    let r = relations[table]?.[part.alias] || relations[table]?.[part.target];
    if (!r && table === "animals" && part.target === "animals") {
      const field = part.head.includes("sire_id")
        ? "sire_id"
        : part.head.includes("dam_id")
        ? "dam_id"
        : null;
      if (field) r = ["animals", field, "id", false];
    }
    if (!r) {
      throw new Error(
        "Relationship not available offline: " + table + "." + part.alias,
      );
    }
    return r;
  }
  function tablesFor(table, select = "*", seen = new Set()) {
    seen.add(table);
    for (const p of selectParts(select)) {
      if (!p.field) {
        const [target] = relation(table, p);
        tablesFor(target, p.children, seen);
      }
    }
    return [...seen];
  }
  function expand(
    tables,
    table,
    row,
    select,
    params,
    prefix = "",
    indices = new Map(),
  ) {
    const result = {}, parts = selectParts(select);
    for (const p of parts) {
      if (p.field === "*") Object.assign(result, row);
      else if (p.field) {
        const [alias, field] = p.field.includes(":")
          ? p.field.split(":")
          : [p.field, p.field];
        result[alias] = row[field];
      } else {
        const [target, left, right, many] = relation(table, p);
        const indexKey = target + ":" + right;
        if (!indices.has(indexKey)) {
          const index = new Map();
          for (const child of tableRows(tables, target)) {
            const value = child[right];
            if (!index.has(value)) index.set(value, []);
            index.get(value).push(child);
          }
          indices.set(indexKey, index);
        }
        let matches = row[left] == null
          ? []
          : indices.get(indexKey).get(row[left]) || [];
        matches = matches.map((r) =>
          expand(
            tables,
            target,
            r,
            p.children,
            params,
            prefix + p.alias + ".",
            indices,
          )
        ).filter(Boolean);
        matches = matches.filter((r) =>
          filters(r, params, prefix + p.alias + ".")
        );
        matches = orderLimit(matches, params, prefix + p.alias + ".");
        if (p.inner && matches.length === 0) return null;
        result[p.alias] = many ? matches : matches[0] || null;
      }
    }
    return result;
  }
  function valuesAt(row, path) {
    if (!path.length) return Array.isArray(row) ? row : [row];
    if (Array.isArray(row)) return row.flatMap((r) => valuesAt(r, path));
    return valuesAt(row?.[path[0]], path.slice(1));
  }
  function literal(value) {
    if (value === "null") return null;
    if (value === "true") return true;
    if (value === "false") return false;
    if (value.startsWith('"')) {
      try {
        return JSON.parse(value);
      } catch (_) {}
    }
    return value;
  }
  function compare(value, expression) {
    if (expression.startsWith("not.")) {
      return !compare(value, expression.slice(4));
    }
    const i = expression.indexOf("."),
      op = expression.slice(0, i),
      text = expression.slice(i + 1),
      expected = literal(text);
    if (i < 0) throw new Error("Unsupported offline filter");
    if (op === "is") {
      return expected === null ? value == null : value === expected;
    }
    if (op === "in") {
      return split(text.slice(1, -1)).some((v) =>
        String(value) === String(literal(v))
      );
    }
    if (value == null || expected == null) return false;
    if (op === "eq") return String(value) === String(expected);
    if (op === "neq") return String(value) !== String(expected);
    const other = typeof value === "number"
      ? Number(expected)
      : String(expected);
    if (op === "gt") return value > other;
    if (op === "gte") return value >= other;
    if (op === "lt") return value < other;
    if (op === "lte") return value <= other;
    if (op === "like" || op === "ilike") {
      const pattern = String(expected).replace(/[.+?^${}()|[\]\\]/g, "\\$&")
        .replace(/[%*]/g, ".*").replace(/_/g, ".");
      return new RegExp("^" + pattern + "$", op === "ilike" ? "i" : "").test(
        String(value),
      );
    }
    throw new Error("Unsupported offline filter: " + op);
  }
  function logical(row, expression) {
    if (expression.startsWith("and(") || expression.startsWith("or(")) {
      const and = expression.startsWith("and("), start = and ? 4 : 3;
      const results = split(expression.slice(start, -1)).map((e) =>
        logical(row, e)
      );
      return and ? results.every(Boolean) : results.some(Boolean);
    }
    const match = expression.match(
      /^(.+?)\.(not\.)?(eq|neq|is|in|gte|gt|lte|lt|like|ilike)\.(.*)$/,
    );
    if (!match) throw new Error("Unsupported offline logical filter");
    return valuesAt(row, match[1].split(".")).some((v) =>
      compare(v, (match[2] || "") + match[3] + "." + match[4])
    );
  }
  function filters(row, params, prefix = "") {
    for (const [key, val] of params) {
      if (!key.startsWith(prefix)) continue;
      const field = key.slice(prefix.length);
      if (/\.(order|limit|offset)$/.test(field)) continue;
      if (
        ["select", "order", "offset", "limit", "on_conflict", "columns"]
          .includes(field)
      ) continue;
      if (prefix && field.includes(".")) continue;
      if (field === "or" || field === "and") {
        if (!logical(row, field + val)) return false;
      } else if (
        !valuesAt(row, field.split(".")).some((v) => compare(v, val))
      ) return false;
    }
    return true;
  }
  function orderLimit(rows, params, prefix = "") {
    rows = rows.slice();
    const order = params.get(prefix + "order");
    if (order) {
      rows.sort((a, b) => {
        for (const expr of split(order)) {
          const [key, direction = "asc", nulls] = expr.split(".");
          const x = a[key], y = b[key];
          if (x === y) continue;
          if (x == null || y == null) {
            const first = nulls ? nulls === "nullsfirst" : direction === "desc";
            return (x == null ? -1 : 1) * (first ? 1 : -1);
          }
          return (x < y ? -1 : 1) * (direction === "desc" ? -1 : 1);
        }
        return 0;
      });
    }
    const offset = Number(params.get(prefix + "offset") || 0),
      limit = params.get(prefix + "limit");
    return rows.slice(
      offset,
      limit == null ? undefined : offset + Number(limit),
    );
  }
  function query(tables, table, params = new URLSearchParams()) {
    // Filters/order may refer to fields omitted by select; evaluate against a
    // full expanded row first, then project the requested columns.
    const selection = params.get("select") || "*";
    const full = "*" +
      (selectParts(selection).filter((p) => !p.field).map((p) =>
        "," + p.head + "(*" + (selectParts(p.children).some((c) =>
            !c.field
          )
          ? "," + split(p.children).filter((s) => s.includes("(")).join(",")
          : "") +
        ")"
      ).join(""));
    // Apply simple root constraints before expanding relationships. Nested and
    // logical filters still run after expansion to preserve their semantics.
    const rootFilters = new URLSearchParams(
      [...params].filter(([k]) =>
        !k.includes(".") && !["or", "and"].includes(k)
      ),
    );
    const indices = new Map();
    let rows = tableRows(tables, table).filter((r) => filters(r, rootFilters))
      .map((r) => expand(tables, table, r, full, params, "", indices)).filter(
        Boolean,
      ).filter((r) => filters(r, params));
    const count = rows.length;
    rows = orderLimit(rows, params);
    const fields = selectParts(selection);
    rows = rows.map((row) => {
      const out = {};
      for (const p of fields) {
        if (p.field === "*") Object.assign(out, row);
        else if (p.field) {
          const [a, f] = p.field.includes(":")
            ? p.field.split(":")
            : [p.field, p.field];
          out[a] = row[f];
        } else out[p.alias] = row[p.alias];
      }
      return out;
    });
    return { rows, count };
  }
  const api = {
    clone,
    equal,
    canonical,
    split,
    relations,
    keyFields,
    identity,
    project,
    query,
    compare,
    filters,
    tableRows,
    tablesFor,
  };
  root.BreederOfflineQuery = api;
  if (typeof module !== "undefined") module.exports = api;
})(globalThis);

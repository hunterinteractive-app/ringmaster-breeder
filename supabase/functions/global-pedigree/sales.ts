/// <reference lib="dom" />
import { document, ORIGIN, Session, State } from "./collector.ts";
const clean = (v: string | null | undefined) =>
  (v ?? "").replace(/\s+/g, " ").trim();
export async function inspectSales(state: State) {
  const session = new Session(state.cookies);
  const doc = document(
    await session.request("/index.php?page=herd&function=sales"),
  );
  state.cookies = session.cookies;
  const heading = doc.querySelector("#hybridDefaultHeading");
  const center = doc.querySelector("#indexDefault") ?? heading?.parentElement;
  if (!center || !/sales/i.test(clean(heading?.textContent))) {
    throw new Error("Unable to inspect Global Pedigree sales history.");
  }
  const link = (a: Element) => ({
    text: clean(a.textContent),
    href: new URL(a.getAttribute("href")!, ORIGIN).href,
  });
  return {
    title: clean(heading?.textContent),
    text: clean(center.textContent).slice(-200000),
    links: Array.from(center.querySelectorAll("a[href]")).map(link),
    tables: Array.from(center.querySelectorAll("table")).map((t) => ({
      id: t.id,
      rows: Array.from(t.querySelectorAll("tr")).map((r) => ({
        cells: Array.from(r.querySelectorAll("th,td")).map((c) =>
          clean(c.textContent)
        ),
        links: Array.from(r.querySelectorAll("a[href]")).map(link),
        inputs: Array.from(
          r.querySelectorAll("input:not([type=password]),select,textarea"),
        ).map((i) => ({
          name: i.getAttribute("name"),
          id: i.id,
          type: i.getAttribute("type"),
          value: i.getAttribute("value") ?? clean(i.textContent),
        })),
      })),
    })),
  };
}

export function salesRecords(page: Awaited<ReturnType<typeof inspectSales>>) {
  const table = page.tables.find((t) => t.id === "results_table");
  if (
    !table ||
    JSON.stringify(table.rows[0]?.cells) !==
      JSON.stringify(["#", "Rabbit", "Sale Date", "Seller", "Buyer", "Price"])
  ) throw new Error("Unable to read the sales table columns.");
  const records: Record<string, unknown>[] = [];
  for (const row of table.rows.slice(1)) {
    if (row.cells.length === 1 && row.cells[0] === "SALES") continue;
    if (row.cells.length !== 6 || !/^\d+$/.test(row.cells[0])) {
      throw new Error("Unable to read a Global Pedigree sales row.");
    }
    const url = row.links.map((a) => new URL(a.href)).find((u) =>
      u.origin === ORIGIN && u.searchParams.get("page") === "rabbits" &&
      u.searchParams.get("function") === "sales" &&
      u.searchParams.get("unit") === "view"
    );
    const id = url?.searchParams.get("sale"),
      animal = url?.searchParams.get("rid");
    if (!id || !animal || !/^\d+$/.test(id) || !/^\d+$/.test(animal)) {
      throw new Error("Unable to identify a Global Pedigree sale.");
    }
    const date = row.cells[2].match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
    let normalized: string | null = null;
    if (date) {
      const iso = `${date[3]}-${date[1]}-${date[2]}`;
      const d = new Date(iso + "T00:00:00Z");
      if (!Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === iso) {
        normalized = iso;
      }
    }
    const money = row.cells[5].replace(/[$,\s]/g, "");
    if (money && !/^\d{1,9}\.\d{2}$/.test(money)) {
      throw new Error("Unable to read a Global Pedigree sale price.");
    }
    const cents = money
      ? Number(money.split(".")[0]) * 100 + Number(money.split(".")[1])
      : null;
    records.push({
      kind: "sale",
      source_id: id,
      animal_source_id: animal,
      sale_date: normalized,
      sale_cents: cents,
      currency: "USD",
      buyer_name: row.cells[4],
      fields: Object.fromEntries(
        table.rows[0].cells.map((k, i) => [k, row.cells[i]]),
      ),
      source_url: url!.href,
    });
  }
  if (new Set(records.map((r) => r.source_id)).size !== records.length) {
    throw new Error("Unable to read unique Global Pedigree sales records.");
  }
  if (records.length > 2000) {
    throw new Error("Too many Global Pedigree sales records.");
  }
  return records;
}

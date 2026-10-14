import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { salesRecords } from "./sales.ts";
const row = (id: string, price: string, date = "05/30/2021") => ({
  cells: ["1", "Rabbit", date, "Seller", "", price],
  links: [{
    text: "Rabbit",
    href:
      `https://www.globalpedigree.com/index.php?page=rabbits&function=sales&unit=view&sale=${id}&rid=211161`,
  }],
  inputs: [],
});
const page = (rows: ReturnType<typeof row>[]) => ({
  title: "Sales Data for My Herd",
  text: "",
  links: [],
  tables: [{
    id: "results_table",
    rows: [{
      cells: ["#", "Rabbit", "Sale Date", "Seller", "Buyer", "Price"],
      links: [],
      inputs: [],
    }, ...rows],
  }],
});
Deno.test("sales preserve separate IDs, exact zero prices, blank buyers and source dates", () => {
  const r = salesRecords(
    page([row("28326", "$ 3.00"), row("28327", "$ 0.00")]),
  );
  assertEquals(r.map((x) => x.sale_cents), [300, 0]);
  assertEquals(r.map((x) => x.sale_date), ["2021-05-30", "2021-05-30"]);
  assertEquals(r[0].buyer_name, "");
  assertEquals(r[0].animal_source_id, "211161");
});
Deno.test("malformed or duplicate sale identities fail safely", () => {
  assertThrows(() =>
    salesRecords(page([row("1", "$ 3.00"), row("1", "$ 3.00")]))
  );
  assertThrows(() => salesRecords(page([row("1", "$ 3.999")])));
  assertEquals(
    salesRecords(page([row("1", "", "02/30/2021")]))[0].sale_date,
    null,
  );
});

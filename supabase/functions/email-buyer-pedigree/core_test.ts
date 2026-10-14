import { pdfBytes, publicPedigree, validEmail } from "./core.ts";
function assert(value: unknown) {
  if (!value) throw new Error("Assertion failed");
}
Deno.test("pedigree export removes private sale, ownership, health, and unknown fields", () => {
  const data = publicPedigree({
    animal: {
      name: "Midnight",
      species: "rabbit",
      tattoo: "A1",
      id: "private-id",
      ring_id: "private-ring",
      notes: "Private notes",
      buyer_email: "private@example.com",
      sale_cents: 10000,
      medical_history: "private",
      color_details: { color: "Black", base_color: "Black", buyer: "Private" },
    },
    sire: { name: "Dad" },
    buyer: { name: "Buyer" },
    asking_cents: 10000,
  });
  const text = JSON.stringify(data);
  assert(
    text.includes("Midnight") && text.includes("Dad") &&
      text.includes("base_color"),
  );
  assert(
    !text.includes("private") && !text.includes("Private") &&
      !text.includes("buyer") && !text.includes("sale_cents"),
  );
  assert(Object.keys(data).length === 15);
});
Deno.test("recipient accepts one address and rejects header injection or multiple recipients", () => {
  assert(validEmail("buyer@example.com"));
  for (
    const v of [
      "a@example.com,b@example.com",
      "a@example.com\nBcc:x@example.com",
      "bad",
      "<a@example.com>",
    ]
  ) assert(!validEmail(v));
});
Deno.test("PDF validation rejects text and oversized files", () => {
  assert(pdfBytes(btoa("%PDF-1.4 test")));
  for (const v of [btoa("not a PDF"), "!bad", "A".repeat(5600001)]) {
    let failed = false;
    try {
      pdfBytes(v);
    } catch {
      failed = true;
    }
    assert(failed);
  }
});

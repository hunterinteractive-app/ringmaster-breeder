export const slots = [
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
const fields = [
  "name",
  "tattoo",
  "species",
  "breed",
  "variety",
  "sex",
  "dob",
  "registration_number",
  "grand_champion_number",
  "legs",
  "weight",
  "leg_details",
];
export function publicPedigree(snapshot: Record<string, unknown>) {
  return Object.fromEntries(slots.map((slot) => {
    const raw = snapshot[slot];
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      return [slot, null];
    }
    const a = raw as Record<string, unknown>;
    const result: Record<string, unknown> = {};
    for (const field of fields) {
      const value = a[field];
      if (
        typeof value === "string" || typeof value === "number" || value === null
      ) result[field] = value;
    }
    if (
      a.color_details && typeof a.color_details === "object" &&
      !Array.isArray(a.color_details)
    ) {
      const allowed = [
        "color",
        "pattern",
        "eye_color",
        "base_color",
        "tipping",
        "undercolor",
        "surface_color",
        "ticking",
        "markings",
      ];
      result.color_details = Object.fromEntries(
        Object.entries(a.color_details).filter(([key, v]) =>
          allowed.includes(key) && typeof v === "string"
        ),
      );
    }
    return [slot, result];
  }));
}
export function validEmail(value: unknown): value is string {
  return typeof value === "string" && value.length <= 254 &&
    /^[^\s<>@,;]+@[^\s<>@,;]+\.[^\s<>@,;]+$/.test(value);
}
export function pdfBytes(value: unknown): string {
  if (
    typeof value !== "string" || value.length > 5600000 ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(value)
  ) throw new Error("Invalid PDF attachment");
  const decoded = atob(value);
  if (!decoded.startsWith("%PDF-") || decoded.length > 4 * 1024 * 1024) {
    throw new Error("Invalid PDF attachment");
  }
  return value;
}
export async function digest(value: string) {
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
  ).map((b) => b.toString(16).padStart(2, "0")).join("");
}
export async function readBody(req: Request) {
  const reader = req.body?.getReader();
  if (!reader) throw new Error("A JSON body is required");
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > 6000000) {
        await reader.cancel();
        throw new Error("Attachment is too large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  const body = JSON.parse(new TextDecoder().decode(bytes));
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new Error("Invalid request");
  }
  return body;
}

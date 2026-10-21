export const APP = "ringmaster_breeder";
export const STRIPE_ACCOUNT = "acct_1T85ZRLAhl5IBJ5k";
export const API_VERSION = "2026-08-26.dahlia";
export const RETURN_URL = "https://breeder.ringmasterone.com/?billing=return";
export function encodeForm(data: Record<string, unknown>): URLSearchParams {
  const out = new URLSearchParams();
  function add(key: string, value: unknown) {
    if (value === undefined || value === null) return;
    if (Array.isArray(value)) value.forEach((v, i) => add(`${key}[${i}]`, v));
    else if (typeof value === "object") {
      Object.entries(value).forEach(([k, v]) => add(`${key}[${k}]`, v));
    } else out.append(key, String(value));
  }
  Object.entries(data).forEach(([k, v]) => add(k, v));
  return out;
}
export class StripeClient {
  constructor(private key = Deno.env.get("STRIPE_SECRET_KEY") ?? "") {
    if (!key.startsWith("sk_live_") && !key.startsWith("rk_live_")) {
      throw Error("Live billing key unavailable");
    }
  }
  async request(
    path: string,
    method = "GET",
    data: Record<string, unknown> = {},
    idempotency?: string,
  ): Promise<any> {
    const form = encodeForm(data);
    const response = await fetch(
      `https://api.stripe.com/v1/${path}${
        method === "GET" && form.size ? "?" + form : ""
      }`,
      {
        method,
        headers: {
          Authorization: `Bearer ${this.key}`,
          "Stripe-Version": API_VERSION,
          ...(method === "GET"
            ? {}
            : { "Content-Type": "application/x-www-form-urlencoded" }),
          ...(idempotency ? { "Idempotency-Key": idempotency } : {}),
        },
        body: method === "GET" ? undefined : form,
        signal: AbortSignal.timeout(20000),
      },
    );
    const result = await response.json();
    if (!response.ok) {
      throw Error(
        `Stripe request failed (${
          result.error?.code ?? response.status
        }). Please retry or contact support.`,
      );
    }
    return result;
  }
  async verifyAccount() {
    const account = await this.request("account");
    if (account.id !== STRIPE_ACCOUNT || !account.charges_enabled) {
      throw Error("Live billing account is not ready");
    }
  }
}
export async function verifySignature(
  raw: string,
  header: string,
  secret: string,
  now = Date.now() / 1000,
): Promise<boolean> {
  const parts = header.split(",").map((p) => p.split("="));
  const timestamp = Number(parts.find(([k]) => k === "t")?.[1]);
  if (
    !secret || !Number.isFinite(timestamp) || Math.abs(now - timestamp) > 300
  ) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = Array.from(
    new Uint8Array(
      await crypto.subtle.sign(
        "HMAC",
        key,
        new TextEncoder().encode(`${timestamp}.${raw}`),
      ),
    ),
  ).map((x) => x.toString(16).padStart(2, "0")).join("");
  return parts.filter(([k]) => k === "v1").some(([, sig]) => {
    if (sig?.length !== signature.length) return false;
    let diff = 0;
    for (let i = 0; i < sig.length; i++) {
      diff |= sig.charCodeAt(i) ^ signature.charCodeAt(i);
    }
    return diff === 0;
  });
}
export const refId = (v: any): string | null =>
  typeof v === "string" ? v : v?.id ?? null;
export const iso = (v: number | undefined | null) =>
  v ? new Date(v * 1000).toISOString() : null;
export function paidPeriod(subscription: any): string | null {
  const invoice = subscription.latest_invoice;
  if (!invoice || typeof invoice === "string" || invoice.status !== "paid") {
    return null;
  }
  const item = subscription.items?.data?.[0];
  const line = invoice.lines?.data?.find((l: any) =>
    (l.parent?.subscription_item_details?.subscription_item === item?.id ||
      l.subscription_item === item?.id) &&
    (refId(l.pricing?.price_details?.price) ?? refId(l.price)) ===
      refId(item?.price) &&
    !l.parent?.subscription_item_details?.proration
  );
  return iso(line?.period?.end);
}
export function schedulePhases(
  subscription: any,
  schedule: any,
  price: string,
  interval: string,
) {
  const item = subscription.items.data[0];
  const end = item.current_period_end ?? subscription.current_period_end;
  if (!end || end <= Date.now() / 1000) {
    throw Error("Renewal date unavailable. Retry after payment completes.");
  }
  return {
    end_behavior: "release",
    proration_behavior: "none",
    metadata: { application: APP },
    phases: [
      {
        start_date: schedule.current_phase.start_date,
        end_date: end,
        items: [{ price: refId(item.price), quantity: 1 }],
        proration_behavior: "none",
      },
      {
        start_date: end,
        duration: { interval, interval_count: 1 },
        items: [{ price, quantity: 1 }],
        proration_behavior: "none",
      },
    ],
  };
}

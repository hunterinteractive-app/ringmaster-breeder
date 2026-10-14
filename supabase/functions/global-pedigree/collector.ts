/// <reference lib="dom" />
import { parseHTML } from "npm:linkedom@0.18.12";
import { litterList, litterDetail, weightHistory } from "./history.ts";
export const ORIGIN = "https://www.globalpedigree.com";
export const LIMIT = 2000;
export type State = {
  user: string;
  expires: number;
  account: string;
  cookies: Record<string, string>;
  owned: string[];
  live?: string[];
  queue: string[];
  seen: string[];
  historyQueue?: Record<string, unknown>[];
};
const clean = (v: string | null | undefined) =>
  (v ?? "").replace(/\s+/g, " ").trim();
const optional = (v: string) =>
  !v || /^(--|\?\?\?|None selected)$/i.test(v) ? null : v;
export function document(html: string) {
  return parseHTML(html).document;
}
export function herdIds(html: string): string[] {
  const doc = document(html);
  const table = doc.querySelector("#results_table");
  if (!table) throw new Error("Unable to read the complete herd list.");
  return [
    ...new Set(
      Array.from(table.querySelectorAll("a[href]")).map((a) => {
        const url = new URL(a.getAttribute("href")!, ORIGIN);
        return url.searchParams.get("page") === "rabbits"
          ? url.searchParams.get("rid")
          : null;
      }).filter((id): id is string => !!id && /^\d+$/.test(id)),
    ),
  ];
}
export function rabbit(html: string, id: string, owned: boolean, live = owned) {
  const doc = document(html), table = doc.querySelector("#rabbit_table");
  if (!table) {
    throw new Error(
      "A rabbit detail page could not be read. Please reconnect.",
    );
  }
  const fields = new Map<string, Element>();
  for (const row of Array.from(table.querySelectorAll("tr"))) {
    const label = row.querySelector(".inputLabel"),
      value = row.querySelector(".inputData");
    if (label && value) {
      fields.set(clean(label.textContent).replace(/:$/, ""), value);
    }
  }
  const value = (key: string) => clean(fields.get(key)?.textContent);
  const parent = (key: string) => {
    const href = fields.get(key)?.querySelector("a[href]")?.getAttribute(
      "href",
    );
    if (!href) return null;
    const url = new URL(href, ORIGIN), rid = url.searchParams.get("rid");
    if (
      url.origin !== ORIGIN || url.searchParams.get("page") !== "rabbits" ||
      !rid || !/^\d+$/.test(rid)
    ) throw new Error("An unsupported pedigree link was found.");
    return rid;
  };
  const breed = optional(value("Breed"));
  let name = clean(doc.querySelector("#hybridDefaultHeading")?.textContent);
  if (breed && name.endsWith(` - ${breed}`)) {
    name = name.slice(0, -breed.length - 3);
  }
  if (!name) throw new Error("A rabbit name could not be read.");
  const date = value("Date of Birth").match(/^(\d{2})\/(\d{2})\/(\d{4})/);
  const rawDate = optional(value("Date of Birth"));
  if (rawDate && !date) throw new Error("A rabbit date could not be read.");
  const rawWeight = clean(
    fields.get("Weight")?.querySelector("#weight_val")?.textContent,
  );
  const weight = rawWeight.match(
    /^(?:(\d+(?:\.\d+)?)\s*lbs?\s*)?(?:(\d+(?:\.\d+)?)\s*oz)?$/i,
  );
  if (rawWeight && (!weight || (!weight[1] && !weight[2]))) {
    throw new Error("A rabbit weight could not be read.");
  }
  const sex = value("Buck/Doe");
  const legs = optional(value("# of Show Legs"));
  if (legs && !/^\d+$/.test(legs)) {
    throw new Error("A rabbit show-leg count could not be read.");
  }
  return {
    source_id: id,
    name,
    tattoo: optional(value("Ear Number")),
    breed,
    variety: optional(value("Variety")),
    sex: ["Buck", "Doe"].includes(sex) ? sex : null,
    dob: date ? `${date[3]}-${date[1]}-${date[2]}` : null,
    weight: rawWeight && weight
      ? Number(weight[1] || 0) + Number(weight[2] || 0) / 16
      : null,
    registration_number: optional(value("Reg. Number")),
    grand_champion_number: optional(value("G.C. Number")),
    legs: legs ? Number(legs) : null,
    status: value("Deceased") === "Yes" ? "deceased" : owned && !live ? "archived" : "active",
    source_live: owned && live,
    sire_id: parent("Sire"),
    dam_id: parent("Dam"),
    notes: optional(clean(doc.querySelector("#r_notes")?.textContent)),
    pedigree_only: !owned,
  };
}
export class Session {
  constructor(
    public cookies: Record<string, string> = {},
    private fetcher: typeof fetch = fetch,
  ) {}
  async request(path: string, body?: URLSearchParams): Promise<string> {
    let url = new URL(path, ORIGIN), method = body ? "POST" : "GET";
    for (let redirect = 0; redirect < 6; redirect++) {
      if (url.origin !== ORIGIN) {
        throw new Error(
          "Global Pedigree redirected to an unsupported website.",
        );
      }
      const response = await this.fetcher(url, {
        method,
        body: method === "POST" ? body : undefined,
        redirect: "manual",
        signal: AbortSignal.timeout(15000),
        headers: {
          Cookie: Object.entries(this.cookies).map(([k, v]) => `${k}=${v}`)
            .join("; "),
          ...(method === "POST"
            ? { "Content-Type": "application/x-www-form-urlencoded" }
            : {}),
        },
      });
      for (const cookie of response.headers.getSetCookie()) {
        const first = cookie.split(";")[0],
          split = first.indexOf("="),
          key = first.slice(0, split),
          val = first.slice(split + 1);
        if (!/^[\w-]+$/.test(key) || /[\r\n;]/.test(val)) continue;
        const domain = cookie.match(/;\s*domain=([^;]+)/i)?.[1].replace(
          /^\./,
          "",
        ).toLowerCase();
        if (
          domain &&
          !["www.globalpedigree.com", "globalpedigree.com"].includes(domain)
        ) continue;
        if (/;\s*max-age=0(?:;|$)/i.test(cookie)) delete this.cookies[key];
        else this.cookies[key] = val;
      }
      if ([301, 302, 303, 307, 308].includes(response.status)) {
        const location = response.headers.get("location");
        if (!location) {
          throw new Error("Global Pedigree returned an invalid redirect.");
        }
        await response.body?.cancel();
        url = new URL(location, url);
        if ([301, 302, 303].includes(response.status)) method = "GET";
        continue;
      }
      if (!response.ok) {
        throw new Error("Global Pedigree is unavailable. Please try again.");
      }
      const reader = response.body?.getReader();
      if (!reader) throw new Error("Empty response from Global Pedigree.");
      let size = 0;
      const chunks: Uint8Array[] = [];
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > 3000000) {
          await reader.cancel();
          throw new Error("A Global Pedigree page is too large.");
        }
        chunks.push(value);
      }
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.length;
      }
      return new TextDecoder().decode(bytes);
    }
    throw new Error("Too many Global Pedigree redirects.");
  }
}
export async function start(
  user: string,
  username: string,
  password: string,
  fetcher: typeof fetch = fetch,
): Promise<State> {
  const session = new Session({}, fetcher);
  await session.request("/index.php?page=login");
  await session.request(
    "/index.php?page=login&action=process",
    new URLSearchParams({ email_address: username, password }),
  );
  const dashboard = document(await session.request("/index.php?page=dash"));
  const referral = clean(dashboard.querySelector("#reflink")?.textContent);
  let ref: string | null = null;
  try {
    ref = new URL(referral).searchParams.get("refid");
  } catch { /* Authentication failed. */ }
  if (!ref || !/^[a-zA-Z0-9]{10,100}$/.test(ref)) {
    throw new Error(
      "Global Pedigree sign-in failed. Check your username and password.",
    );
  }
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(ref),
  );
  const account = "gp:" +
    Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0"))
      .join("");
  let html = await session.request("/index.php?page=herd&list=all");
  const countText = clean(
    document(html).querySelector("#indexDefault")?.textContent,
  );
  const match = countText.match(/(\d+) results\s*\(All Rabbits\)/i);
  if (!match) {
    throw new Error("Unable to verify the complete Global Pedigree herd.");
  }
  const count = Number(match[1]);
  if (count === 0) throw new Error("Global Pedigree has no rabbits to import.");
  if (count > LIMIT) {
    throw new Error(
      "This importer supports up to 2,000 rabbits and ancestors.",
    );
  }
  if (count > 0) {
    html = await session.request(`/index.php?page=herd&list=all&sh=${count}`);
  }
  const owned = herdIds(html);
  if (owned.length !== count) {
    throw new Error("Global Pedigree returned an incomplete herd list.");
  }
  const liveHtml = await session.request("/index.php?page=herd&list=live");
  const liveMatch = clean(document(liveHtml).querySelector("#indexDefault")?.textContent).match(/(\d+) results\s*\(All Live Rabbits\)/i);
  if (!liveMatch) throw new Error("Unable to verify the current Global Pedigree herd.");
  const liveCount = Number(liveMatch[1]);
  if (liveCount > count) throw new Error("Global Pedigree returned inconsistent herd lists.");
  const live = liveCount ? herdIds(await session.request(`/index.php?page=herd&list=live&sh=${liveCount}`)) : [];
  if (live.length !== liveCount || live.some(id => !owned.includes(id))) throw new Error("Global Pedigree returned an incomplete live herd list.");
  const litters = litterList(await session.request("/index.php?page=herd&function=litter&archive=show"));
  const historyQueue = [...litters, ...owned.map(id => ({kind:"weight", animal_source_id:id}))];
  if (historyQueue.length > LIMIT) throw new Error("This importer supports up to 2,000 history pages.");
  const queue = [...owned];
  for (const litter of litters) {
    for (const id of [litter.animal_source_id, litter.sire_source_id]) {
      if (!queue.includes(String(id))) queue.push(String(id));
    }
  }
  return {
    historyQueue,
    user,
    expires: Date.now() + 3600000,
    account,
    cookies: session.cookies,
    owned,
    live,
    queue,
    seen: [],
  };
}
export async function batch(state: State, fetcher: typeof fetch = fetch) {
  const session = new Session(state.cookies, fetcher), animals = [];
  // Sequential requests keep load low and avoid races in the upstream cookie jar.
  for (let i = 0; i < 6 && state.queue.length; i++) {
    const id = state.queue.shift()!;
    const animal = rabbit(
      await session.request(`/index.php?page=rabbits&rid=${id}`),
      id,
      state.owned.includes(id),
      (state.live ?? state.owned).includes(id),
    );
    state.seen.push(id);
    animals.push(animal);
    for (const parent of [animal.sire_id, animal.dam_id]) {
      if (
        parent && !state.seen.includes(parent) && !state.queue.includes(parent)
      ) state.queue.push(parent);
    }
    if (state.seen.length + state.queue.length > LIMIT) {
      throw new Error(
        "This importer supports up to 2,000 rabbits and ancestors.",
      );
    }
  }
  state.cookies = session.cookies;
  return animals;
}
export async function historyBatch(state: State, fetcher: typeof fetch = fetch) {
  const session = new Session(state.cookies, fetcher), history=[];
  for(let i=0;i<4 && state.historyQueue?.length;i++) {
    const task=state.historyQueue.shift()!;
    if(task.kind==="litter") {
      const record=litterDetail(await session.request(String(task.detail_path)),task);
      history.push(record);
      for(const id of record.offspring_source_ids) {
        if(!state.seen.includes(id)&&!state.queue.includes(id)) state.queue.push(id);
      }
    } else if(task.kind==="weight") {
      history.push(...weightHistory(await session.request(`/index.php?page=rabbits&function=weights&rid=${task.animal_source_id}`),String(task.animal_source_id)));
    } else throw new Error("Invalid import history session.");
    if(state.seen.length+state.queue.length>LIMIT) throw new Error("This importer supports up to 2,000 rabbits and ancestors.");
  }
  state.cookies=session.cookies;
  return history;
}
export async function key(secret: string) {
  return crypto.subtle.importKey(
    "raw",
    await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode("global-pedigree-session-v1:" + secret),
    ),
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );
}
const base64 = (bytes: Uint8Array) =>
  btoa(Array.from(bytes, (b) => String.fromCharCode(b)).join(""));
export async function seal(state: State, secret: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  return base64(iv) + "." +
    base64(
      new Uint8Array(
        await crypto.subtle.encrypt(
          { name: "AES-GCM", iv },
          await key(secret),
          new TextEncoder().encode(JSON.stringify(state)),
        ),
      ),
    );
}
export async function open(
  token: string,
  secret: string,
  user: string,
): Promise<State> {
  try {
    if (token.length > 1000000) throw new Error();
    const [a, b, ...rest] = token.split(".");
    if (rest.length) throw new Error();
    const decode = (s: string) =>
      Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
    const state = JSON.parse(
      new TextDecoder().decode(
        await crypto.subtle.decrypt(
          { name: "AES-GCM", iv: decode(a) },
          await key(secret),
          decode(b),
        ),
      ),
    );
    if (
      state.user !== user || state.expires < Date.now() ||
      state.expires > Date.now() + 3600000 || !Array.isArray(state.queue) ||
      !Array.isArray(state.seen) || !Array.isArray(state.owned) ||
      state.queue.length + state.seen.length > LIMIT ||
      [...state.queue, ...state.seen, ...state.owned].some((x) =>
        typeof x !== "string" || !/^\d+$/.test(x)
      )
      || (state.historyQueue != null && (!Array.isArray(state.historyQueue) || state.historyQueue.length > LIMIT))
    ) throw new Error();
    return state;
  } catch {
    throw new Error(
      "The import session expired or is invalid. Please reconnect.",
    );
  }
}

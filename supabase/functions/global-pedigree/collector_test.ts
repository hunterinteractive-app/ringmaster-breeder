import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  batch,
  herdIds,
  open,
  rabbit,
  seal,
  Session,
  start,
  State,
} from "./collector.ts";
const detail = (sex = "Buck", weight = "7 lbs 8 oz") =>
  `<h1 id="hybridDefaultHeading">Test Rabbit - Standard Chinchilla</h1><table id="rabbit_table">${
    Object.entries({
      "Breed": "Standard Chinchilla",
      "Ear Number": "T1",
      "Date of Birth": "05/04/2022 (4 yrs)",
      "Buck/Doe": sex,
      "Variety": "None selected",
      "Weight": `<span id="weight_val">${weight}</span> - Update Weight`,
      "Reg. Number": "123",
      "# of Show Legs": "2",
      "Deceased": "Yes",
      "Sire":
        '<a href="https://www.globalpedigree.com/index.php?page=rabbits&amp;rid=2">Sire</a> Edit Sire',
      "Dam": "",
    }).map(([k, v]) =>
      `<tr><td class="inputLabel">${k}:</td><td class="inputData">${v}</td></tr>`
    ).join("")
  }<tr><td id="r_notes">Test notes</td></tr></table>`;
Deno.test("detail parser preserves fields, normalizes placeholders, and converts ounces", () => {
  const a = rabbit(detail(), "1", true);
  assertEquals(a.name, "Test Rabbit");
  assertEquals(a.weight, 7.5);
  assertEquals(a.dob, "2022-05-04");
  assertEquals(a.sire_id, "2");
  assertEquals(a.dam_id, null);
  assertEquals(a.variety, null);
  assertEquals(a.legs, 2);
  assertEquals(a.status, "deceased");
  assertEquals(a.pedigree_only, false);
  assertEquals(a.notes, "Test notes");
  assertEquals(rabbit(detail("???", ""), "2", false).sex, null);
  assertEquals(rabbit(detail("???", ""), "2", false).weight, null);
});
Deno.test("herd listing ignores pedigree links and deduplicates detail links", () => {
  assertEquals(
    herdIds(
      '<table id="results_table"><tr><td><a href="?page=rabbits&rid=1">A</a><a href="?page=rabbits&rid=1">Detail</a><a href="?page=pedigree&rid=2">Pedigree</a></td></tr></table>',
    ),
    ["1"],
  );
});
Deno.test("credential redirects cannot send passwords or cookies offsite", async () => {
  let calls = 0;
  const session = new Session({}, async () => {
    calls++;
    return new Response(null, {
      status: 307,
      headers: {
        Location: "https://other.example/login",
        "Set-Cookie": "PHPSESSID=test; Path=/",
      },
    });
  });
  await assertRejects(
    () =>
      session.request(
        "/index.php?page=login",
        new URLSearchParams({ password: "test" }),
      ),
    Error,
    "unsupported website",
  );
  assertEquals(calls, 1);
});
Deno.test("cookies carry across login redirects and POST becomes GET", async () => {
  const calls: { method: string; cookie: string; body: unknown }[] = [];
  const session = new Session({}, async (_url, options) => {
    calls.push({
      method: options!.method!,
      cookie: (options!.headers as Record<string, string>).Cookie,
      body: options!.body,
    });
    return calls.length === 1
      ? new Response(null, {
        status: 302,
        headers: {
          Location: "?page=dash",
          "Set-Cookie": "PHPSESSID=abc; Path=/; Secure",
        },
      })
      : new Response("<h1>Dashboard</h1>");
  });
  assertEquals(
    await session.request(
      "/index.php?page=login",
      new URLSearchParams({ password: "test" }),
    ),
    "<h1>Dashboard</h1>",
  );
  assertEquals(calls[1].method, "GET");
  assertEquals(calls[1].body, undefined);
  assertEquals(calls[1].cookie, "PHPSESSID=abc");
});
Deno.test("continuations are encrypted, bound to the caller, authenticated and expire", async () => {
  const state: State = {
    user: "a",
    expires: Date.now() + 60000,
    account: "gp:test",
    cookies: { PHPSESSID: "private-cookie" },
    owned: ["1"],
    seen: [],
    queue: ["1"],
  };
  const token = await seal(state, "secret");
  assertEquals(token.includes("private-cookie"), false);
  assertEquals((await open(token, "secret", "a")).queue, ["1"]);
  await assertRejects(() => open(token, "secret", "b"));
  await assertRejects(() => open(token, "other", "a"));
  await assertRejects(() => open(token.slice(0, -4) + "AAAA", "secret", "a"));
  await assertRejects(async () =>
    open(
      await seal({ ...state, expires: Date.now() - 1 }, "secret"),
      "secret",
      "a",
    )
  );
});

Deno.test("collection follows parents once and marks only ancestors pedigree-only", async () => {
  const state: State = {
    user: "a",
    expires: Date.now() + 60000,
    account: "gp:test",
    cookies: {},
    owned: ["1"],
    seen: [],
    queue: ["1"],
  };
  const calls: string[] = [];
  const result = await batch(state, async (url) => {
    const id = new URL(String(url)).searchParams.get("rid")!;
    calls.push(id);
    return new Response(
      id === "1" ? detail() : detail().replace("rid=2", "rid=1"),
    );
  });
  assertEquals(calls, ["1", "2"]);
  assertEquals(state.queue, []);
  assertEquals(result.map((a) => a.pedigree_only), [false, true]);
  // The database review rejects cycles; the collector must still terminate.
});
Deno.test("a truncated all-herd response cannot produce a successful collection", async () => {
  await assertRejects(
    () =>
      start("a", "fixture", "test", async (url) => {
        const u = new URL(String(url));
        if (u.searchParams.get("page") === "dash") {
          return new Response(
            '<textarea id="reflink">https://www.globalpedigree.com/index.php?refid=abcdefghij1234567890</textarea>',
          );
        }
        if (u.searchParams.get("page") === "herd") {
          return new Response(
            '<div id="indexDefault">2 results (All Rabbits): <table id="results_table"><tr><td><a href="?page=rabbits&amp;rid=1">Only one</a></td></tr></table></div>',
          );
        }
        return new Response("<h1>Login</h1>");
      }),
    Error,
    "incomplete herd list",
  );
});

Deno.test("non-deceased historical herd rabbits are archived; ancestors remain pedigree-only",()=>{
 const html=detail().replace('<td class="inputData">Yes</td>','<td class="inputData">No</td>');
 assertEquals(rabbit(html,'1',true,false).status,'archived');
 assertEquals(rabbit(html,'1',true,true).status,'active');
 assertEquals(rabbit(detail(),'1',true,false).status,'deceased');
 assertEquals(rabbit(html,'1',false,false).pedigree_only,true);
});
Deno.test("a truncated live list cannot complete collection",async()=>{
 await assertRejects(()=>start('a','fixture','test',async(url)=>{
 const u=new URL(String(url));
 if(u.searchParams.get('page')==='dash')return new Response('<textarea id="reflink">https://www.globalpedigree.com/index.php?refid=abcdefghij1234567890</textarea>');
 if(u.searchParams.get('list')==='all')return new Response('<div id="indexDefault">2 results (All Rabbits)<table id="results_table"><tr><td><a href="?page=rabbits&rid=1">A</a><a href="?page=rabbits&rid=2">B</a></td></tr></table></div>');
 if(u.searchParams.get('list')==='live')return new Response('<div id="indexDefault">2 results (All Live Rabbits)<table id="results_table"><tr><td><a href="?page=rabbits&rid=1">A</a></td></tr></table></div>');
 return new Response('Login');
 }),Error,'incomplete live herd list');
});

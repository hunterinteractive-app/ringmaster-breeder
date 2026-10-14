/// <reference lib="dom" />
import { document, ORIGIN } from "./collector.ts";
const clean = (v: string | null | undefined) => (v ?? "").replace(/\s+/g, " ").trim();
function sourceURL(href: string) {
  const u = new URL(href, ORIGIN);
  if (u.origin !== ORIGIN || u.searchParams.get("page") !== "rabbits") throw new Error("An unsupported history link was found.");
  return u;
}
export function litterList(html: string) {
  const doc = document(html), table = doc.querySelector("#results_table");
  if (!table || !clean(doc.querySelector("#hybridDefaultHeading")?.textContent).includes("Litter Data")) throw new Error("Unable to read Global Pedigree litter history.");
  let category = "";
  const records: Record<string, unknown>[] = [];
  for (const row of Array.from(table.querySelectorAll("tr"))) {
    const cells = Array.from(row.querySelectorAll("td"));
    if (cells.length === 1) { category = clean(cells[0].textContent); continue; }
    const href = cells[1]?.querySelector("a[href]")?.getAttribute("href");
    if (!href) continue;
    const u = sourceURL(href), id = u.searchParams.get("lid"), dam = u.searchParams.get("rid"), sire = u.searchParams.get("rid2");
    if (cells.length !== 11 || !id || !dam || !sire || ![id,dam,sire].every(x=>/^\d+$/.test(x))) throw new Error("Unable to read a Global Pedigree litter record.");
    records.push({kind:"litter",source_id:id,animal_source_id:dam,sire_source_id:sire,category,detail_path:u.pathname+u.search,dam_name:clean(cells[1].textContent),sire_name:clean(cells[2].textContent),date_bred:clean(cells[3].textContent),kindled_or_due:clean(cells[4].textContent),born:clean(cells[5].textContent),bucks:clean(cells[6].textContent),does:clean(cells[7].textContent),died:clean(cells[8].textContent),date_weaned:clean(cells[9].textContent),weaned:clean(cells[10].textContent)});
  }
  if (new Set(records.map(r=>r.source_id)).size!==records.length) throw new Error("Unable to read unique Global Pedigree litter records.");
  return records;
}
export function litterDetail(html: string, record: Record<string, unknown>) {
  const doc = document(html), table = doc.querySelector("#litterData_table");
  if (!table) throw new Error("Unable to read Global Pedigree litter details.");
  const fields: Record<string,string> = {};
  let comments = false;
  for (const row of Array.from(table.querySelectorAll("tr"))) {
    const cells=Array.from(row.querySelectorAll("td")), label=clean(cells[0]?.textContent).replace(/:$/,"");
    if (label === "Comments") {comments=true;continue;}
    if(comments && cells.length===1) {fields.Comments=clean(cells[0].textContent); comments=false;}
    if(cells.length===2 && /^(Breed|Date Bred|Date Kindled|Date Due|Number Born|Number Fostered|Number Died|Number Added|Number Raised|Number Weaned|Date Weaned|Reminders)$/.test(label)) fields[label]=clean(cells[1].textContent);
  }
  const kits: string[]=[];
  for (const fieldset of Array.from(doc.querySelectorAll("fieldset"))) {
    if(clean(fieldset.querySelector("legend")?.textContent)!=="Weaned Kits") continue;
    for(const a of Array.from(fieldset.querySelectorAll("a[href]"))) {
      const u=sourceURL(a.getAttribute("href")!), id=u.searchParams.get("rid");
      if(id && /^\d+$/.test(id)) kits.push(id);
    }
  }
  const events = Array.from(doc.querySelectorAll("#litDateBtnsBox input[title]")).map(e=>({event:clean(e.getAttribute("value")),date:clean(e.getAttribute("title"))}));
  return {...record,fields,events,offspring_source_ids:[...new Set(kits)]};
}
export function weightHistory(html:string, animalId:string) {
  const doc=document(html), table=doc.querySelector("#weights-table");
  if(!table) throw new Error("Unable to read Global Pedigree weight history.");
  const records: Record<string,unknown>[]=[];
  for(const row of Array.from(table.querySelectorAll("tbody tr"))) {
    const cells=Array.from(row.querySelectorAll("td")), date=row.querySelector("[data-date-sortable]")?.getAttribute("data-date-sortable");
    if(!date) { if(cells.length>1) throw new Error("Unable to read a Global Pedigree weight date."); continue; }
    const id=row.querySelector('[id^="deleteWt_"]')?.id.replace("deleteWt_","") || `${date}:${clean(cells[2]?.textContent)}`;
    const raw=clean(cells[2]?.textContent), decimal=raw.match(/\((\d+(?:\.\d+)?) lbs\)/i), units=raw.match(/^(?:(\d+(?:\.\d+)?)\s*lbs?\s*)?(?:(\d+(?:\.\d+)?)\s*oz)?/i);
    const weight=decimal?Number(decimal[1]):units&&(units[1]||units[2])?Number(units[1]||0)+Number(units[2]||0)/16:NaN;
    if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isFinite(weight)||weight<=0||weight>=1000) throw new Error("Unable to read a Global Pedigree weight record.");
    records.push({kind:"weight",source_id:`${animalId}:${id}`,animal_source_id:animalId,recorded_date:date,weight,raw_weight:raw});
  }
  return records;
}

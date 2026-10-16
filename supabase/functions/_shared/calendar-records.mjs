const date = d => d.toISOString().slice(0, 10);
const add = (day, n) => { const d = new Date(day + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return date(d); };
export async function allPages(query) {
  const rows = [];
  for (;;) {
    const { data, error } = await query(rows.length, rows.length + 499);
    if (error) throw error;
    if (!data.length) return rows;
    rows.push(...data);
  }
}
export async function calendarRecords(db, ring, start, end) {
  const beforeEnd = (query, field) => end ? query.lt(field,end) : query;
  const dateFilter = (field, lower) => end ? `and(${field}.gte.${lower},${field}.lt.${end})` : `${field}.gte.${lower}`;
  const settings = await allPages((a,b) => db.from('breeding_settings').select().eq('ring_id',ring).order('species').range(a,b));
  let breedingDays = 72, weaningDays = 56;
  for (const s of settings) {
    for (const f of ['gestation_min','gestation_max','palpation_min','palpation_max','nesting_day']) breedingDays = Math.max(breedingDays, s[f] ?? 0);
    weaningDays = Math.max(weaningDays, s.weaning_max * 7);
  }
  const columns = '*,dam:animals!breeding_records_dam_id_fkey!inner(id,name,tattoo,species,ring_id),tracking:breeding_tracking(*)';
  const [bred, tracked, health] = await Promise.all([
    allPages((a,b) => beforeEnd(db.from('breeding_records').select(columns).eq('dam.ring_id',ring).gte('breeding_date',add(start,-breedingDays)), 'breeding_date').order('id').range(a,b)),
    allPages((a,b) => db.from('breeding_tracking').select(`breeding:breeding_records!inner(${columns})`).eq('breeding.dam.ring_id',ring)
      .or([dateFilter('check_date',start),dateFilter('wean_date',start),dateFilter('birth_date',add(start,-weaningDays))].join(',')).order('breeding_id').range(a,b)),
    allPages((a,b) => db.from('animal_health_records').select('id,title,record_type,administered_date,readminister_date,expires_date,animal:animals!inner(id,name,tattoo,ring_id)').eq('animal.ring_id',ring)
      .or(['administered_date','readminister_date','expires_date'].map(f=>dateFilter(f,start)).join(',')).order('id').range(a,b)),
  ]);
  const records = new Map(bred.map(r=>[r.id,r]));
  for(const r of tracked) records.set(r.breeding.id,r.breeding);
  return {breedings:[...records.values()], health, settings};
}
export function showInWindow(s, start, end) {
  // Date-only comparisons include timezone boundaries; final events are clipped
  // again in the subscriber's timezone before rendering the feed.
  const close = s.entry_close_at?.slice(0,10);
  return (s.start_date >= start && (!end || s.start_date < end)) ||
    (s.is_favorite && close && close >= add(start,-1) && (!end || close < add(end,1)));
}

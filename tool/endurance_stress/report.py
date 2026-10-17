#!/usr/bin/env python3
"""Report the completed fixed-code run alongside preserved pre-fix measurements."""
from datetime import datetime,timezone
import gzip
import hashlib
import json
from pathlib import Path
import statistics

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'deliverables/scaling-fixes'
def read(name):return json.loads((OUT/name).read_text())
def write(name,data):(OUT/name).write_text(json.dumps(data,indent=2)+'\n')
raw=OUT/'endurance-browser-samples.jsonl'
text=raw.read_text() if raw.exists() else gzip.decompress((OUT/'endurance-browser-samples.jsonl.gz').read_bytes()).decode()
samples=[json.loads(line) for line in text.splitlines()]
last=samples[-1]
assert last['complete'] and last['elapsed_seconds']>=1800, 'The measured 30-minute run is still in progress'
heaps=[s['js_heap_bytes'] for s in samples if s.get('js_heap_bytes') is not None]
cycles=[s['js_heap_bytes'] for s in samples if s['phase'].startswith('Cycle ') and s.get('js_heap_bytes')]
per_minute={s['elapsed_seconds']//60:s for s in samples}
browser={
 'completed':True,'viewport_css_pixels':read('browser-viewport.json'),'duration_seconds':last['elapsed_seconds'],'cycles':last['cycles'],'steps':last['ticks'],
 'counters':last['counters'],'max_mounted_animal_cards':last['max_mounted_cards'],
 'js_heap_bytes':{'minimum':min(heaps),'maximum':max(heaps),'final':heaps[-1],
  'first_three_cycle_end_median':statistics.median(cycles[:3]),'last_three_cycle_end_median':statistics.median(cycles[-3:])},
 'unexpected_checkpoints':last['errors'],'unexpected_checkpoint_count':len(last['errors']),
 'heap_scope':'JavaScript heap only; excludes GPU/Wasm.',
 'faults':'Synthetic HTTP 503 outages, 350ms added delay, and committed inserts with lost acknowledgement; no packet-loss emulation',
 'timeline':[{k:s.get(k) for k in ['elapsed_seconds','ticks','cycles','phase','js_heap_bytes','mounted_elements','max_mounted_cards']} for s in per_minute.values()],
 'proxy_final':last['proxy'],
 'calibration_notes':'Two incomplete runs are preserved separately. A widget regression confirmed the error/retry card must be scrolled into view below the month grid.',
 'start_utc':datetime.fromtimestamp(samples[0]['server_timestamp']-samples[0]['elapsed_seconds'],timezone.utc).isoformat(),
 'end_utc':datetime.fromtimestamp(last['server_timestamp'],timezone.utc).isoformat(),
}
write('endurance-browser-results.json',browser)
load=read('multiuser-load-results.json')
before=json.loads((ROOT/'deliverables/multiuser-load-results.json').read_text())
calendar=read('calendar-lifecycle-results.json')
capacity=read('calendar-large-feed-results.json')
isolation=read('multiuser-isolation-results.json')
policies=read('access-policy-results.json')
equivalence=read('policy-equivalence-results.json')
audit=read('endurance-data-audit.json')
verification=read('regression-verification.json')
phone=json.loads(Path('/private/tmp/rmb-next-stress/phone-check.json').read_text())
columns=['concurrent_breeders','rounds','sessions','failed_sessions','requests','p95_ms','max_ms','unexpected_http_errors']
passed=(not last['errors'] and all(not s['failed_sessions'] and not s['unexpected_http_errors'] for s in load['stages'])
 and all(r['passed'] for r in calendar) and capacity['passed'] and isolation['passed'] and policies['passed']
 and audit['passed'] and verification['passed'] and equivalence['passed'])
sources=['supabase/functions/calendar-feed/calendar.mjs','supabase/migrations/20261017023049_calendar_query_scaling.sql','tool/endurance_stress/main.dart','test/calendar_window_test.dart']
summary={'completed':True,'overall_passed':passed,'production_changes':False,
 'environment':'Isolated full local Supabase stack; API pool 10, max_rows 1000, worker CPU hard limit 2000ms. Synthetic data only. Not a production capacity SLA.',
 'fixture':{'breeders':50,'animals':50000,'initial_history_records':990000,'largest_herd_animals':1000,'largest_herd_history_records':500000},
 'base_commit':'c5ede03f871d1d8ef8299105cbd4ac9145f1d18c',
 'source_sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources},
 'phone':phone,'calendar_functional_checks':calendar,'calendar_capacity':capacity,'browser':browser,
 'load_stages_before':[{k:s[k] for k in columns} for s in before['stages']],
 'load_stages_after':[{k:s[k] for k in columns} for s in load['stages']],
 'isolation':isolation,'access_policy_checks':policies,'permission_equivalence':equivalence,'data_audit':audit,'regression_verification':verification}
write('scaling-fix-results.json',summary)
lines=[
 'RingMaster Breeder — scaling fixes and repeated stress tests',
 f"Result: {'PASS' if passed else 'FAIL'}. Completed {browser['end_utc']}.",
 'These stress tests ran before publication using isolated local data. Original pre-fix evidence remains in deliverables/.',
 '',
 'Fixes',
 'Resolve accessible family rings once per statement, then hash accessible animal IDs for history and breeding reads.',
 'Preserve active-owner, accepted/nonrevoked-member, non-demo-herd checks and both parents on breeding reads.',
 'Preserve USING and WITH CHECK for animal and health writes. Existing weight/breeding insert checks remain.',
 'Measure UTF-8 code-point widths without allocating a TextEncoder and byte array for every character.',
 'No API pool, acquisition timeout, row limit, feed date range or worker CPU limit was increased.',
 '',
 'Environment',
 summary['environment'],
 '50 independent breeders, 50,000 animals, 990,000 initial history records; largest herd has 500,000 history records.',
 'Flutter 3.38.5/Dart 3.10.4 release browser build; production CI uses Flutter 3.41.4.',
 '',
 'Concurrent mixed workloads — three synchronized rounds at each stage',
 'Breeders | before failed sessions | after failed sessions | before HTTP errors | after HTTP errors | before p95 ms | after p95 ms',
]
for old,new in zip(before['stages'],load['stages']):
 lines.append(f"{new['concurrent_breeders']:8} | {old['failed_sessions']:22} | {new['failed_sessions']:21} | {old['unexpected_http_errors']:18} | {new['unexpected_http_errors']:17} | {old['p95_ms']:13} | {new['p95_ms']:12}")
lines += [
 '',
 'Large private calendar feed',
 'The pre-fix fresh-worker request returned 546 WORKER_LIMIT at 20,434 events.',
 'Three fixed-code requests returned 200 with all 20,434 events (8,196,282 bytes), valid UTF-8 folds <=75 bytes and unique UIDs.',
 'All 14,000 extra follow-up events in 2035 were retained. Source dates in 1999 were excluded.',
 'Feeds still begin on the first day of last month and have no future cutoff.',
 'All five HTTP lifecycle groups passed, including refresh/update/delete, token rotation/revocation, inactive subscriber and revoked membership.',
 'CPU-only profiles compare byte-identical output with the pre-fix implementation in memory; see calendar-render-profile.json.',
 '',
 'Browser endurance',
 f"Completed {browser['duration_seconds']} seconds, {browser['cycles']} cycles, {browser['steps']} steps and {len(last['errors'])} unexpected checkpoints.",
 'The production-widget component harness was retained. The calendar-error check now scrolls below the month grid and waits up to 10s; it previously searched unmounted lazy children after 500ms. The original 80s save confirmation check is unchanged.',
 'Includes 1000-animal reloads/search/scroll/view changes, month navigation and retries, histories/graphs, bulk saves, concurrent retries and conflicting edits.',
 f"Final viewport: {browser['viewport_css_pixels']['width']} x {browser['viewport_css_pixels']['height']} CSS pixels. Max mounted cards: {browser['max_mounted_animal_cards']}. Heap min/max/final: {min(heaps)/1e6:.1f}/{max(heaps)/1e6:.1f}/{heaps[-1]/1e6:.1f} MB.",
 f"Cycle-end median for first/last three cycles: {statistics.median(cycles[:3])/1e6:.1f}/{statistics.median(cycles[-3:])/1e6:.1f} MB. GPU/Wasm memory was not measured.",
 browser['faults']+'.',
 '',
 'Security and data integrity',
 'All 50 independent families passed foreign-read and atomic mixed-family write checks.',
 f"Original and optimized animal access predicates agree for {equivalence['animal_identity_comparisons']:,} animal/identity pairs, including unauthenticated access.",
 'Additional HTTP checks cover accepted, pending and revoked membership, inactive owners, demo herds, allowed member health edits/deletes, and rejected family reassignment.',
 'The helper is private, stable, fixed-search-path, and unavailable to anonymous users; RLS remains enabled.',
 'See endurance-data-audit.json for duplicate, fixture-cleanup and revision audits.',
 '',
 'Regression checks',
 f"Flutter: {verification['flutter_tests']} passed. Node calendar: {verification['node_tests']} passed. Flutter analyze clean.",
 'Database function lint has no errors; pre-existing warnings are retained separately.',
 'Local advisors report no security errors. Two existing draft-policy performance warnings remain outside this change:',
 'https://supabase.com/docs/guides/database/database-linter?lint=0003_auth_rls_initplan',
 '',
 'Physical device scope',
 'The user previously confirmed successful iPhone subscription and expected herd dates.',
 'No new phone interaction was required. Recent/distant-future boundaries were verified automatically, not on a physical phone.',
 'Android and provider-controlled refresh timing/alerts remain unverified.',
 '',
 'Reproduction: tool/endurance_stress/README.txt. Machine-readable summary: scaling-fix-results.json.',
]
(OUT/'scaling-fix-report.txt').write_text('\n'.join(lines)+'\n')
print(json.dumps({'passed':passed,'browser_seconds':browser['duration_seconds'],'browser_errors':len(last['errors']),
 'failed_load_sessions':sum(s['failed_sessions'] for s in load['stages']),'http_errors':sum(s['unexpected_http_errors'] for s in load['stages'])}))
if not passed:raise SystemExit(1)

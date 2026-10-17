#!/usr/bin/env python3
"""Actual Edge Function + Auth + DB lifecycle, independently parsed with icalendar 6.3.2."""
from datetime import date, timedelta
import json
from pathlib import Path
import time
from icalendar import Calendar
from common import ROOT, RING, STATUS, evidence, login, request, sql, uid

results = []
owner = login('scale-owner@example.invalid')
outsider = login('scale-outsider@example.invalid')


def manage(token, action='create', ring=RING):
    status, value, _, _ = request('/rest/v1/rpc/manage_calendar_subscription', token, method='POST',
                                 body={'p_ring': ring, 'p_action': action, 'p_timezone': 'America/Indiana/Indianapolis'})
    assert status == 200, (status, value)
    return value


def feed(token, expected=200, method='GET'):
    status, value, headers, ms = request('/functions/v1/calendar-feed?token=' + token, method=method)
    assert status == expected, (status, value[:200] if isinstance(value, str) else value)
    return value, headers, ms


def events(raw):
    calendar = Calendar.from_ical(raw)
    rows = calendar.walk('VEVENT')
    keys = [str(e['UID']) for e in rows]
    assert len(keys) == len(set(keys)), 'Duplicate calendar UIDs'
    for event in rows:
        assert not event.errors, event.errors
        assert event.decoded('DTEND') > event.decoded('DTSTART')
    return {str(e['UID']): e for e in rows}


def check(name, fn):
    start = time.monotonic()
    try:
        detail = fn()
        r = {'test': name, 'passed': True, 'milliseconds': round((time.monotonic() - start) * 1000), 'detail': detail}
    except Exception as error:
        r = {'test': name, 'passed': False, 'error': str(error)}
    results.append(r)
    evidence('calendar-lifecycle-results.json', results)
    print(json.dumps(r), flush=True)


def lifecycle():
    a = manage(owner)
    b = manage(owner)
    assert a['token'] == b['token'], 'Create must preserve the existing subscription'
    raw, headers, ms = feed(a['token'])
    parsed = events(raw)
    assert len(parsed) > 1000
    headers = {k.lower(): v for k, v in headers.items()}
    assert headers.get('content-type', '').startswith('text/calendar'), 'Incorrect feed content type'
    assert 'no-store' in headers.get('cache-control', ''), 'Feed may be cached'
    assert raw.endswith('\r\n') and all(len(line.encode()) <= 75 for line in raw.split('\r\n'))
    head, _, _ = feed(a['token'], method='HEAD')
    assert head == ''
    start = date.today().replace(day=1)
    start = (start - timedelta(days=1)).replace(day=1)
    assert all(e.decoded('DTSTART') >= start for e in parsed.values())
    again = events(feed(a['token'])[0])
    assert set(again) == set(parsed), 'Refresh changed event identities'
    return {'event_count': len(parsed), 'feed_bytes': len(raw.encode()), 'first_allowed_date': str(start),
            'cold_feed_ms': ms, 'repeat_poll_preserves_all_uids': True, 'head_returns_no_body': True}


def distant_dates_and_updates():
    marker = uid('rmb-next-calendar-sentinel')
    animal = uid('rmb-scale-animal-1')
    start = (date.today().replace(day=1) - timedelta(days=1)).replace(day=1)
    sql(f"""insert into animal_health_records(id,animal_id,record_type,title,administered_date,readminister_date,expires_date,retention)
    values('{marker}','{animal}','health',E'Synthetic 🐇 \\nBEGIN:VEVENT,semicolon;','1999-01-01','{start}','2035-12-01','never')
    on conflict(id) do update set readminister_date=excluded.readminister_date;""")
    link = manage(owner)['token']
    parsed = events(feed(link)[0])
    prefix = 'health-' + marker + '-'
    initial = parsed[prefix + 'readminister_date@breeder.ringmasterone.com']
    assert initial.decoded('DTSTART') == start
    assert prefix + 'administered_date@breeder.ringmasterone.com' not in parsed
    assert parsed[prefix + 'expires_date@breeder.ringmasterone.com'].decoded('DTSTART') == date(2035, 12, 1)
    assert str(initial['SUMMARY']).count('BEGIN:VEVENT') == 1
    changed = start + timedelta(days=2)
    sql(f"update animal_health_records set readminister_date='{changed}' where id='{marker}';")
    updated = events(feed(link)[0])
    assert updated[prefix + 'readminister_date@breeder.ringmasterone.com'].decoded('DTSTART') == changed
    assert set(updated) == set(parsed)
    sql(f"delete from animal_health_records where id='{marker}';")
    deleted = events(feed(link)[0])
    assert all(not key.startswith(prefix) for key in deleted)
    return {'history_1999_excluded': True, 'previous_month_boundary_included': True, 'future_2035_retained': True,
            'updated_event_keeps_uid': True, 'deleted_events_disappear_on_poll': True, 'unicode_and_injection_parsed': True}


def rotate_revoke():
    old = manage(owner)['token']
    new = manage(owner, 'rotate')['token']
    assert old != new
    feed(old, 404)
    events(feed(new)[0])
    assert manage(owner, 'revoke')['enabled'] is False
    feed(new, 404)
    # Leave a fresh owner subscription for the local native-calendar check.
    link = manage(owner)
    Path('/private/tmp/rmb-next-stress/test-subscription.json').write_text(json.dumps(link))
    return {'old_link_rejected_after_rotation': True, 'revoked_link_rejected': True}


def access_denials():
    for token, expected in [(owner, 403), (STATUS['ANON_KEY'], 401)]:
        status, _, _, _ = request('/rest/v1/rpc/resolve_calendar_subscription', token, method='POST', body={'p_token': 'x'})
        assert status == expected, status
    status, _, _, _ = request('/rest/v1/rpc/manage_calendar_subscription', outsider, method='POST', body={'p_ring': RING, 'p_action': 'create'})
    assert status == 403, status
    feed('invalid', 404)
    feed('f' * 64, 404)
    feed('f' * 64, 405, 'POST')
    sql("insert into public.users(id,auth_user_id,username,email) values('scale-member','e1000000-0000-4000-8000-000000000002','scale-member','scale-member@example.invalid') on conflict do nothing;")
    member = login('scale-member@example.invalid')
    link = manage(member)['token']
    sql("update public.users set is_active=false where id='scale-member';")
    try:
        feed(link, 404)
    finally:
        sql("update public.users set is_active=true where id='scale-member';")
    return {'authenticated_resolver_denied': True, 'anonymous_resolver_denied': True,
            'outsider_cannot_subscribe': True, 'invalid_tokens_rejected': True, 'disabled_subscriber_rejected': True}


def member_revocation():
    sql("insert into public.users(id,auth_user_id,username,email) values('scale-member','e1000000-0000-4000-8000-000000000002','scale-member','scale-member@example.invalid') on conflict do nothing;")
    member = login('scale-member@example.invalid')
    token = manage(member)['token']
    assert len(events(feed(token)[0])) > 1000
    sql("update breeder_private.invitations set revoked_at=now() where member_user_id='e1000000-0000-4000-8000-000000000002';")
    try:
        feed(token, 404)
        events(feed(manage(owner)['token'])[0])
    finally:
        sql("update breeder_private.invitations set revoked_at=null where member_user_id='e1000000-0000-4000-8000-000000000002';")
    return {'member_feed_works': True, 'revoked_member_link_stops': True, 'owner_feed_remains_available': True}


for name, fn in [('actual_http_subscription_lifecycle', lifecycle), ('date_boundaries_and_refresh', distant_dates_and_updates),
                 ('rotate_and_revoke', rotate_revoke), ('actual_http_access_denials', access_denials), ('family_membership_revocation', member_revocation)]:
    check(name, fn)
if any(not r['passed'] for r in results):
    raise SystemExit(1)

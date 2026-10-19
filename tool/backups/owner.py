"""Snapshot recovery for one herd owner, preserving live access and newer rows.

This is deliberately an admin tool, not a client RPC. SQL constraints remain on.
No deletes: recovering a point never cascades into another family's records.
"""
import argparse
import json
import os
from pathlib import Path

from common import Database, ident, literal, sha256, write_json


# Parent-before-child order. Every selected FK to a selected table is validated.
TABLES = [
    'farms', 'animals', 'breeding_settings', 'breeding_records',
    'breeding_tracking', 'breeding_offspring', 'animal_weights',
    'animal_health_records', 'pedigree_drafts', 'animal_sales',
    'animal_sale_payments', 'animal_sale_history', 'breeder_exhibitor_profiles',
    'breeder_imported_animals', 'breeder_show_history', 'global_pedigree_animals',
    'global_pedigree_history', 'rabbit_register_sources', 'rabbit_register_animals',
    'rabbit_register_records', 'kintraks_sources', 'kintraks_animals',
]
PRESERVED = [
    'public.users', 'public.user_licenses', 'public.license_tiers',
    'public.species', 'public.breeds', 'public.varieties',
    'public.show_connections', 'public.connected_show_reports',
    'public.account_deletions', 'public.breeder_legal_acceptances',
    'public.breeder_offline_jobs', 'public.breeder_offline_receipts',
    'public.pedigree_buyer_emails', 'public.global_pedigree_import_drafts',
    'public.global_pedigree_sales_source_previews',
    'breeder_private.invitations', 'breeder_private.calendar_subscriptions',
    'breeder_private.offline_versions', 'breeder_private.support_audit',
    'breeder_private.super_admins', 'breeder_private.testing_access',
]


def relation(table, stage=False):
    return ('pg_temp.' + ident('recover_' + table) if stage
            else 'public.' + ident(table))


def scope(table, owner, stage=False):
    farms = f'SELECT id FROM {relation("farms", stage)} WHERE owner_id={literal(owner)}'
    animals = f'SELECT id FROM {relation("animals", stage)} WHERE ring_id IN ({farms})'
    breedings = (f'SELECT id FROM {relation("breeding_records", stage)} '
                 f'WHERE sire_id IN ({animals}) AND dam_id IN ({animals})')
    sales = f'SELECT id FROM {relation("animal_sales", stage)} WHERE ring_id IN ({farms})'
    if table == 'farms':
        return f't.owner_id={literal(owner)}'
    if table in ('breeder_exhibitor_profiles', 'breeder_imported_animals', 'breeder_show_history'):
        return f't.owner_id={literal(owner)}'
    if table in ('animal_weights', 'animal_health_records'):
        return f't.animal_id IN ({animals})'
    if table == 'breeding_records':
        # Include mixed-family records so FK validation refuses ambiguous recovery.
        return f'(t.sire_id IN ({animals}) OR t.dam_id IN ({animals}))'
    if table == 'breeding_tracking':
        return f't.breeding_id IN ({breedings})'
    if table == 'breeding_offspring':
        return f'(t.breeding_id IN ({breedings}) OR t.animal_id IN ({animals}))'
    if table in ('animal_sale_payments', 'animal_sale_history'):
        return f't.sale_id IN ({sales})'
    return f't.ring_id IN ({farms})'


def schema(db):
    return db.json("""SELECT coalesce(jsonb_object_agg(name, cols),'{}') FROM (
      SELECT c.relname name, jsonb_agg(jsonb_build_object('name',a.attname,
        'type',format_type(a.atttypid,a.atttypmod)) ORDER BY a.attnum) cols
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
      WHERE n.nspname='public' AND c.relkind='r'
      GROUP BY c.relname) x;""")


def export_owner(db, owner, created_at):
    identity = db.json('SELECT row_to_json(t) FROM (SELECT id,auth_user_id FROM '
                       f'public.users WHERE id={literal(owner)}) t;')
    shapes = schema(db)
    rows = {}
    for table in TABLES:
        rows[table] = db.json(f"SELECT coalesce(jsonb_agg(to_jsonb(t)),'[]') FROM "
                             f'{relation(table)} t WHERE {scope(table, owner)};')
    # A connection may since have been revoked/deleted. Retained report content
    # remains useful without reviving its synchronization link.
    for row in rows['breeder_show_history']:
        row['report_connection_id'] = None
    return dict(format='ringmaster-breeder-owner', version=1, owner=identity,
                created_at=created_at, schema={t: shapes[t] for t in TABLES}, tables=rows)


def primary_keys(db):
    return db.json("""SELECT jsonb_object_agg(name,cols) FROM (
      SELECT c.relname name,jsonb_agg(a.attname ORDER BY k.ordinality) cols
      FROM pg_constraint p JOIN pg_class c ON c.oid=p.conrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace
      CROSS JOIN LATERAL unnest(p.conkey) WITH ORDINALITY k(attnum,ordinality)
      JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=k.attnum
      WHERE p.contype='p' AND n.nspname='public' GROUP BY c.relname) x;""")


def assertion(condition, message):
    body = f'BEGIN IF {condition} THEN RAISE EXCEPTION {literal(message)}; END IF; END;'
    return 'DO ' + literal(body) + ';'


def make_plan(db, data, commit=False):
    if data.get('format') != 'ringmaster-breeder-owner' or data.get('version') != 1:
        raise ValueError('Not a supported owner recovery file')
    if set(data['tables']) != set(TABLES) or set(data['schema']) != set(TABLES):
        raise ValueError('Incomplete recovery table set')
    current_schema = schema(db)
    if any(current_schema.get(t) != data['schema'][t] for t in TABLES):
        raise ValueError('Schema differs from this backup. Migrate a scratch copy first.')
    owner, auth_id = data['owner']['id'], data['owner']['auth_user_id']
    if not auth_id:
        raise ValueError('Recovery requires an existing linked owner identity')
    keys = primary_keys(db)
    sql = ['BEGIN;', 'SET LOCAL standard_conforming_strings=on;',
           "SET LOCAL lock_timeout='15s';", "SET LOCAL statement_timeout='10min';",
           # Lock before validating live ownership. Foreign keys stay enabled.
           'LOCK TABLE ' + ','.join(relation(t) for t in TABLES) + ',public.users,public.account_deletions IN SHARE ROW EXCLUSIVE MODE;',
           assertion(f'NOT EXISTS(SELECT 1 FROM public.users WHERE id={literal(owner)} '
                     f'AND auth_user_id::text={literal(auth_id)} AND is_active)',
                     'Owner identity changed, missing or inactive; manual review required'),
           assertion(f'EXISTS(SELECT 1 FROM public.account_deletions WHERE owner_id={literal(owner)})',
                     'Account deletion is pending')]
    sql.append(assertion("EXISTS(SELECT 1 FROM pg_trigger g JOIN pg_class c ON c.oid=g.tgrelid "
                         "JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' "
                         f"AND c.relname IN ({','.join(literal(t) for t in TABLES)}) "
                         "AND NOT g.tgisinternal AND g.tgenabled<>'O')",
                         'Nonstandard trigger state requires manual review'))
    for table in TABLES:
        rows = data['tables'][table]
        cols = [c['name'] for c in data['schema'][table]]
        if not isinstance(rows, list) or any(set(r) != set(cols) for r in rows):
            raise ValueError(f'Invalid row shape: {table}')
        sql += [f'CREATE TEMP TABLE recover_{table} (LIKE {relation(table)}) ON COMMIT DROP;',
                f'INSERT INTO {relation(table, True)} SELECT * FROM jsonb_populate_recordset('
                f'NULL::{relation(table)}, {literal(json.dumps(rows))}::jsonb);']
    for table in TABLES:
        staged = relation(table, True)
        match = ' AND '.join(f't.{ident(k)}=s.{ident(k)}' for k in keys[table])
        sql += [assertion(f'EXISTS(SELECT 1 FROM {staged} t WHERE NOT coalesce(({scope(table, owner, True)}),false))',
                          f'Backup row outside owner scope: {table}'),
                assertion(f'EXISTS(SELECT 1 FROM {relation(table)} t JOIN {staged} s ON {match} '
                          f'WHERE NOT coalesce(({scope(table, owner)}),false))',
                          f'ID belongs to another owner: {table}')]
    # Check all FK edges between restored tables. Prevent foreign pedigree links,
    # mixed-family breedings, and imports that point into another household.
    fks = db.json("""SELECT coalesce(jsonb_agg(jsonb_build_object('child',c.relname,
       'parent',p.relname,'child_cols',ck.cols,'parent_cols',pk.cols)),'[]')
       FROM pg_constraint f JOIN pg_class c ON c.oid=f.conrelid
       JOIN pg_class p ON p.oid=f.confrelid
       JOIN pg_namespace cn ON cn.oid=c.relnamespace
       JOIN pg_namespace pn ON pn.oid=p.relnamespace
       CROSS JOIN LATERAL (SELECT jsonb_agg(a.attname ORDER BY k.i) cols
         FROM unnest(f.conkey) WITH ORDINALITY k(n,i)
         JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=k.n) ck
       CROSS JOIN LATERAL (SELECT jsonb_agg(a.attname ORDER BY k.i) cols
         FROM unnest(f.confkey) WITH ORDINALITY k(n,i)
         JOIN pg_attribute a ON a.attrelid=p.oid AND a.attnum=k.n) pk
       WHERE f.contype='f' AND cn.nspname='public' AND pn.nspname='public';""")
    for fk in fks:
        if fk['child'] not in TABLES or fk['parent'] not in TABLES:
            continue
        match = ' AND '.join(f't.{ident(c)}=p.{ident(p)}' for c, p in zip(fk['child_cols'], fk['parent_cols']))
        present = ' AND '.join(f't.{ident(c)} IS NOT NULL' for c in fk['child_cols'])
        sql.append(assertion(f'EXISTS(SELECT 1 FROM {relation(fk["child"], True)} t WHERE {present} '
                             f'AND NOT EXISTS(SELECT 1 FROM {relation(fk["parent"], True)} p WHERE {match}))',
                             'Backup contains incomplete or cross-owner relationships'))
    # A sandbox dry run executes all constraints and rolls everything back.
    for table in TABLES:
        sql.append(f'ALTER TABLE {relation(table)} DISABLE TRIGGER USER;')
    for table in TABLES:
        cols = [c['name'] for c in data['schema'][table]]
        values = ['NULL' if table == 'animals' and c in ('sire_id', 'dam_id') else 's.' + ident(c) for c in cols]
        if table == 'animals':
            values[cols.index('revision')] = '(extract(epoch from clock_timestamp())*1000000)::bigint'
        for version_column in ('version', 'revision'):
            if table != 'animals' and version_column in cols:
                match = ' AND '.join(f'v.{ident(k)}=s.{ident(k)}' for k in keys[table])
                values[cols.index(version_column)] = (
                    f'greatest(s.{ident(version_column)},coalesce((SELECT v.{ident(version_column)} '
                    f'FROM {relation(table)} v WHERE {match}),0))+1')
        updates = ','.join(f'{ident(c)}=excluded.{ident(c)}' for c in cols if c not in keys[table])
        sql.append(f'INSERT INTO {relation(table)} ({",".join(map(ident, cols))}) '
                   f'SELECT {",".join(values)} FROM {relation(table, True)} s '
                   f'ON CONFLICT ({",".join(map(ident, keys[table]))}) DO UPDATE SET {updates};')
    sql.append('UPDATE public.animals a SET sire_id=s.sire_id,dam_id=s.dam_id '
               'FROM pg_temp.recover_animals s WHERE a.id=s.id;')
    # Disabled statement triggers must be compensated so offline clients see recovery.
    for table in TABLES:
        sql.append(f'ALTER TABLE {relation(table)} ENABLE TRIGGER USER;')
        sql.append('INSERT INTO breeder_private.offline_versions(name,version) '
                   f'VALUES({literal(table)},1) ON CONFLICT(name) DO UPDATE '
                   'SET version=breeder_private.offline_versions.version+1;')
    sql.append('COMMIT;' if commit else 'ROLLBACK;')
    return '\n'.join(sql) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('--output', type=Path, required=True, help='New private review directory')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--confirm-owner')
    parser.add_argument('--maintenance-confirmed', action='store_true')
    args = parser.parse_args()
    os.umask(0o077)
    data = json.loads(args.snapshot.read_text())
    args.output.mkdir(mode=0o700, parents=True, exist_ok=False)
    with Database(os.environ['RESTORE_DB_URL']) as db:
        plan = make_plan(db, data, commit=args.apply)
        (args.output / 'restore.sql').write_text(plan)
        write_json(args.output / 'review.json', {
            'owner': data['owner'], 'backup_point': data['created_at'],
            'snapshot_sha256': sha256(args.snapshot),
            'mode': 'recover_snapshot_rows_preserve_newer_rows',
            'counts': {t: len(data['tables'][t]) for t in TABLES},
            'preserved': PRESERVED,
            'files': 'Restore snapshot file objects before applying this plan; see runbook.'})
        if args.apply and (args.confirm_owner != data['owner']['id'] or not args.maintenance_confirmed):
            raise ValueError('Apply requires --confirm-owner and --maintenance-confirmed')
        if args.apply and not data.get('media_prepared'):
            raise ValueError('Run files.py first, including accounts with no media')
        db.execute(plan)
    print('Recovery committed.' if args.apply else 'Recovery dry run passed; all writes rolled back.')


if __name__ == '__main__':
    main()

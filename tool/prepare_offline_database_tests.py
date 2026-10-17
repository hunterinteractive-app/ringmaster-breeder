#!/usr/bin/env python3
"""Prepare rollback-only SQL checks for an isolated copy of the Breeder schema.

Does not connect to a database. Run the emitted SQL only against a disposable
local database with the Phase 1 migrations and existing storage policies applied.
"""
import json
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='breeder-offline-fixtures-') as directory:
    operation = pathlib.Path(directory) / 'operation.json'
    workflows = pathlib.Path(directory) / 'workflows.json'
    subprocess.run(['node', str(root / 'tool/offline_workspace_test.cjs'), '--fixtures', str(operation)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['node', str(root / 'tool/offline_workflow_fixtures.cjs'), str(workflows)], check=True)
    sql = ''
    for name, path in [('offline_operation', operation), ('offline_workflows', workflows)]:
        value = json.dumps(json.loads(path.read_text()))
        assert '$fixture$' not in value
        sql += f"select set_config('fixture.{name}',$fixture${value}$fixture$,false);\n"
    sql += (root / 'supabase/tests/offline_workspace.sql').read_text()
    pathlib.Path(sys.argv[1]).write_text(sql)

#!/usr/bin/env python3
"""Package a flagged Flutter web build for local offline testing.

Run after: flutter build web --release --pwa-strategy=none --dart-define=OFFLINE_PILOT=true
Does not modify source web files or publish anything.
"""
import hashlib
import json
import pathlib
import sys


def prepare(root):
    root = pathlib.Path(root).resolve()
    for required in ('index.html', 'main.dart.js', 'flutter_bootstrap.js', 'offline_store.js'):
        if not (root / required).is_file():
            raise SystemExit(f'Missing Flutter build asset: {required}')
    # Avoid enabling cached application loading on an unflagged Dart build.
    if 'Offline pilot: downloaded animals' not in (root / 'main.dart.js').read_text():
        raise SystemExit('Build with --dart-define=OFFLINE_PILOT=true first.')
    # CanvasKit always loads a family named Roboto as its default fallback. Use
    # our bundled font for that fallback in the pilot instead of fetching a CDN.
    manifest_path = root / 'assets/FontManifest.json'
    fonts = json.loads(manifest_path.read_text())
    if not any(font['family'] == 'Roboto' for font in fonts):
        bundled = next((font for font in fonts if font['family'] == 'BreederSans'), None)
        if bundled is None:
            raise SystemExit('Bundled BreederSans UI font is missing.')
        fonts.append({**bundled, 'family': 'Roboto'})
        manifest_path.write_text(json.dumps(fonts))
    (root / 'offline_config.js').write_text('window.BREEDER_OFFLINE_BUILD = true;\n')
    excluded = {'breeder-offline-worker.js', 'flutter_service_worker.js', '_headers', '_redirects'}
    files = sorted(p.relative_to(root).as_posix() for p in root.rglob('*')
                   if p.is_file() and p.name not in excluded and not p.name.endswith('.map'))
    digest = hashlib.sha256()
    template = pathlib.Path(__file__).with_name('offline_worker.template.js').read_text()
    digest.update(template.encode())
    for name in files:
        digest.update(name.encode())
        digest.update((root / name).read_bytes())
    revision = digest.hexdigest()[:20]
    worker = template.replace('__REVISION__', json.dumps(revision)).replace('__FILES__', json.dumps(files))
    (root / 'breeder-offline-worker.js').write_text(worker)
    total = sum((root / name).stat().st_size for name in files)
    print(f'Offline pilot packaged: {len(files)} assets, {total / 1024 / 1024:.1f} MB, version {revision}')


if __name__ == '__main__':
    prepare(sys.argv[1] if len(sys.argv) > 1 else 'build/web')

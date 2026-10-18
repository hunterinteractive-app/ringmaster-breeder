const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const web = path.join(__dirname, '..', 'web');
const viewportSource = fs.readFileSync(path.join(web, 'browser_viewport.js'), 'utf8');
const bootstrap = fs.readFileSync(path.join(web, 'flutter_bootstrap.js'), 'utf8')
  .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '');

function viewportFixture(overrides = {}) {
  const window = new EventTarget();
  window.visualViewport = new EventTarget();
  Object.assign(window.visualViewport, { height: 72, scale: 1 });
  const input = { tagName: 'INPUT', value: 'Unsaved barn edit' };
  const document = { activeElement: input, documentElement: { clientHeight: 325 } };
  const timers = new Map();
  let id = 0, resizes = 0;
  window.visualViewport.addEventListener('resize', () => resizes++);
  const context = {
    window, document, Event,
    navigator: { userAgent: 'iPhone', platform: 'iPhone', maxTouchPoints: 5 },
    setTimeout: callback => { timers.set(++id, callback); return id; },
    clearTimeout: key => timers.delete(key),
    ...overrides,
  };
  vm.runInNewContext(viewportSource, context);
  return {
    window, document, input,
    rotate: () => window.dispatchEvent(new Event('orientationchange')),
    flush: () => { const pending = [...timers.values()]; timers.clear(); pending.forEach(fn => fn()); },
    resizes: () => resizes,
    pending: () => timers.size,
  };
}

async function main() {
  const f = viewportFixture();
  f.rotate();
  f.rotate();
  assert.equal(f.pending(), 3, 'A second rotation replaces pending measurements');
  f.flush();
  assert.equal(f.resizes(), 3);
  assert.equal(f.document.activeElement, f.input);
  assert.equal(f.input.value, 'Unsaved barn edit');
  f.window.visualViewport.height = 325;
  f.rotate(); f.flush();
  assert.equal(f.resizes(), 3, 'Dismissing the keyboard needs no correction');
  f.window.visualViewport.height = 72;
  f.window.visualViewport.scale = 1.5;
  f.rotate(); f.flush();
  assert.equal(f.resizes(), 3, 'Pinch zoom must not be treated as a keyboard');
  f.window.visualViewport.scale = 1;
  f.document.activeElement = { tagName: 'BODY' };
  f.rotate(); f.flush();
  assert.equal(f.resizes(), 3, 'No focused input needs no keyboard correction');
  const android = viewportFixture({ navigator: { userAgent: 'Android', platform: 'Linux', maxTouchPoints: 5 } });
  android.rotate(); android.flush();
  assert.equal(android.resizes(), 0);

  for (const hash of ['#/animals', '#/add-animal', '#/animal-detail', '#/edit-animal', '#/weight-history', '#/animal-detail?test=1', '#/sales', '#/calendar', '#/account', '']) {
    let replacement = null, loads = 0;
    const context = {
      window: {}, navigator: {},
      location: { hash, pathname: '/', search: '?source=test' },
      history: { state: { fixture: true }, replaceState: (state, title, url) => { replacement = { state, url }; } },
      _flutter: { loader: { load: () => loads++ } },
      document: { body: {} },
    };
    await vm.runInNewContext(bootstrap, context);
    assert.equal(loads, 1);
    const record = !['#/sales', '#/calendar', '#/account', ''].includes(hash);
    assert.equal(replacement?.url ?? null, record ? '/?source=test' : null, hash);
    if (record) assert.equal(replacement.state, context.history.state);
  }
  console.log('PASS browser rotation recovery preserves drafts, respects zoom, and safely reopens record URLs');
}
main().catch(error => { console.error(error); process.exitCode = 1; });

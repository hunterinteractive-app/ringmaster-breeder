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
  let now = 10000, scrolls = 0;
  Object.assign(window, {
    scrollX: 0, scrollY: 0,
    scrollTo: (x, y) => { window.scrollX = x; window.scrollY = y; scrolls++; },
  });
  window.visualViewport.addEventListener('resize', () => resizes++);
  const context = {
    window, document, Event, Date: { now: () => now },
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
    advance: ms => { now += ms; },
    scrolls: () => scrolls,
  };
}

async function main() {
  const f = viewportFixture();
  f.rotate();
  f.rotate();
  assert.equal(f.pending(), 4, 'A second rotation replaces pending measurements');
  f.flush();
  assert.equal(f.resizes(), 4);
  assert.equal(f.document.activeElement, f.input);
  assert.equal(f.input.value, 'Unsaved barn edit');
  f.window.visualViewport.height = 325;
  f.rotate(); f.flush();
  assert.equal(f.resizes(), 4, 'Dismissing the keyboard needs no correction');
  f.window.visualViewport.height = 72;
  f.window.visualViewport.scale = 1.5;
  f.rotate(); f.flush();
  f.window.scrollY = 121;
  f.window.visualViewport.dispatchEvent(new Event('scroll'));
  assert.equal(f.scrolls(), 0, 'Rotation recovery must respect pinch zoom');
  assert.equal(f.resizes(), 4, 'Pinch zoom must not be treated as a keyboard');
  f.window.visualViewport.scale = 1;
  f.window.visualViewport.dispatchEvent(new Event('scroll'));
  assert.equal(f.window.scrollY, 0, 'Undo Safari document panning after rotation');
  assert.equal(f.scrolls(), 1);
  assert.equal(f.input.value, 'Unsaved barn edit');
  assert.equal(f.document.activeElement, f.input);
  f.advance(2501);
  f.window.scrollY = 121;
  f.window.visualViewport.dispatchEvent(new Event('scroll'));
  assert.equal(f.scrolls(), 1, 'Do not keep overriding scrolling after rotation settles');
  f.document.activeElement = { tagName: 'BODY' };
  f.rotate(); f.flush();
  assert.equal(f.resizes(), 5, 'No focused input needs no keyboard correction');
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

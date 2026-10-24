/* Run after packaging build/web. Requires Playwright on NODE_PATH.
 * The served bundle uses a loopback fixture backend, never a live database.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { chromium, webkit } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(process.argv[2] || 'build/web');
const freshLogin = process.env.FRESH_LOGIN === 'true';
const fullWorkspace = process.env.FULL_WORKSPACE === 'true';
const legalSource=fs.readFileSync(path.resolve(__dirname,'../lib/config/legal_config.dart'),'utf8');
const termsVersion=legalSource.match(/termsVersion\s*=\s*'([^']+)'/)[1];
const privacyVersion=legalSource.match(/privacyVersion\s*=\s*'([^']+)'/)[1];
const liveBackend = 'https://aqfsrolvaewcpkdkttiz.supabase.co';
let fixtureOrigin, fixtureHandler, originOffline = false;
const mime = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm',
  '.json': 'application/json', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf' };
const server = http.createServer(async (req, res) => {
  if (req.url.startsWith('/__supabase/')) {
    if (!fixtureHandler) { res.writeHead(503); return res.end(); }
    try { return await fixtureHandler(req, res); }
    catch (error) { res.writeHead(500); return res.end(JSON.stringify({ message: String(error) })); }
  }
  if (originOffline) {
    res.writeHead(503);
    return res.end('Fixture application server unavailable');
  }
  // Match Cloudflare Pages' canonical index redirect. A cached redirected HTML
  // response must be normalized before answering an offline navigation.
  if (new URL(req.url, 'http://localhost').pathname === '/index.html') {
    res.writeHead(308, { Location: '/' });
    return res.end();
  }
  if (req.url === '/__storage-probe') {
    res.setHeader('Content-Type', 'text/html');
    return res.end('<script src="/offline_store.js"></script><p>Offline storage test</p>');
  }
  const name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  const file = path.resolve(root, '.' + (name === '/' ? '/index.html' : name));
  if (!file.startsWith(root + path.sep) || !fs.existsSync(file)) { res.writeHead(404); return res.end(); }
  res.setHeader('Content-Type', mime[path.extname(file)] || 'application/octet-stream');
  res.setHeader('Cache-Control', 'no-store');
  // Worker-owned fetches can bypass Playwright routes in WebKit. Keep the
  // fixture at the HTTP-server boundary so no engine can contact live Auth/DB.
  if (name === '/main.dart.js') {
    const source = fs.readFileSync(file, 'utf8');
    assert.ok(source.includes(liveBackend));
    return res.end(source.replaceAll(liveBackend, fixtureOrigin + '/__supabase'));
  }
  fs.createReadStream(file).pipe(res);
});

async function main() {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  fixtureOrigin = origin;
  const useWebKit = process.env.BROWSER === 'webkit';
  const executablePath = process.env.BROWSER_BIN || (!useWebKit && process.env.CHROME_BIN);
  const browser = await (useWebKit ? webkit : chromium).launch({ headless: true, ...(executablePath ? { executablePath } : {}) });
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, serviceWorkers: 'allow' });
  const failures = [];
  const consoleErrors = [];
  const externalFontRequests = [];
  context.on('page', page => {
    page.on('pageerror', error => {
      failures.push(error.stack || error.message);
      console.error('Browser runtime error:', error.stack || error.message);
    });
    if(process.env.DEBUG_REQUESTS==='true')page.on('requestfailed',request=>{const url=new URL(request.url());console.error('Fixture request failed:',url.origin+url.pathname,request.failure()?.errorText);});
    if(process.env.DEBUG_REQUESTS==='true')page.on('response',async response=>{if(response.status()>=400)console.error('Fixture HTTP error:',new URL(response.url()).pathname,response.status(),(await response.text().catch(()=>'' )).slice(0,500));});
    page.on('console', message => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });
  });
  let page = await context.newPage();
  try {
    await page.goto(origin + '/__storage-probe');
    const result = await page.evaluate(async () => {
      const api = window.breederOffline;
      await api.commit(JSON.stringify({ expected: { 'probe:a': null }, puts: { 'probe:a': { name: 'Original' } }, deletes: [] }));
      const before = JSON.parse(await api.read('probe:a'));
      const batch = name => JSON.stringify({ expected: { 'probe:a': before.version }, puts: { 'probe:a': { name } }, deletes: [] });
      const race = await Promise.all([api.commit(batch('First')), api.commit(batch('Second'))]);
      const atomic = await api.commit(JSON.stringify({ expected: { 'probe:a': -1 }, puts: { 'probe:unexpected': { bad: true } }, deletes: [] }));
      return { race, atomic, unexpected: JSON.parse(await api.read('probe:unexpected')) };
    });
    assert.equal(result.race.filter(Boolean).length, 1);
    assert.equal(result.atomic, false);
    assert.equal(result.unexpected, null);
    await page.close();
    page = await context.newPage();
    await page.goto(origin + '/__storage-probe');
    assert.equal(await page.evaluate(async () => JSON.parse(await breederOffline.read('probe:a')).version), 2);
    console.log('PASS: real IndexedDB durability, transaction rollback, concurrent version checks');

    const userId = '00000000-0000-4000-8000-000000000001';
    const ringId = '00000000-0000-4000-8000-000000000002';
    const animalId = '00000000-0000-4000-8000-000000000003';
    const user = { id: userId, email: 'offline-fixture@example.invalid', aud: 'authenticated', role: 'authenticated',
      email_confirmed_at: '2026-01-01T00:00:00Z', created_at: '2026-01-01T00:00:00Z', app_metadata: {}, user_metadata: {} };
    const token = [Buffer.from('{"alg":"HS256","typ":"JWT"}').toString('base64url'),
      Buffer.from(JSON.stringify({ sub: userId, exp: Math.floor(Date.now() / 1000) + 86400, role: 'authenticated' })).toString('base64url'), 'fixture'].join('.');
    const session = { access_token: token, refresh_token: 'fixture', token_type: 'bearer',
      expires_in: 86400, expires_at: Math.floor(Date.now() / 1000) + 86400, user };
    await context.addInitScript(({ value, fresh }) => {
      if (location.protocol !== 'http:') return;
      if (!fresh && !localStorage.getItem('sb-127-auth-token')) {
        localStorage.setItem('sb-127-auth-token', JSON.stringify(value));
      }
      if (fresh) {
        let api;
        Object.defineProperty(window, 'breederOffline', {
          configurable: true, get: () => api,
          set(value) {
            api = value;
            const scan = api.scan;
            let first = true;
            api.scan = async function(prefix) {
              if (first && prefix.includes(':op:')) {
                first = false;
                await new Promise(resolve => setTimeout(resolve, 2000));
              }
              return scan.call(this, prefix);
            };
          }
        });
      }
    }, { value: session, fresh: freshLogin });
    let online = true;
    let stallBackend = false;
    let stalledRequests = 0;
    const stalledPaths = [];
    let failAccountCheck = process.env.CHECK_STARTUP_ERROR === 'true';
    const setConnectivity = async available => {
      online = available;
      if (useWebKit) {
        // WebKit's automation offline override can reject navigation before a
        // worker handles it. Deny both fixture servers instead: a reopen must
        // get every app file from the worker and every private read from IDB.
        originOffline = !available;
        if (available) await page.evaluate(() => window.dispatchEvent(new Event('online')));
      } else {
        await context.setOffline(!available);
      }
    };
    const animal = { id: animalId, ring_id: ringId, name: 'Willow', tattoo: 'W1', species: 'rabbit',
      breed: 'Mini Rex', variety: 'Black', sex: 'Doe', status: 'active', revision: 1,
      created_at: '2026-01-01T00:00:00Z', pedigree_only: false, dob: null,
      sire_id: null, dam_id: null, photo_path: null, color_details: {}, registration_number: '', grand_champion_number: '', leg_details: '' };
    const weights = [];
    const fixtureTables={
      animals:[animal],animal_weights:weights,animal_health_records:[],
      farms:[{id:ringId,owner_id:userId,name:'Offline Test Herd',is_demo:false,created_at:'2026-01-01T00:00:00Z'}],
      users:[{id:userId,auth_user_id:userId,username:'fixture',display_name:'Fixture Owner',email:user.email}],
      user_licenses:[{id:'license',user_id:userId,status:'active',tier_code:'TEST',started_at:'2026-01-01T00:00:00Z',expires_at:null}],license_tiers:[{code:'TEST',name:'Test',max_rings:3}],
      breeds:[{id:'breed',name:'Mini Rex',species:'rabbit',is_recognized:true}],varieties:[{id:'variety',breed_id:'breed',name:'Black',is_recognized:true}],species:[],
      breeding_records:[],breeding_settings:[],breeding_tracking:[],breeding_offspring:[],pedigree_drafts:[],
      animal_sales:[],animal_sale_payments:[],animal_sale_history:[],breeder_show_history:[],breeder_exhibitor_profiles:[],breeder_imported_animals:[],
      connected_show_reports:[],show_connections:[],global_pedigree_animals:[],global_pedigree_history:[],global_pedigree_import_drafts:[],breeder_offline_jobs:[],
      account_deletions:[],breeder_legal_acceptances:[{user_id:userId,accepted_at:'2026-01-01T00:00:00Z',terms_version:termsVersion,privacy_version:privacyVersion}],
    };
    if (process.env.RESPONSIVE_SITE === 'true') {
      animal.registration_number = 'REG-123';
      animal.leg_details = 'Best of breed at the county show';
      for (let i = 0; i < 20; i++) weights.push({ id: 'layout-weight-' + i, animal_id: animalId,
        weight: 5 - i / 100, recorded_at: new Date(Date.UTC(2026, 9, 17 - i)).toISOString() });
    }
    const receipts=new Map();
    if (process.env.GROW_OUT_DASHBOARD === 'true') {
      Object.assign(fixtureTables.license_tiers[0],{max_active_animals:1000,annual_price_cents:0});
      fixtureTables.breeder_license_usage=[];
      const sireId='00000000-0000-4000-8000-000000000004';
      const litterId='00000000-0000-4000-8000-000000000005';
      fixtureTables.animals.push({...animal,id:sireId,name:'Grow-out sire',tattoo:'S1',sex:'Buck'});
      fixtureTables.breeding_records=[{id:litterId,sire_id:sireId,dam_id:animalId,breeding_date:'2026-07-01',status:'active'}];
      fixtureTables.breeding_tracking=[{breeding_id:litterId,revision:1,birth_date:'2026-08-01',born_alive:3,born_dead:0,wean_date:'2026-09-15',weaned:3,weaned_males:2,weaned_females:1,weaning_destination:'grow_out',status:'active',cage:'G1'}];
      fixtureTables.litter_weights=[
        {id:'old',breeding_id:litterId,recorded_date:'2026-09-20',weight:8,feed_weight:10,voided:false,revision:1},
        {id:'latest',breeding_id:litterId,recorded_date:'2026-10-01',weight:12,feed_weight:35,voided:false,revision:1},
      ];
    }
    if (process.env.COMPACT_HERD_SCREEN === 'true') {
      animal.sale_status = 'for_sale';
      animal.dob = '2025-02-19';
      fixtureTables.animals.push(
        { ...animal, id: '00000000-0000-4000-8000-000000000004', name: 'Yarrow', tattoo: 'Y2', sale_status: null },
        { ...animal, id: '00000000-0000-4000-8000-000000000005', name: 'Zinnia', tattoo: 'Z3', sale_status: null },
      );
    }
    fixtureHandler = async (request, response) => {
      const url = new URL(request.url.replace('/__supabase', ''), origin);
      response.setHeader('Content-Type', 'application/json');
      if (stallBackend) {
        stalledRequests++;
        stalledPaths.push(url.pathname);
        // Keep navigator.onLine true while the backend never answers promptly.
        const timer = setTimeout(() => {
          response.writeHead(503);
          response.end(JSON.stringify({ code: '503', message: 'Stalled connection' }));
        }, 12000);
        response.on('close', () => clearTimeout(timer));
        return;
      }
      if (!online) {
        response.writeHead(503);
        return response.end(JSON.stringify({ code: '503', message: 'Fixture network unavailable' }));
      }
      if (failAccountCheck && url.pathname.endsWith('/account_deletions')) {
        response.writeHead(403);
        return response.end(JSON.stringify({ code: '42501', message: 'Fixture account check denied' }));
      }
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      if(url.pathname.startsWith('/storage/v1/object/')&&request.method==='POST'){response.end(JSON.stringify({Key:'fixture'}));return;}
      const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : null;
      let data = [];
      if(url.pathname.endsWith('/rpc/breeder_offline_snapshot')){
        if(failAccountCheck){response.writeHead(403);return response.end(JSON.stringify({code:'42501',message:'Fixture account check denied'}));}
        data={protocol:1,tables:fixtureTables,versions:Object.fromEntries(Object.keys(fixtureTables).map(t=>[t,receipts.size+1])),counts:Object.fromEntries(Object.entries(fixtureTables).map(([k,v])=>[k,v.length])),files:[],membership:{households:[{owner_user_id:userId,is_owner:true,label:'Fixture'}],invitations:[]}};
      }
      else if(url.pathname.endsWith('/rpc/breeder_offline_apply')){
        const op=body.p_operation;
        if(!receipts.has(op.id)){
          for(const m of op.mutations){
            const table=fixtureTables[m.table]||(fixtureTables[m.table]=[]);
            const fields=m.table==='breeding_settings'?['ring_id','species']:m.table==='breeding_tracking'?['breeding_id']:m.table==='breeding_offspring'?['animal_id']:['id'];
            const index=table.findIndex(r=>fields.every(k=>r[k]===m.row[k]));
            if(m.action==='delete'){if(index>=0)table.splice(index,1);}
            else if(index<0)table.push({...m.row});
            else {Object.assign(table[index],m.row);if(m.table==='animals')table[index].revision=(table[index].revision||1)+1;}
          }
          receipts.set(op.id,{state:'applied',result:null});
        }
        data=receipts.get(op.id);
      }
      else if(url.pathname.endsWith('/rpc/save_production_measurement') && process.env.GROW_OUT_DASHBOARD === 'true') {
        const index=fixtureTables.litter_weights.findIndex(r=>r.id===body.p_id);
        const row={...body.p_data,id:body.p_id,breeding_id:body.p_parent,revision:body.p_revision+1};
        if(index<0)fixtureTables.litter_weights.push(row);else fixtureTables.litter_weights[index]=row;
        data=null;
      }
      else if(url.pathname.endsWith('/functions/v1/offline-jobs')){
        const prior=fixtureTables.breeder_offline_jobs.find(j=>j.id===body.id);
        if(prior)data=prior;else {data={id:body.id,actor:userId,target:body.target,payload:body.payload,state:body.payload?.requires_sign_in?'needs_input':'complete',result:{fixture:true}};fixtureTables.breeder_offline_jobs.push(data);}
      }
      else if (url.pathname === '/auth/v1/otp') data = {};
      else if (url.pathname === '/auth/v1/verify' || url.pathname === '/auth/v1/token') data = session;
      else if (url.pathname === '/auth/v1/user') data = user;
      else if (url.pathname.endsWith('/rpc/breeder_family_access')) data = { households: [{ owner_user_id: userId, is_owner: true, label: 'Fixture' }], invitations: [] };
      else if (url.pathname.endsWith('/rpc/breeder_license_status')) data = {active:true,code:'TEST',name:'Test',max_rings:3,current_rings:1,max_active_animals:1000,active_count:fixtureTables.animals.length,annual_price_cents:0,growth_blocked:false};
      else if (url.pathname.endsWith('/breeder_legal_acceptances')) data = { accepted_at: '2026-01-01T00:00:00Z' };
      else if (url.pathname.endsWith('/user_licenses')) data = { tier_code: 'TEST', license_tiers: { max_rings: 3 } };
      else if (url.pathname.endsWith('/farms')) data = [{ id: ringId, owner_id: userId, name: 'Offline Test Herd', is_demo: false }];
      else if (url.pathname.endsWith('/animals')) {
        if (request.method === 'PATCH') { Object.assign(animal, body); animal.revision++; }
        data = request.headers.accept?.includes('object') ? { ...animal }
          : Number(url.searchParams.get('offset') || 0) > 0 ? [] : fixtureTables.animals.map(value => ({ ...value }));
      } else if (url.pathname.endsWith('/animal_weights')) {
        if (request.method === 'POST') weights.push(...body);
        data = weights.slice(Number(url.searchParams.get('offset') || 0));
      } else if (url.pathname.endsWith('/breeds')) data = [{ name: 'Mini Rex', species: 'rabbit', is_recognized: true,
        varieties: [{ name: 'Black', is_recognized: true }] }];
      response.end(JSON.stringify(data));
    };
    await context.route('**/*', async route => {
      const url = new URL(route.request().url());
      if (url.origin === origin) return route.continue();
      if (url.hostname === 'fonts.gstatic.com' || url.hostname === 'fonts.googleapis.com') externalFontRequests.push(url.href);
      return route.abort('blockedbyclient');
    });
    const semantics = async () => {
      await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 30000 });
      await page.locator('flt-semantics-placeholder').dispatchEvent('click');
    };
    const herd=()=>page.getByRole('button',{name:/Offline Test Herd/}).or(page.getByText('Offline Test Herd',{exact:false})).first();
    const click = async name => { await page.getByRole('button', { name, exact: true }).click({ timeout: 30000 }); };
    // waitForFunction treats an async predicate's Promise as truthy in some
    // Playwright versions. Poll the resolved IDB result, not the Promise object.
    const waitForOperations = async count => {
      const deadline = Date.now() + 15000;
      while (Date.now() < deadline) {
        const actual = await page.evaluate(async () =>
          JSON.parse(await breederOffline.scan('v1:00000000-0000-4000-8000-000000000001:op:')).length);
        if (actual === count) return;
        await new Promise(resolve => setTimeout(resolve, 50));
      }
      throw new Error(`Expected ${count} durably saved operations`);
    };
    await page.goto(origin);
    await semantics();
    if (freshLogin) {
      await page.getByRole('textbox', { name: 'Email address', exact: true }).click();
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      await page.locator('input:focus, textarea:focus').fill(user.email);
      await page.keyboard.press('Tab');
      await click('Send sign-in code');
      await page.getByRole('textbox', { name: 'Sign-in code', exact: true }).click();
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      await page.keyboard.type('12345678');
      await page.keyboard.press('Tab');
      await click('Sign in');
    }
    if (failAccountCheck) {
      await page.getByText('Reconnect to verify this account before continuing.', { exact: true }).waitFor();
      await click('Sync');
      await page.getByText('Sync status', { exact: true }).waitFor();
      await click('Close');
      failAccountCheck = false;
      await click('Retry account check');
      console.log('PASS: failed account check preserves recovery access and retries without signing out');
    }
    await herd().click({ timeout: 30000 });
    await page.getByText('Willow', { exact: false }).first().waitFor({ timeout: 30000 });
    if (process.env.GROW_OUT_DASHBOARD === 'true') {
      assert.ok(fullWorkspace,'Use FULL_WORKSPACE=true for grow-out browser checks');
      const settle=async()=>{await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));await page.waitForTimeout(200);};
      const fill=async(label,value)=>{
        await page.getByRole('textbox',{name:label,exact:true}).click();await settle();
        await page.locator('input:focus,textarea:focus').fill(value);await page.keyboard.press('Tab');
      };
      const reach=async(label)=>{
        const target=page.getByRole('button',{name:label,exact:true}).first();
        for(let i=0;i<30;i++){
          const box=await target.count()?await target.boundingBox():null;
          const v=page.viewportSize();if(box&&box.y>=55&&box.y+box.height<=v.height-35)return target;
          await page.mouse.move(v.width-15,v.height-100);await page.mouse.wheel(0,160);await settle();
        }throw new Error('Cannot reach '+label);
      };
      await (await reach('Breeding')).click();
      await page.getByText('Grow-out dashboard',{exact:true}).click();
      await page.getByText('Grow-out overview',{exact:true}).waitFor();
      await page.getByText('3 rabbits • 0 cavies',{exact:true}).waitFor();
      await page.getByText('35 lb',{exact:true}).waitFor();
      console.log('PASS: grow-out dashboard loads the group and cumulative totals');
      await page.setViewportSize({width:1280,height:1000});await settle();
      await page.screenshot({path:'/tmp/breeder-grow-out-dashboard-desktop.png'});
      await page.setViewportSize({width:390,height:844});await settle();
      await page.screenshot({path:'/tmp/breeder-grow-out-dashboard-phone.png'});
      await (await reach('Weights & feed')).click();
      await page.getByText('Grow-out weights & feed',{exact:true}).waitFor();
      await click('Record feed & weight');
      await fill('Total group weight (lb) · optional','13');
      await fill('Cumulative group feed (lb) · optional','40');
      await click('Save');
      await page.getByText('40 lb cumulative feed',{exact:false}).first().waitFor();
      console.log('PASS: grow-out weight and feed save appears in measurement history');
      await click('Back');
      await page.getByText('40 lb',{exact:true}).waitFor();
      await (await reach('Create individual records')).click();
      await page.getByRole('checkbox').first().click();
      await fill('Ear number / tag','GROWKEEP');
      await click('Create 1 animal');
      await page.getByText('2 growing out',{exact:true}).waitFor();
      await page.getByText('2 rabbits • 0 cavies',{exact:true}).waitFor();
      await setConnectivity(false);
      await click('Refresh');
      await page.getByText('2 growing out',{exact:true}).waitFor();
      await page.getByText('40 lb',{exact:true}).waitFor();
      assert.deepEqual(failures,[]);
      console.log('PASS: dedicated grow-out dashboard totals, phone/desktop rendering, weight/feed saves, selected individual records, and offline refresh');
      return;
    }
    if (process.env.COMPACT_HERD_SCREEN === 'true') {
      const settle = async () => {
        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        await page.waitForTimeout(200);
      };
      await page.setViewportSize({ width: 360, height: 520 });
      await settle();
      const card = name => page.getByRole('button', { name: new RegExp(name) }).first();
      const boxes = await Promise.all(['Willow', 'Yarrow', 'Zinnia'].map(name => card(name).boundingBox()));
      boxes.sort((a, b) => a.y - b.y);
      const [first, second] = boxes;
      assert.ok(first && first.y < 220 && first.height < 180, 'The first phone card must be compact and immediately visible');
      assert.ok(second && second.y + second.height <= 490, 'Two whole animals should fit without scrolling on the small phone');
      await page.screenshot({ path: `/tmp/breeder-compact-herd-${useWebKit ? 'webkit' : 'chrome'}.png` });
      await click('Filters');
      await page.getByText('All breeds', { exact: false }).first().waitFor();
      await click('Hide filters');
      await page.getByRole('radio', { name: 'List view', exact: true }).click();
      await page.getByRole('radio', { name: 'Card view', exact: true }).click();
      await page.setViewportSize({ width: 1280, height: 900 });
      await settle();
      const wide = await card('Yarrow').boundingBox();
      assert.ok(wide.height > first.height * 1.7, 'Wide screens retain the full card details');
      await page.screenshot({ path: `/tmp/breeder-compact-herd-desktop-${useWebKit ? 'webkit' : 'chrome'}.png` });
      await page.setViewportSize({ width: 360, height: 520 });
      await settle();
      await page.mouse.move(180, 420);
      await page.mouse.wheel(0, 200);
      await settle();
      await card('Willow').click();
      await page.getByText('Animal Details', { exact: false }).first().waitFor();
      assert.deepEqual(failures, []);
      console.log(`PASS: two complete phone cards, collapsible filters, view switching, full desktop cards, and opening details (${useWebKit ? 'WebKit' : 'Chrome'})`);
      return;
    }
    if (process.env.RESPONSIVE_FORM === 'true') {
      await page.getByText('Willow', { exact: false }).first().click();
      await click('Edit Animal');
      const settle = async () => {
        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        await page.waitForTimeout(150);
      };
      const name = page.getByRole('textbox', { name: 'Name', exact: true });
      await name.click();
      await settle();
      await page.locator('input:focus, textarea:focus').fill('Unsaved barn edit');
      // Model a browser that resizes its viewport when the phone keyboard opens.
      await page.setViewportSize({ width: 360, height: 260 });
      await settle();
      assert.equal(await page.locator('input:focus, textarea:focus').inputValue(), 'Unsaved barn edit');
      const nameBox = await name.boundingBox();
      assert.ok(nameBox && nameBox.y >= 50 && nameBox.y + nameBox.height <= 260, 'The focused name must fit above the keyboard');
      await page.getByRole('button', { name: 'Sync', exact: true }).waitFor();
      await page.getByRole('button', { name: 'Page menu', exact: true }).waitFor();
      await page.screenshot({ path: `/tmp/breeder-responsive-keyboard-${useWebKit ? 'webkit' : 'chrome'}.png` });
      const scrollTo = async label => {
        const target = page.getByRole('textbox', { name: label, exact: true });
        for (let attempt = 0; attempt < 40; attempt++) {
          const box = await target.count() ? await target.boundingBox() : null;
          if (box && box.y >= 56 && box.y + box.height <= 260) return target;
          await page.mouse.move(180, 180);
          await page.mouse.wheel(0, 80);
          await settle();
        }
        throw new Error(`Field ${label} was unreachable above the keyboard`);
      };
      const registration = await scrollTo('Registration Number');
      await registration.click();
      await settle();
      await page.locator('input:focus, textarea:focus').fill('BARN-42');
      for (let attempt = 0; attempt < 30; attempt++) {
        const save = page.getByRole('button', { name: 'Save Changes', exact: true });
        const box = await save.count() ? await save.boundingBox() : null;
        if (box && box.height >= 40 && box.y >= 56 && box.y + box.height <= 260) break;
        await page.mouse.move(340, 180);
        await page.mouse.wheel(0, 100);
        await settle();
        if (attempt === 29) throw new Error('Save Changes was unreachable above the keyboard: ' + JSON.stringify(box));
      }
      await page.screenshot({ path: `/tmp/breeder-responsive-save-${useWebKit ? 'webkit' : 'chrome'}.png` });
      await page.setViewportSize({ width: 1280, height: 900 });
      await settle();
      await page.mouse.move(640, 500);
      await page.mouse.wheel(0, -4000);
      await settle();
      await name.waitFor();
      await name.click();
      await settle();
      assert.equal(await page.locator('input:focus, textarea:focus').inputValue(), 'Unsaved barn edit');
      const desktopName = await name.boundingBox();
      assert.ok(desktopName.width <= 1200, 'Desktop forms must remain readable rather than stretching indefinitely');
      await page.screenshot({ path: `/tmp/breeder-responsive-desktop-${useWebKit ? 'webkit' : 'chrome'}.png` });
      assert.deepEqual(failures, []);
      console.log(`PASS: keyboard-sized form, lower fields, save access, persistent draft, Sync/menu, and desktop resize (${useWebKit ? 'WebKit' : 'Chrome'})`);
      return;
    }
    if (process.env.SMALL_HERD_SCREEN === 'true') {
      await page.setViewportSize({ width: 360, height: 520 });
      const settle = async () => {
        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        await new Promise(resolve => setTimeout(resolve, 200));
      };
      const animalVisible = async () => {
        const title = page.getByText('Willow', { exact: false }).first();
        const box = await title.count() ? await title.boundingBox() : null;
        return box && box.y >= 56 && box.y + box.height <= 490;
      };
      await settle();
      await page.mouse.move(180, 410);
      for (let i = 0; i < 8 && !await animalVisible(); i++) {
        await page.mouse.wheel(0, 180);
        await settle();
      }
      assert.ok(await animalVisible(), 'Animal cards must be reachable below the wrapped filters on a short phone');
      if (!useWebKit) {
        const cdp = await context.newCDPSession(page);
        for (let swipe = 0; swipe < 5; swipe++) {
          await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 180, y: 260 }] });
          for (let y = 280; y <= 470; y += 20) {
            await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: 180, y }] });
          }
          await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
          await settle();
        }
        await cdp.detach();
      } else {
        await page.mouse.wheel(0, -2000);
        await settle();
      }
      const search = await page.getByRole('textbox', { name: 'Search animals', exact: true }).boundingBox();
      assert.ok(search && search.y >= 56 && search.y + search.height <= 520, 'The search control must be reachable again after scrolling back');
      await page.mouse.wheel(0, 1600);
      await settle();
      await page.screenshot({ path: `/tmp/breeder-herd-scroll-${useWebKit ? 'webkit' : 'chrome'}.png` });
      await page.getByText('Willow', { exact: false }).first().click({ timeout: 10000 });
      await page.getByText('Animal Details', { exact: false }).first().waitFor({ timeout: 10000 });
      assert.deepEqual(failures, []);
      console.log(`PASS: short-phone herd scrolling reaches animals, returns to filters, and opens details (${useWebKit ? 'WebKit wheel' : 'Chrome wheel and touch'})`);
      return;
    }
    assert.ok(await page.evaluate(async () =>
      JSON.parse(await breederOffline.read('v1:00000000-0000-4000-8000-000000000001:cache:deletion'))),
      'A fresh sign-in must save its account check after delayed storage attachment');
    // The list has downloaded the animal, but its detail and weight history
    // have never been opened. Missing optional history must not hide the animal.
    if(fullWorkspace){
      await page.evaluate(async()=>{await navigator.serviceWorker.ready;});
      await page.waitForFunction(()=>!!navigator.serviceWorker.controller);
      await page.evaluate(async()=>JSON.parse(await breederWorkspace.download(false)));
      assert.equal(await page.evaluate(()=>breederWorkspace.isReady()),true);
      // Verify the actual snapshot. Rebuilding this table from the pilot cache
      // races a fresh login and can replace a valid agreement with an empty list.
      const legalRows = await page.evaluate(async () =>
        JSON.parse(await breederOffline.read('v1:00000000-0000-4000-8000-000000000001:cache:table:breeder_legal_acceptances')).value.rows);
      assert.ok(legalRows.some(row => row.user_id === userId && row.terms_version === termsVersion && row.privacy_version === privacyVersion),
        'The complete download must retain the current legal agreement');
      console.log('PASS: complete authorized table download and full local repository activation');
    }
    if (process.env.RESPONSIVE_SITE === 'true') {
      const engine = useWebKit ? 'webkit' : 'chrome';
      const waitUiText = value => page.waitForFunction(value => {
        const text = document.body.innerText + ' ' + Array.from(document.querySelectorAll('[aria-label]'))
          .map(node => node.getAttribute('aria-label')).join(' ');
        return text.includes(value);
      }, value, { timeout: 10000 });
      const settle = async () => {
        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        await page.waitForTimeout(500);
      };
      const reach = async (label, role = 'button') => {
        const target = page.getByRole(role, { name: label, exact: true }).first();
        for (let n = 0; n < 35; n++) {
          const box = await target.count() ? await target.boundingBox() : null;
          const viewport = page.viewportSize();
          if (box && box.y >= 48 && box.y + box.height <= viewport.height - 30) return target;
          await page.mouse.move(viewport.width - 15, viewport.height - 90);
          await page.mouse.wheel(0, 120);
          await settle();
        }
        throw new Error('Could not reach ' + label);
      };
      const navigate = async label => {
        await click('Page menu');
        await page.getByRole('menuitem', { name: label, exact: true }).click();
        await settle();
      };
      await page.setViewportSize({ width: 360, height: 520 });
      await setConnectivity(false);
      await page.getByText('Willow', { exact: false }).first().click();
      await settle();
      const edit = await page.getByRole('button', { name: 'Edit Animal', exact: true }).boundingBox();
      assert.ok(edit && edit.y < 180, 'The primary edit action must appear near the top of phone details');
      await page.waitForFunction(() => document.body.innerText.includes('Current Weight: 5.00 lb'));
      await page.screenshot({ path: `/tmp/breeder-adaptive-details-${engine}.png` });
      await (await reach('Registration & show details')).click();
      await settle();
      await page.getByRole('group', { name: /Registration #:[\s\S]*REG-123/ }).waitFor();
      await page.setViewportSize({ width: 1280, height: 900 });
      await settle();
      await page.mouse.move(1100, 500);
      await page.mouse.wheel(0, -4000);
      await settle();
      await page.screenshot({ path: `/tmp/breeder-adaptive-details-desktop-${engine}.png` });
      await page.setViewportSize({ width: 360, height: 520 });
      await settle();
      await (await reach('View Weight History')).click();
      await settle();
      await page.getByText('5.00 lb', { exact: false }).first().waitFor();
      await page.screenshot({ path: `/tmp/breeder-adaptive-weights-${engine}.png` });
      await click('Growth chart');
      await settle();
      await (await reach(/5\.00 lb/, 'button')).click();
      await click('Cancel');
      await click('Back');
      await (await reach('Health & Vaccine Records')).click();
      await page.getByText('No records yet.', { exact: true }).waitFor();
      await page.screenshot({ path: `/tmp/breeder-adaptive-health-${engine}.png` });
      await click('Back');
      await (await reach('Show history & reports')).click();
      await waitUiText('From the show table');
      await settle();
      await page.screenshot({ path: `/tmp/breeder-adaptive-reports-${engine}.png` });
      await navigate('Sales dashboard');
      await waitUiText('Sales overview');
      await settle();
      await page.screenshot({ path: `/tmp/breeder-adaptive-sales-${engine}.png` });
      await navigate('Herd calendar');
      await waitUiText('Event type');
      await settle();
      await page.screenshot({ path: `/tmp/breeder-adaptive-calendar-${engine}.png` });
      await navigate('Account');
      await waitUiText('Your account, all in one place');
      await settle();
      await page.screenshot({ path: `/tmp/breeder-adaptive-account-${engine}.png` });
      assert.deepEqual(failures, []);
      assert.equal(consoleErrors.some(error => /overflowed|Another exception/i.test(error)), false, consoleErrors.join('\n'));
      console.log('PASS: compact animal details, registration expansion, desktop resize, scrollable weight chart, health, reports, sales, calendar and account while offline (' + engine + ')');
      return;
    }
    await setConnectivity(false);
    await page.getByText('Willow', { exact: false }).first().click();
    await page.getByRole('button', { name: 'Edit Animal', exact: true }).waitFor({ timeout: 30000 });
    if(!fullWorkspace)await page.getByText('Current Weight: Not downloaded', { exact: true }).waitFor();
    console.log('PASS: downloaded list animal opens offline without previously downloaded weight history');
    await setConnectivity(true);
    await click('Home');
    await herd().click();
    await page.getByText('Willow', { exact: false }).first().click({ timeout: 30000 });
    await click('View Weight History');
    await click('Add weight');
    // Cancel after reading the online screen so the complete history is cached.
    await click('Cancel');
    await page.evaluate(async () => { await navigator.serviceWorker.ready; });
    await page.waitForFunction(() => !!navigator.serviceWorker.controller);
    console.log('PASS: signed-in fixture startup and application cache installation');
    if (process.env.CHECK_OFFLINE_SPEED === 'true' && !fullWorkspace) {
      assert.equal(await page.evaluate(() => navigator.onLine), true);
      await click('Home');
      await herd().waitFor();
      stallBackend = true;
      const firstFailure = Date.now();
      await herd().click();
      await page.getByText('Willow', { exact: false }).first().waitFor();
      assert.ok(Date.now() - firstFailure < 5500, 'First stalled read should fall back in about three seconds');
      const initialRequests = stalledRequests;
      const cachedNavigation = Date.now();
      await page.getByText('Willow', { exact: false }).first().click();
      await page.getByRole('button', { name: 'Edit Animal', exact: true }).waitFor();
      await click('View Weight History');
      await page.getByRole('button', { name: 'Add weight', exact: true }).waitFor();
      const navigationMs = Date.now() - cachedNavigation;
      console.log(`Offline speed: first failure ${cachedNavigation - firstFailure}ms; cached details and history ${navigationMs}ms; stalled requests ${JSON.stringify(stalledPaths)}`);
      assert.equal(stalledRequests, initialRequests, 'Later saved screens must not attempt the stalled backend');
      assert.ok(navigationMs < 2500, 'Saved animal and history must not wait for further timeouts');
      stallBackend = false;
      console.log('PASS: unresponsive backend detected within three seconds; cached details and history open without further network waits');
    }
    await setConnectivity(false);
    await click('Add weight');
    await page.getByRole('textbox').click();
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await page.locator('input:focus, textarea:focus').fill('4.75');
    await click('Save');
    await waitForOperations(1);
    await click('Home');
    await herd().click();
    await page.getByText('Willow', { exact: false }).first().click();
    await click('Edit Animal');
    await page.getByRole('textbox', { name: 'Name', exact: true }).click();
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    const focusedInput = page.locator('input:focus, textarea:focus');
    await focusedInput.fill('Willow Offline');
    assert.equal(await focusedInput.inputValue(), 'Willow Offline');
    await page.keyboard.press('Tab');
    await page.mouse.move(195, 600);
    await page.mouse.wheel(0, 1400);
    await click('Save Changes');
    await waitForOperations(2);
    await page.getByRole('button', { name: 'Save Changes', exact: true }).waitFor({ state: 'detached' });
    if(fullWorkspace){
      const expired=await page.evaluate(()=>{
        let changed=0;
        for(const key of Object.keys(localStorage)){
          try{const session=JSON.parse(localStorage.getItem(key));if(!session?.access_token||!session.user)continue;
            const parts=session.access_token.split('.'),payload=JSON.parse(atob(parts[1].replace(/-/g,'+').replace(/_/g,'/')));payload.exp=Math.floor(Date.now()/1000)-3600;
            parts[1]=btoa(JSON.stringify(payload)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');session.access_token=parts.join('.');session.expires_at=payload.exp;
            localStorage.setItem(key,JSON.stringify(session));changed++;
          }catch(_){}
        }return changed;
      });assert.ok(expired>0,'Fixture must expire the actual saved session');
    }
    await page.close();
    page = await context.newPage();
    await page.goto(origin);
    await semantics();
    await herd().waitFor({ timeout: 45000 });
    await page.getByRole('button', { name: 'Sync (2)', exact: true }).click();
    await page.getByText('Pending changes: 2', { exact: true }).waitFor();
    if(fullWorkspace)await page.getByText('All authorized record tables downloaded.',{exact:true}).waitFor();
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await page.screenshot({ path: '/tmp/breeder-offline-sync.png' });
    console.log('PASS: offline save survives app closure; cached signed-in startup and Sync dialog work offline'+(fullWorkspace?' with an expired login token':''));
    await click('Close');
    await setConnectivity(true);
    await page.getByRole('button', { name: /^Sync(?: \(\d+\))?$/ }).click();
    await page.getByText('Pending changes: 0', { exact: true }).waitFor({ timeout: 30000 });
    await click('Sync now');
    assert.equal(weights.length, 1);
    assert.equal(weights[0].weight, 4.75);
    assert.equal(animal.name, 'Willow Offline');
    if(fullWorkspace){
      await click('Close');await setConnectivity(false);
      const contract=await require('./offline_browser_workflows.cjs')(page,ringId,animalId);
      assert.ok(contract.queued>15);console.log('PASS: offline worker contracts for new animals, health, breeding, litters, pedigree, calendar windows, composite settings, profile, sales/payments, binary files and outside requests');
      await page.close();page=await context.newPage();await page.goto(origin);await semantics();
      await herd().waitFor({timeout:45000});
      await waitForOperations(contract.queued);
      await setConnectivity(true);
      await waitForOperations(0);
      assert.equal(fixtureTables.animals.filter(a=>a.id===contract.added).length,1);
      assert.equal(fixtureTables.animals.filter(a=>a.id===contract.root).length,1);
      assert.equal(fixtureTables.breeder_offline_jobs.length,3);
      // Migrate a saved pilot weight while the complete worker is active. A
      // projected weight is not evidence that the actual server received it.
      await setConnectivity(false);
      const legacy=await page.evaluate(async animalId=>{
        const id=crypto.randomUUID(),key='v1:00000000-0000-4000-8000-000000000001:';
        await breederOffline.commit(JSON.stringify({expected:{},puts:{[key+'op:weight:'+id]:{id:'weight:'+id,kind:'weight',animal_id:animalId,row:{id,animal_id:animalId,weight:5,recorded_at:new Date().toISOString()},created_at:new Date().toISOString(),state:'pending'},[key+'queue-version']:{}},deletes:[]}));
        return id;
      },animalId);
      await setConnectivity(true);
      await page.getByRole('button',{name:/^Sync(?: \(\d+\))?$/}).click();await click('Sync now');
      await waitForOperations(0);
      assert.equal(weights.filter(w=>w.id===legacy).length,1);
      console.log('PASS: all workflow requests survive restart and sync once; legacy pilot weight reaches the real server rather than its local projection');
      if(!useWebKit){
        await click('Close');
        const control=await context.newPage(),cdp=await context.newCDPSession(control),registrations=[];
        cdp.on('ServiceWorker.workerRegistrationUpdated',event=>registrations.push(...event.registrations));
        await cdp.send('ServiceWorker.enable');
        await setConnectivity(false);
        const backgroundId=await page.evaluate(async animalId=>{
          const c=JSON.parse(await breederOffline.read('workspace:active')).value;
          const response=await fetch(c.url+'/rest/v1/animal_health_records?select=*',{method:'POST',headers:{Authorization:'Bearer '+c.token,apikey:c.apiKey,'Content-Type':'application/json'},body:JSON.stringify({animal_id:animalId,title:'Closed page background sync',record_type:'health',administered_date:'2026-10-17'})});
          return (await response.json())[0].id;
        },animalId);
        const until=Date.now()+10000;while(!registrations.some(r=>r.scopeURL===origin+'/')&&Date.now()<until)await new Promise(resolve=>setTimeout(resolve,20));
        const registration=registrations.find(r=>r.scopeURL===origin+'/');assert.ok(registration,'Chromium worker registration');
        await page.close();page=control;await setConnectivity(true);
        await cdp.send('ServiceWorker.dispatchSyncEvent',{origin,registrationId:registration.registrationId,tag:'breeder-outbox',lastChance:false});
        const completed=Date.now()+10000;while(!fixtureTables.animal_health_records.some(r=>r.id===backgroundId)&&Date.now()<completed)await new Promise(resolve=>setTimeout(resolve,20));
        assert.equal(fixtureTables.animal_health_records.filter(r=>r.id===backgroundId).length,1);
        console.log('PASS: actual Chromium worker Sync event delivers a queued record with the Breeder page closed');
        await cdp.detach();await page.goto(origin);await semantics();
      }

    }
    assert.deepEqual(failures, []);
    assert.deepEqual(externalFontRequests, [], 'UI fonts must be bundled for an offline restart');
    console.log('PASS: reconnect automatically syncs the animal edit and original weight once; manual Sync also works; no browser runtime errors');
  } catch (error) {
    if(process.env.GROW_OUT_DASHBOARD==='true')console.error('Grow-out failure UI before recovery:',(await page.locator('body').innerText()).slice(0,4000));
    const syncButton = page.getByRole('button', { name: 'Sync', exact: true });
    if (await syncButton.count()) await syncButton.click().catch(() => {});
    console.error('Accessible labels:',await page.locator('[aria-label]').evaluateAll(nodes=>nodes.map(n=>({role:n.getAttribute('role'),label:n.getAttribute('aria-label')})).filter(n=>n.label)));
    console.error('Browser UI:', (await page.locator('body').innerText()).slice(0, 6000));
    console.error('Persisted queue:', await page.evaluate(async () =>
      JSON.parse(await breederOffline.scan('v1:00000000-0000-4000-8000-000000000001:op:'))).catch(() => []));
    console.error('Browser runtime errors:', failures);
    console.error('Browser console errors:', consoleErrors.slice(-12));
    await page.screenshot({ path: '/tmp/breeder-offline-failure.png' }).catch(() => {});
    throw error;
  } finally {
    await context.close();
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; server.close(); });

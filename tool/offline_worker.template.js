/* Generated pilot worker. Cache only this build's public application assets. */
'use strict';
importScripts('offline_store.js','offline_query.js','offline_actions.js','offline_workspace.js');
const workspaceOptions = {
  notify: async type => {
    if(type==='queued' && self.registration.sync)await self.registration.sync.register('breeder-outbox').catch(()=>{});
    const clients=await self.clients.matchAll();clients.forEach(client => client.postMessage({type:'breeder-workspace-changed'}));
  }
};
const REVISION = __REVISION__;
const FILES = __FILES__;
const CACHE_PREFIX = 'breeder-pilot-shell-';
const CACHE_NAME = CACHE_PREFIX + REVISION;
const ROOT = self.registration.scope;
const ASSETS = new Set(FILES.map(name => new URL(name, ROOT).href));
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    try {
      await cache.addAll([...ASSETS].map(url => new Request(url, { cache: 'reload' })));
    } catch (error) {
      await caches.delete(CACHE_NAME);
      throw error;
    }
    // Do not skipWaiting: a running form keeps its compatible application build.
  })());
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (url.searchParams.has('__breeder_network')) {
    url.searchParams.delete('__breeder_network');
    // Passing Request as a RequestInit dictionary supplies a ReadableStream
    // body, which Chromium can refuse over HTTP/1. Buffer the original bytes.
    event.respondWith((async()=>fetch(url.href,{
      method:request.method,headers:request.headers,
      body:['GET','HEAD'].includes(request.method)?undefined:await request.arrayBuffer(),
      credentials:request.credentials,mode:request.mode,redirect:request.redirect,
      cache:'no-store'
    }))());
    return;
  }
  if (url.pathname.includes('/rest/v1/') || url.pathname.includes('/storage/v1/') || url.pathname.includes('/functions/v1/')) {
    event.respondWith((async () => {
      const workspace=BreederOfflineWorkspace.create(breederOffline,workspaceOptions);
      await workspace.loadConfiguration();
      return await workspace.handle(request) || fetch(request);
    })());
    return;
  }
  if (request.method !== 'GET' || url.origin !== new URL(ROOT).origin) return;
  const navigation = request.mode === 'navigate' && url.href.startsWith(ROOT);
  const asset = new URL(url.href);
  asset.search = '';
  if (!navigation && !ASSETS.has(asset.href)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const response = await cache.match(navigation ? new URL('index.html', ROOT).href : asset.href);
    // Pages redirects /index.html to /. Navigation requests use redirect mode
    // "manual", so returning that cached redirected Response is a network error.
    // Keep the cached HTML/headers while giving the navigation a fresh response.
    if (navigation && response?.redirected) return new Response(response.body, {
      status: response.status, statusText: response.statusText, headers: response.headers
    });
    return response || fetch(request);
  })());
});
self.addEventListener('message',event=>{
  if(event.data?.type==='breeder-workspace-setup')event.waitUntil(Promise.resolve());
});
self.addEventListener('sync',event=>{
  if(event.tag==='breeder-outbox')event.waitUntil((async()=>{
    const workspace=BreederOfflineWorkspace.create(breederOffline,workspaceOptions);
    const config=await workspace.loadConfiguration();
    if(!config || config.expires*1000<Date.now())return;
    await workspace.sync();
  })());
});

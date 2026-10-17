{{flutter_js}}
{{flutter_build_config}}
async function startBreeder() {
  if (window.BREEDER_OFFLINE_BUILD === true) {
    if ('serviceWorker' in navigator) {
      // Registration failures leave the online app usable. The pilot never
      // claims full offline readiness solely because a worker registered.
      try { await navigator.serviceWorker.register('breeder-offline-worker.js'); }
      catch (error) { console.warn('Offline application installation failed.', error); }
    }
    return _flutter.loader.load({ config: { canvasKitBaseUrl: 'canvaskit/' } });
  }
  if ('serviceWorker' in navigator) {
    const registrations = await navigator.serviceWorker.getRegistrations();
    const appRoot = new URL(document.baseURI).href;
    await Promise.all(registrations.filter(r => r.scope === appRoot).map(r => r.unregister()));
  }
  if ('caches' in window) {
    const names = await caches.keys();
    await Promise.all(names.filter(n => n.startsWith('flutter-')).map(n => caches.delete(n)));
  }
  _flutter.loader.load();
}
startBreeder().catch(() => { document.body.textContent = 'Unable to start RingMaster Breeder. Please refresh to try again.'; });

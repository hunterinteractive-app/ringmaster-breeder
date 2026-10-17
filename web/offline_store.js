/* Account-scoped IndexedDB storage. No herd records or tokens enter CacheStorage. */
(() => {
  'use strict';
  let database;
  function open() {
    if (!database) database = new Promise((resolve, reject) => {
      const request = indexedDB.open('ringmaster-breeder-offline', 1);
      request.onupgradeneeded = () => request.result.createObjectStore('documents', { keyPath: 'key' });
      request.onerror = () => { database = undefined; reject(request.error); };
      request.onblocked = () => { database = undefined; reject(new Error('Close other Breeder tabs to finish upgrading offline storage.')); };
      request.onsuccess = () => {
        const db = request.result;
        db.onversionchange = () => { db.close(); database = undefined; };
        resolve(db);
      };
    });
    return database;
  }
  globalThis.breederOffline = {
    isOnline() { return navigator.onLine; },
    async read(key) {
      const db = await open();
      return new Promise((resolve, reject) => {
        const tx = db.transaction('documents', 'readonly');
        const request = tx.objectStore('documents').get(key);
        tx.oncomplete = () => resolve(JSON.stringify(request.result || null));
        tx.onabort = () => reject(tx.error || new Error('Offline read failed.'));
      });
    },
    async scan(prefix) {
      const db = await open();
      return new Promise((resolve, reject) => {
        const tx = db.transaction('documents', 'readonly');
        const rows = [];
        const request = tx.objectStore('documents').openCursor(IDBKeyRange.bound(prefix, prefix + '\uffff'));
        request.onsuccess = () => {
          const cursor = request.result;
          if (cursor) { rows.push(cursor.value); cursor.continue(); }
        };
        tx.oncomplete = () => resolve(JSON.stringify(rows));
        tx.onabort = () => reject(tx.error || new Error('Offline read failed.'));
      });
    },
    async commit(encoded) {
      const { expected, puts, deletes } = JSON.parse(encoded);
      const db = await open();
      return new Promise((resolve, reject) => {
        const tx = db.transaction('documents', 'readwrite');
        const store = tx.objectStore('documents');
        const keys = [...new Set([...Object.keys(expected), ...Object.keys(puts)])];
        const current = {};
        let left = keys.length, conflict = false;
        const apply = () => {
          if (Object.entries(expected).some(([key, version]) => (current[key]?.version ?? null) !== version)) {
            conflict = true; tx.abort(); return;
          }
          for (const [key, value] of Object.entries(puts)) {
            store.put({ key, version: (current[key]?.version || 0) + 1, value });
          }
          for (const key of deletes) store.delete(key);
        };
        for (const key of keys) {
          const request = store.get(key);
          request.onsuccess = () => { current[key] = request.result; if (--left === 0) apply(); };
        }
        if (!left) apply();
        tx.oncomplete = () => resolve(true);
        tx.onabort = () => conflict ? resolve(false) : reject(tx.error || new Error('Unable to save on this device. Check available storage.'));
      });
    },
    async storageStatus() {
      const storage = navigator.storage;
      const estimate = storage?.estimate ? await storage.estimate() : {};
      let persistent = storage?.persisted ? await storage.persisted() : null;
      if (persistent === false && storage?.persist) persistent = await storage.persist();
      return JSON.stringify({ usage: estimate.usage ?? null, quota: estimate.quota ?? null, persistent });
    },
    watch(callback) {
      window.addEventListener('online', callback);
      window.addEventListener('offline', callback);
      window.addEventListener('pageshow', callback);
      document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') callback(); });
    },
    watchWorkspace(callback) {
      window.addEventListener('breeder-workspace-changed', callback);
      // Data notifications refresh the UI; they are not connectivity events.
      if ('BroadcastChannel' in window) {
        const channel = new BroadcastChannel('breeder-offline');
        channel.onmessage = callback;
      }
      navigator.serviceWorker?.addEventListener('message', event => {
        if (event.data?.type === 'breeder-workspace-changed') callback();
      });
    }
  };
})();

/* The Flutter bridge does not expose credentials in statistics or exports. */
(() => {
  "use strict";
  const channel = "BroadcastChannel" in window
    ? new BroadcastChannel("breeder-offline")
    : null;
  const changed = async (type) => {
    channel?.postMessage({ type: "changed" });
    window.dispatchEvent(new Event("breeder-workspace-changed"));
    if (type === "queued") {
      const registration = await navigator.serviceWorker?.ready;
      if (registration?.sync) {
        await registration.sync.register("breeder-outbox").catch(() => {});
      }
    }
  };
  let workspace = BreederOfflineWorkspace.create(breederOffline, {
    notify: changed,
  });
  let ready = false;
  let currentAccount = null;
  const fileUrls = new Map();
  const failure = (error) =>
    JSON.stringify({
      error: error.message || "Unable to finish. Your saved work is retained.",
      retryable: !error.conflict &&
        ([401, 408, 429].includes(error.status) || error.status >= 500 ||
          error.name === "AbortError" ||
          error instanceof TypeError &&
            /fetch|network|load failed/i.test(error.message)),
      server: error.conflict,
    });
  const task = async (action) => {
    try {
      return JSON.stringify(await action() || {});
    } catch (error) {
      return failure(error);
    }
  };
  window.breederWorkspace = {
    async setup(encoded) {
      const config = JSON.parse(encoded);
      if (config?.account !== currentAccount) {
        workspace = BreederOfflineWorkspace.create(breederOffline, {
          notify: changed,
        });
      }
      await workspace.setup(config);
      if (config?.account !== currentAccount) {
        for (const value of fileUrls.values()) URL.revokeObjectURL(value.url);
        fileUrls.clear();
        currentAccount = config?.account;
      }
      ready = config != null && (await workspace.status()).ready;
      navigator.serviceWorker?.controller?.postMessage({
        type: "breeder-workspace-setup",
      });
      return JSON.stringify({ ready });
    },
    isReady() {
      return ready;
    },
    isControlled() {
      return !!navigator.serviceWorker?.controller;
    },
    async status() {
      return JSON.stringify({
        ...await workspace.status(),
        background_sync: "SyncManager" in window,
        update_waiting: !!(await navigator.serviceWorker?.getRegistration())
          ?.waiting,
      });
    },
    async download(full) {
      try {
        if (!navigator.serviceWorker) {
          throw new Error(
            "This browser cannot install offline application files.",
          );
        }
        let timeout;
        try {
          await Promise.race([
            navigator.serviceWorker.ready.then(() =>
              navigator.serviceWorker.controller ||
              new Promise((resolve) =>
                navigator.serviceWorker.addEventListener(
                  "controllerchange",
                  resolve,
                  { once: true },
                )
              )
            ),
            new Promise((_, reject) =>
              timeout = setTimeout(
                () =>
                  reject(
                    new Error(
                      "Application files are not ready. Reconnect and reload before preparing offline access.",
                    ),
                  ),
                30000,
              )
            ),
          ]);
        } finally {
          clearTimeout(timeout);
        }
        const active = workspace,
          value = await active.refresh({ fullFiles: full });
        if (active !== workspace) {
          throw new Error("The signed-in account changed during the download.");
        }
        ready = value.ready;
        navigator.serviceWorker.controller.postMessage({
          type: "breeder-workspace-setup",
        });
        return JSON.stringify(value);
      } catch (error) {
        return failure(error);
      }
    },
    async sync() {
      await workspace.sync();
      return JSON.stringify(await workspace.status());
    },
    async push(encoded) {
      try {
        await workspace.push(JSON.parse(encoded));
        return "{}";
      } catch (error) {
        return failure(error);
      }
    },
    async resolve(encoded) {
      return task(async () => {
        const { id, keep } = JSON.parse(encoded);
        await workspace.resolve(id, keep);
      });
    },
    async cancelJob(id) {
      return task(() => workspace.cancelJob(id));
    },
    async retryJob(id) {
      return task(() => workspace.retryJob(id));
    },
    async pause(paused) {
      return await workspace.pause(paused);
    },
    async fileUrl(encoded) {
      const { bucket, path, full } = JSON.parse(encoded),
        file = await workspace.file(bucket, path, full === true);
      if (!file) return "";
      const key = bucket + ":" + path + ":" + full,
        stamp = file.updated_at + ":" + file.base64.length;
      const prior = fileUrls.get(key);
      if (prior?.stamp === stamp) return prior.url;
      if (prior) URL.revokeObjectURL(prior.url);
      const url = URL.createObjectURL(
        new Blob([BreederOfflineWorkspace.bytes(file.base64)], {
          type: file.type,
        }),
      );
      fileUrls.set(key, { url, stamp });
      return url;
    },
  };
  window.addEventListener(
    "breeder-workspace-changed",
    () =>
      navigator.serviceWorker?.ready.then((registration) => {
        workspace.meta().then((value) => ready = !!value).catch(() => {});
      }),
  );
})();

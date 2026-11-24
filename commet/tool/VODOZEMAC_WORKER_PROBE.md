# Vodozemac service-worker probe

This is an isolated smoke test for loading Commet's generated Vodozemac WASM
bindings and performing a Megolm encrypt/decrypt round-trip inside a browser
service worker. It does not access Matrix credentials, IndexedDB, or real
room sessions.

## 1. Generate the WASM assets

Run Commet's normal web preparation step first:

```sh
./scripts/prepare-web.sh
```

That script copies the generated Vodozemac bindings into
`commet/assets/vodozemac/`. Flutter exposes those assets under
`/assets/assets/vodozemac/` in the built web application.

## 2. Compile the probe

From the `commet/` Flutter package directory:

```sh
dart compile js tool/vodozemac_worker_probe.dart -O2 -o web/vodozemac_worker_probe.js
flutter build web
```

The probe is intentionally kept as source in `tool/`; the compiled JS is a
build output and should not be committed.

## 3. Deploy and run

Deploy the built web application to an HTTPS origin (or localhost). Open the
Commet page, then run this in the browser developer console:

```js
(async () => {
  const registration = await navigator.serviceWorker.register(
    '/vodozemac-probe/sw.js',
    { scope: '/vodozemac-probe/' },
  );

  let worker = registration.active;
  if (!worker) {
    worker = registration.installing || registration.waiting;
    if (!worker) throw new Error('Probe service worker was not created');

    await new Promise((resolve, reject) => {
      worker.addEventListener('statechange', () => {
        if (worker.state === 'activated') resolve();
        if (worker.state === 'redundant') {
          reject(new Error('Probe service worker became redundant'));
        }
      });
    });
    worker = registration.active;
  }

  if (!worker) throw new Error('Probe service worker is not active');

  const channel = new MessageChannel();
  const result = new Promise((resolve, reject) => {
    channel.port1.onmessage = (event) => resolve(event.data);
    channel.port1.onmessageerror = () => reject(new Error('Message port error'));
    setTimeout(() => reject(new Error('Probe timed out after 30 seconds')), 30000);
  });

  worker.postMessage({ type: 'RUN_VODOZEMAC_PROBE' }, [channel.port2]);
  console.log(await result);
})();
```

The probe worker uses a separate `/vodozemac-probe/` scope and will not
replace Commet's normal service worker. If the app is hosted below a URL
sub-path, adjust the absolute URLs in the worker and Dart probe accordingly.

## 4. Interpret the result

- **PASS** means the generated WASM bindings initialized in a service worker
  and a Megolm round-trip succeeded there.
- A **SharedArrayBuffer**, shared-memory, or WASM compilation error points to
  browser/runtime requirements such as cross-origin isolation headers.
- A fetch/404 error usually means the generated WASM asset path is incorrect.
- A timeout means the probe did not report back; inspect the service-worker
  console and network requests.

This test does not prove that the worker can restore Commet's persisted
Matrix crypto state or decrypt a real Matrix event. That is the next test if
this smoke test passes.

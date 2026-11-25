# Vodozemac in Firefox Service Workers — experimental proof

This isolated experiment established two things in Firefox:

1. The actual Dart/Flutter-Rust-Bridge Vodozemac API can initialize in a
   Service Worker when the worker pre-initializes the generated wasm-bindgen
   module and uses a **non-threaded** WASM build.
2. Using the Commet Matrix SDK database and a persisted inbound Megolm
   session, a real stored encrypted Matrix event was decrypted in that worker.

The second test was run against a local account/database. No account IDs,
event IDs, access tokens, pickles, or ciphertext are committed here.

## Important boundaries

- These are probes, not production notification integration.
- The worker must be registered as a module worker under the isolated
  `/vodozemac-probe/` scope. It does not replace Commet's normal worker.
- The Service Worker has no `SharedArrayBuffer` in the tested Firefox setup,
  so the WASM module must use non-shared memory.
- The Matrix database is opened directly with
  `MatrixSdkDatabase.init(id, idbFactory: self.indexedDB)`. Do not call
  Commet's `getMatrixDatabase()` in a worker: its web implementation calls
  `window.navigator.storage.persist()`.
- The Matrix SDK's IndexedDB `getAllValues()` implementation needed a
  transaction-lifetime fix in the local pub-cache checkout during the test.
  That dependency fix is not silently applied to Commet here; it must be
  carried in a maintained SDK fork/override before production use.

## Generate the non-threaded WASM

Use the dart-vodozemac source corresponding to Commet's generated bindings.
In the tested setup this was tag `0.9.0`, built with FRB codegen 2.13.0:

```sh
flutter_rust_bridge_codegen build-web \
  --dart-root dart \
  --rust-root "$(readlink -f rust)" \
  --release \
  --wasm-pack-rustflags=""
```

The empty wasm-pack Rust flags override FRB's default threaded-WASM flags.
The output module must have unshared linear memory. Keep this experimental
output separate from the normal app asset under `assets/vodozemac/`.

Copy the generated JS and WASM into the built web root as follows:

- generated `vodozemac_bindings_dart.js` → `build/web/vodozemac_worker_glue.js`
- generated `vodozemac_bindings_dart_bg.wasm` →
  `build/web/vodozemac-probe/nonthreaded/vodozemac_bindings_dart_bg.wasm`

In the generated JS, expose the bindgen init function and exports at the end
of the module:

```js
wasm_bindgen = self.__vodozemacWasmBindgen =
  Object.assign(__wbg_init, { initSync }, __exports);
```

Also provide the worker global aliases required by the generated glue:

```js
if (typeof self.window === 'undefined') self.window = self;
self.wasm_bindgen = self.__vodozemacWasmBindgen;
```

The exact generated glue varies by FRB version. Keep these edits confined to
the experimental worker copy, never the normal app assets.

## Compile and defer the Dart entry points

From the Flutter package directory:

```sh
fvm dart compile js -O2 tool/vodozemac_worker_probe.dart \
  -o build/web/vodozemac_worker_probe.js
fvm dart compile js -O2 tool/matrix_worker_db_probe.dart \
  -o build/web/matrix_worker_db_probe.js
```

Dart's compiled JS is an immediately-starting IIFE. The worker must initialize
wasm-bindgen first, then invoke the Dart entry point. Create deferred copies
by changing the final startup wrapper from an immediate call to a function:

- Vodozemac: expose `self.__runVodozemacDartProbe`
- Matrix: expose `self.__runMatrixWorkerDbProbe`

The startup wrapper contains the generated program entry function
(`A.dq` or similar for the Vodozemac probe, and `A.i5` or similar for the
Matrix probe in the tested build). Do not assume those minified symbols are
stable across Dart SDK versions; inspect the compiled file's final wrapper.

Save the deferred outputs as
`build/web/vodozemac_worker_probe_deferred.js` and
`build/web/matrix_worker_db_probe_deferred.js`, then copy them to the web
root as `vodozemac_worker_probe_deferred.js` and
`matrix_worker_db_probe_deferred.js`.

## Run the isolated Megolm probe

Build/serve the web root with the same-origin isolation headers used by the
test page. Register the worker from the Firefox **page console**:

```js
const old = await navigator.serviceWorker.getRegistration('/vodozemac-probe/');
if (old) await old.unregister();
const registration = await navigator.serviceWorker.register(
  '/vodozemac-probe/matrix_megolm_sw.js',
  { scope: '/vodozemac-probe/', type: 'module', updateViaCache: 'none' }
);
await new Promise((resolve, reject) => {
  const worker = registration.installing || registration.waiting;
  if (!worker) return resolve();
  worker.addEventListener('statechange', () => {
    if (worker.state === 'activated') resolve();
    if (worker.state === 'redundant') reject(new Error('Worker redundant'));
  });
});
```

Then, still in the **page console**, supply your own local database ID,
room ID, and event ID. These values stay in your browser and are not part
of this repository:

```js
const databaseId = 'YOUR_LOCAL_CLIENT_DATABASE_ID';
const roomId = '!your-room:example.org';
const eventId = '$your-event-id';
const channel = new MessageChannel();
channel.port1.onmessage = ({ data }) => console.log(data);
registration.active.postMessage(
  { type: 'RUN_MATRIX_MEGOLM_PROBE', databaseId, roomId, eventId },
  [channel.port2]
);
```

A PASS means a real event was fetched from `box_events`, a matching persisted
inbound session was restored from the Matrix SDK database, and Vodozemac
decrypted its Megolm ciphertext in the Service Worker.

## Known limitations / next work

- The test assumes Matrix SDK's event key format `roomId|eventId` and the
  current inbound-session schema. Re-check these when upgrading the SDK.
- The test reads the locally cached event. It does not fetch a push event from
  the homeserver, process event-id-only push payloads, or display a decrypted
  notification.
- Do not open the same database concurrently with a migration or schema
  upgrade. The probe opens the existing database and closes it afterward.
- Before production integration, fix and test the IndexedDB transaction
  lifetime issue in a maintained Matrix SDK fork, then share the existing
  background decryption logic rather than maintaining a second algorithm.

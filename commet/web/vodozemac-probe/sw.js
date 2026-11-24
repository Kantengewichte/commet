/* Temporary, isolated service worker for the Vodozemac WASM probe.
 *
 * Register this worker with scope "/vodozemac-probe/" so it does not replace
 * Commet's normal service worker.
 */

let resultPort = null;

self.__vodozemacProbeResult = function (result) {
  if (resultPort) {
    resultPort.postMessage(result);
    resultPort.close();
    resultPort = null;
  }
};

self.addEventListener('message', (event) => {
  if (event.data?.type !== 'RUN_VODOZEMAC_PROBE') {
    return;
  }

  const port = event.ports?.[0];
  if (!port) {
    return;
  }

  resultPort = port;

  try {
    // The compiled Dart probe is a classic script and invokes main().
    importScripts('/vodozemac_worker_probe.js');
  } catch (error) {
    resultPort?.postMessage(
      'FAIL: Could not load the compiled Dart probe: ' + String(error),
    );
    resultPort?.close();
    resultPort = null;
  }
});

// Isolated Vodozemac worker smoke test; does not replace Commet's worker.
import '/vodozemac_worker_glue.js';
import '/vodozemac_worker_probe_deferred.js';

let wasmInitPromise;

self.addEventListener('message', async (event) => {
  const port = event.ports?.[0];
  if (!port || event.data?.type !== 'RUN_VODOZEMAC_PROBE') return;
  try {
    wasmInitPromise ??= self.__vodozemacWasmBindgen(
      '/vodozemac-probe/nonthreaded/vodozemac_bindings_dart_bg.wasm'
    );
    await wasmInitPromise;
    const resultPromise = new Promise((resolve) => {
      self.__vodozemacProbeResult = resolve;
    });
    if (typeof self.__runVodozemacDartProbe !== 'function') {
      throw new Error('Deferred Dart probe entry point is missing');
    }
    self.__runVodozemacDartProbe();
    port.postMessage(await resultPromise);
  } catch (error) {
    port.postMessage('FAIL: ' + error + '\\n' + (error?.stack ?? ''));
  } finally {
    port.close();
  }
});

// Experimental worker dedicated to the Matrix Megolm proof.
// Register under /vodozemac-probe/ with type: 'module'.
import '/vodozemac_worker_glue.js';
import '/matrix_worker_db_probe_deferred.js';

let wasmInitPromise;

function readEvent(databaseId, roomId, eventId) {
  const key = roomId + '|' + eventId;
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(databaseId);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const db = request.result;
      const tx = db.transaction('box_events', 'readonly');
      const get = tx.objectStore('box_events').get(key);
      get.onsuccess = () => {
        const value = get.result;
        db.close();
        if (!value) reject(new Error('Target Matrix event was not found'));
        else resolve(value);
      };
      get.onerror = () => {
        const error = get.error;
        db.close();
        reject(error);
      };
    };
  });
}

self.addEventListener('message', async (event) => {
  const port = event.ports?.[0];
  if (!port || event.data?.type !== 'RUN_MATRIX_MEGOLM_PROBE') return;

  try {
    const { databaseId, roomId, eventId } = event.data;
    if (![databaseId, roomId, eventId].every(
      (value) => typeof value === 'string' && value.length > 0
    )) {
      throw new Error('databaseId, roomId and eventId are required');
    }

    const matrixEvent = await readEvent(databaseId, roomId, eventId);
    self.__matrixWorkerEventJson = JSON.stringify({
      database_id: databaseId,
      room_id: roomId,
      event_id: eventId,
      event: matrixEvent,
    });

    wasmInitPromise ??= self.__vodozemacWasmBindgen(
      '/vodozemac-probe/nonthreaded/vodozemac_bindings_dart_bg.wasm'
    );
    await wasmInitPromise;

    if (typeof self.__runMatrixWorkerDbProbe !== 'function') {
      throw new Error('Deferred Matrix Dart probe entry point is missing');
    }
    const resultPromise = new Promise((resolve) => {
      self.__matrixWorkerDbProbeResult = resolve;
    });
    self.__runMatrixWorkerDbProbe();
    port.postMessage(await resultPromise);
  } catch (error) {
    port.postMessage('FAIL: ' + error + '\\n' + (error?.stack ?? ''));
  } finally {
    port.close();
  }
});

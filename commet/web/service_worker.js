
importScripts(
  "/vodozemac-probe/vodozemac_worker_glue.js",
  "/vodozemac-probe/matrix_worker_db_probe_deferred.js"
);

let wasmInitPromise;

async function getStoredValue(databaseId, storeName, key) {
  const db = await new Promise((resolve, reject) => {
    const request = indexedDB.open(databaseId);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });

  try {
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(storeName, "readonly");
      const request = tx.objectStore(storeName).get(key);
      request.onsuccess = () => resolve(request.result ?? null);
      request.onerror = () => reject(request.error);
      tx.onerror = () => reject(tx.error);
    });
  } finally {
    db.close();
  }
}

async function getStoredEvent(databaseId, roomId, eventId) {
  if (!databaseId || !roomId || !eventId) return null;
  return getStoredValue(databaseId, "box_events", roomId + "|" + eventId);
}

async function getMatrixCredentials(databaseId) {
  const [homeserverUrl, token, userId] = await Promise.all([
    getStoredValue(databaseId, "box_client", "homeserver_url"),
    getStoredValue(databaseId, "box_client", "token"),
    getStoredValue(databaseId, "box_client", "user_id")
  ]);

  if (!homeserverUrl || !token || !userId) {
    throw new Error("Matrix credentials are missing from IndexedDB");
  }

  return { homeserverUrl, token, userId };
}

async function fetchMatrixEvent(databaseId, roomId, eventId) {
  const credentials = await getMatrixCredentials(databaseId);
  const baseUrl = credentials.homeserverUrl.endsWith("/")
    ? credentials.homeserverUrl
    : credentials.homeserverUrl + "/";

  const url = new URL(
    "_matrix/client/v3/rooms/" +
      encodeURIComponent(roomId) +
      "/event/" +
      encodeURIComponent(eventId),
    baseUrl
  );

  const response = await fetch(url, {
    method: "GET",
    headers: { Authorization: "Bearer " + credentials.token }
  });

  if (!response.ok) {
    throw new Error("Synapse event request failed: HTTP " + response.status);
  }

  const matrixEvent = await response.json();

  if (
    matrixEvent.room_id !== roomId ||
    matrixEvent.event_id !== eventId
  ) {
    throw new Error("Synapse returned an unexpected Matrix event");
  }

  return matrixEvent;
}

async function decryptMatrixEvent(databaseId, roomId, eventId, matrixEvent) {
  const content = matrixEvent.content || {};
  const sessionId = content.session_id;

  if (!sessionId) {
    throw new Error("Encrypted event has no session_id");
  }

  const [credentials, session] = await Promise.all([
    getMatrixCredentials(databaseId),
    getStoredValue(databaseId, "box_inbound_group_session", sessionId)
  ]);

  if (!session) {
    throw new Error("Inbound Megolm session not found: " + sessionId);
  }

  console.log("[Commet SW] Megolm session lookup:", {
    found: true,
    roomMatches: session.room_id === roomId,
    sessionMatches: session.session_id === sessionId,
    senderKeyMatches: session.sender_key === content.sender_key,
    picklePresent: !!session.pickle
  });

  self.__matrixWorkerEventJson = JSON.stringify({
    room_id: roomId,
    event_id: eventId,
    user_id: credentials.userId,
    event: matrixEvent,
    session
  });

  wasmInitPromise ??= self.__vodozemacWasmBindgen(
    "/vodozemac-probe/nonthreaded/vodozemac_bindings_dart_bg.wasm"
  );

  await wasmInitPromise;

  const resultPromise = new Promise((resolve) => {
    self.__matrixWorkerDbProbeResult = resolve;
  });

  if (typeof self.__runMatrixWorkerDbProbe !== "function") {
    throw new Error("Deferred Matrix Dart probe entry point is missing");
  }

  self.__runMatrixWorkerDbProbe();

  const result = JSON.parse(await resultPromise);

  if (!result.success) {
    throw new Error(
      "Megolm decryption failed: " + result.error +
      (result.stackTrace ? "\n" + result.stackTrace : "")
    );
  }

  return result;
}

self.addEventListener("push", (event) => {
  event.waitUntil((async () => {
    let data = {};

    try {
      data = event.data ? event.data.json() : {};
    } catch (error) {
      console.error("[Commet SW] Invalid push payload:", error);
    }

    console.log("[Commet SW] Push received:", {
      roomIdPresent: !!data.room_id,
      eventIdPresent: !!data.event_id,
      clientIdPresent: !!data.local_client_id
    });

    const roomId = data.room_id;
    const eventId = data.event_id;
    const databaseId = data.local_client_id;

    let body = "Du hast eine neue Nachricht";
    let decrypted = false;

    try {
      const matrixEvent = await fetchMatrixEvent(databaseId, roomId, eventId);

      console.log("[Commet SW] Synapse event fetch:", {
        success: true,
        type: matrixEvent.type
      });

      if (matrixEvent.type === "m.room.encrypted") {
        const result = await decryptMatrixEvent(
          databaseId, roomId, eventId, matrixEvent
        );

        if (typeof result.body === "string") {
          body = result.body;
          decrypted = true;
        }

        console.log("[Commet SW] Megolm decryption:", {
          success: true,
          eventType: result.eventType,
          bodyPresent: typeof result.body === "string"
        });
      }
    } catch (error) {
      console.error("[Commet SW] Background decryption failed:", error);
    }

    if (!decrypted) {
      try {
        const storedEvent = await getStoredEvent(databaseId, roomId, eventId);

        if (
          storedEvent?.type === "m.room.message" &&
          typeof storedEvent.content?.body === "string"
        ) {
          body = storedEvent.content.body;
          decrypted = true;
        }

        console.log("[Commet SW] Event lookup:", {
          found: !!storedEvent,
          type: storedEvent?.type ?? null,
          decrypted
        });
      } catch (error) {
        console.error("[Commet SW] IndexedDB lookup failed:", error);
      }
    }

    await self.registration.showNotification("Commet", {
      body,
      tag: eventId || undefined,
      renotify: false,
      data: {
        room_id: roomId,
        event_id: eventId,
        local_client_id: databaseId,
        decrypted
      }
    });
  })());
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const data = event.notification.data || {};

  event.waitUntil((async () => {
    const clientList = await clients.matchAll({
      type: "window",
      includeUncontrolled: true
    });

    for (const client of clientList) {
      if ("focus" in client) {
        client.postMessage({
          type: "matrix_notification_click",
          room_id: data.room_id,
          event_id: data.event_id,
          local_client_id: data.local_client_id
        });
        return client.focus();
      }
    }

    return clients.openWindow("/");
  })());
});

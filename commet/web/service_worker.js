
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

async function getSenderDisplayName(databaseId, senderId) {
  if (!senderId) return null;

  try {
    const credentials = await getMatrixCredentials(databaseId);
    const baseUrl = credentials.homeserverUrl.endsWith("/")
      ? credentials.homeserverUrl
      : credentials.homeserverUrl + "/";
    const url = new URL(
      "_matrix/client/v3/profile/" + encodeURIComponent(senderId),
      baseUrl
    );

    const response = await fetch(url, {
      method: "GET",
      headers: { Authorization: "Bearer " + credentials.token }
    });

    if (!response.ok) {
      console.warn("[Commet SW] Sender profile lookup failed:", response.status);
      return senderId;
    }

    const profile = await response.json();
    return typeof profile.displayname === "string" && profile.displayname.trim()
      ? profile.displayname
      : senderId;
  } catch (error) {
    console.warn("[Commet SW] Sender profile lookup failed:", error);
    return senderId;
  }
}


async function getRoomState(databaseId, roomId) {
  const credentials = await getMatrixCredentials(databaseId);
  const baseUrl = credentials.homeserverUrl.endsWith("/")
    ? credentials.homeserverUrl
    : credentials.homeserverUrl + "/";
  const url = new URL(
    "_matrix/client/v3/rooms/" + encodeURIComponent(roomId) + "/state",
    baseUrl
  );
  const response = await fetch(url, {
    headers: { Authorization: "Bearer " + credentials.token }
  });
  if (!response.ok) {
    throw new Error("Room state request failed: HTTP " + response.status);
  }
  return response.json();
}

async function getConversationDetails(databaseId, roomId) {
  try {
    const credentials = await getMatrixCredentials(databaseId);
    const baseUrl = credentials.homeserverUrl.endsWith("/")
      ? credentials.homeserverUrl
      : credentials.homeserverUrl + "/";
    const auth = { Authorization: "Bearer " + credentials.token };

    const [accountResponse, roomState] = await Promise.all([
      fetch(new URL(
        "_matrix/client/v3/user/" + encodeURIComponent(credentials.userId) +
          "/account_data/m.direct",
        baseUrl
      ), { headers: auth }),
      getRoomState(databaseId, roomId)
    ]);

    let directRoomIds = [];
    if (accountResponse.ok) {
      const directAccountData = await accountResponse.json();
      directRoomIds = Object.values(directAccountData)
        .flat()
        .filter((id) => typeof id === "string");
    }

    const roomNameEvent = roomState.find((state) => state.type === "m.room.name");
    let roomName = typeof roomNameEvent?.content?.name === "string"
      ? roomNameEvent.content.name.trim()
      : "";

    const parentEvent = roomState.find((state) => state.type === "m.space.parent");
    const serverId = parentEvent?.state_key ||
      (typeof parentEvent?.content?.via === "string" ? parentEvent.state_key : null);

    if (serverId) {
      try {
        const serverState = await getRoomState(databaseId, serverId);
        const serverNameEvent = serverState.find((state) => state.type === "m.room.name");
        const serverName = typeof serverNameEvent?.content?.name === "string"
          ? serverNameEvent.content.name.trim()
          : serverId;
        const channelName = roomName
          ? (roomName.startsWith("#") ? roomName : "#" + roomName)
          : "#" + roomId;
        return { kind: "server", roomName: channelName, serverName };
      } catch (error) {
        console.warn("[Commet SW] Parent Space lookup failed:", error);
      }
    }

    if (directRoomIds.includes(roomId)) {
      return { kind: "direct" };
    }

    return { kind: "group", roomName: roomName || null };
  } catch (error) {
    console.warn("[Commet SW] Conversation lookup failed:", error);
    return { kind: "unknown" };
  }
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
    let senderId = null;
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
        senderId = typeof result.senderId === "string"
          ? result.senderId
          : typeof matrixEvent.sender === "string"
            ? matrixEvent.sender
            : null;

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
          senderId = typeof storedEvent.sender === "string"
            ? storedEvent.sender
            : null;
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

    const displayName = senderId
      ? await getSenderDisplayName(databaseId, senderId)
      : null;
    const conversation = roomId
      ? await getConversationDetails(databaseId, roomId)
      : { kind: "unknown" };

    let notificationTitle = "Commet";
    if (displayName) {
      if (conversation.kind === "server" && conversation.serverName && conversation.roomName) {
        notificationTitle = `${displayName} · ${conversation.serverName} ${conversation.roomName} · Commet`;
      } else if (conversation.kind === "group" && conversation.roomName) {
        notificationTitle = `${displayName} · ${conversation.roomName} · Commet`;
      } else {
        notificationTitle = `${displayName} · Commet`;
      }
    }

    await self.registration.showNotification(notificationTitle, {
      body,
      icon: "/icons/Icon-192.png",
      badge: "/favicon-32x32.png",
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

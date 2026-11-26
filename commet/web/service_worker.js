// Set to true to log each push's Matrix event type and notification decisions.
const DEBUG_PUSH_EVENTS = false;

function debugPushEvent(...args) {
  if (DEBUG_PUSH_EVENTS) {
    console.log("[Commet SW][Push debug]", ...args);
  }
}

function getNotificationTranslations() {
  const language = (self.navigator?.language || "en").toLowerCase();

  if (language.startsWith("de")) {
    return {
      poll: "Umfrage: ",
      invitedToRoom: (roomName) => "Du wurdest zu " + roomName + " eingeladen",
      genericNotification: "Du hast eine neue Benachrichtigung"
    };
  }

  return {
    poll: "Poll: ",
    invitedToRoom: (roomName) => "You were invited to " + roomName,
    genericNotification: "You have a new notification"
  };
}


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

// Invites are not always retrievable through /rooms/{roomId}/event because
// the recipient is not yet joined. Matrix exposes the stripped invite state
// through /sync instead.
async function fetchInviteFromSync(databaseId, roomId, eventId) {
  const credentials = await getMatrixCredentials(databaseId);
  const baseUrl = credentials.homeserverUrl.endsWith("/")
    ? credentials.homeserverUrl
    : credentials.homeserverUrl + "/";
  const filter = {
    room: {
      timeline: { limit: 0 },
      state: { lazy_load_members: true }
    }
  };
  const url = new URL("_matrix/client/v3/sync", baseUrl);
  url.searchParams.set("filter", JSON.stringify(filter));
  url.searchParams.set("timeout", "0");

  const response = await fetch(url, {
    method: "GET",
    headers: { Authorization: "Bearer " + credentials.token }
  });
  if (!response.ok) {
    throw new Error("Invite sync request failed: HTTP " + response.status);
  }

  const sync = await response.json();
  const inviteRoom = sync.rooms?.invite?.[roomId];
  const inviteEvents = inviteRoom?.invite_state?.events;
  if (!Array.isArray(inviteEvents)) return null;

  const membershipEvent = inviteEvents.find((state) =>
    state.type === "m.room.member" &&
    state.content?.membership === "invite" &&
    (!state.event_id || state.event_id === eventId) &&
    (!state.state_key || state.state_key === credentials.userId)
  );
  if (!membershipEvent) return null;

  return {
    ...membershipEvent,
    room_id: roomId,
    event_id: membershipEvent.event_id || eventId,
    unsigned: {
      ...(membershipEvent.unsigned || {}),
      invite_room_state: inviteEvents
    }
  };
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

  debugPushEvent("Megolm session lookup:", {
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

// Temporary diagnostics: Firefox may signal when a push subscription is changed or lost.
self.addEventListener("pushsubscriptionchange", (event) => {
  const oldEndpoint = event.oldSubscription?.endpoint ?? null;
  const newEndpoint = event.newSubscription?.endpoint ?? null;

  console.warn("[Commet SW] pushsubscriptionchange:", {
    oldEndpoint,
    newEndpoint,
    oldExpirationTime: event.oldSubscription?.expirationTime ?? null,
    newExpirationTime: event.newSubscription?.expirationTime ?? null
  });

  if (event.waitUntil) {
    event.waitUntil(Promise.resolve());
  }
});

self.addEventListener("push", (event) => {
  event.waitUntil((async () => {
    let data = {};

    try {
      data = event.data ? event.data.json() : {};
    } catch (error) {
      console.error("[Commet SW] Invalid push payload:", error);
      return;
    }

    debugPushEvent("Push payload received", {
      roomId: data.room_id || null,
      eventId: data.event_id || null,
      hasClientId: !!data.local_client_id
    });

    // With a full-event pusher, the Matrix gateway includes the event in
    // the push payload. This is essential for invites, which are not
    // necessarily retrievable through /rooms/{roomId}/event while not joined.
    const pushedEvent = data.event || data.notification?.event || null;
    const roomId = data.room_id || pushedEvent?.room_id;
    const eventId = data.event_id || pushedEvent?.event_id;
    const databaseId = data.local_client_id;

    // Ignore notifications that cannot be tied to a specific Matrix event.
    if (!roomId || !eventId || !databaseId) {
      console.log("[Commet SW] Ignoring push without Matrix event identifiers");
      return;
    }

    let body = null;
    let senderId = null;
    let isMessage = false;
    let isPoll = false;
    let matrixEvent = null;

    if (pushedEvent) {
      matrixEvent = pushedEvent;
      debugPushEvent("Using full Matrix event from push payload:", matrixEvent.type);
    } else {
      try {
        matrixEvent = await fetchMatrixEvent(databaseId, roomId, eventId);
      } catch (error) {
        debugPushEvent("Synapse event lookup failed; checking local event store:", error);
        try {
          matrixEvent = await getStoredEvent(databaseId, roomId, eventId);
        } catch (storedError) {
          debugPushEvent("Local event lookup failed:", storedError);
        }
        if (!matrixEvent) {
          try {
            matrixEvent = await fetchInviteFromSync(databaseId, roomId, eventId);
            if (matrixEvent) {
              debugPushEvent("Recovered invite event from /sync invite state");
            }
          } catch (syncError) {
            debugPushEvent("Invite /sync fallback failed:", syncError);
          }
        }
        if (!matrixEvent) {
          debugPushEvent("Could not identify Matrix event; notification suppressed");
          return;
        }
      }
    }

    try {
      debugPushEvent("Matrix event received:", matrixEvent.type);

      if (matrixEvent.type === "m.room.message") {
        isMessage = true;
        body = typeof matrixEvent.content?.body === "string"
          ? matrixEvent.content.body
          : null;
        senderId = typeof matrixEvent.sender === "string"
          ? matrixEvent.sender
          : null;
      } else if (matrixEvent.type === "org.matrix.msc3381.poll.start") {
        isPoll = true;
        const poll = matrixEvent.content?.["m.poll.start"] || {};
        const question = poll.question;
        body = typeof question === "string"
          ? question
          : typeof question?.["m.text"] === "string"
            ? question["m.text"]
            : typeof question?.body === "string"
              ? question.body
              : typeof matrixEvent.content?.["m.text"] === "string"
                ? matrixEvent.content["m.text"]
                : null;
        isMessage = !!body;
        senderId = typeof matrixEvent.sender === "string"
          ? matrixEvent.sender
          : null;
      } else if (
        matrixEvent.type === "m.room.member" &&
        matrixEvent.content?.membership === "invite"
      ) {
        const inviteState = matrixEvent.unsigned?.invite_room_state || [];
        const nameEvent = inviteState.find((state) => state.type === "m.room.name");
        const invitedRoomName = nameEvent?.content?.name;
        const translations = getNotificationTranslations();
        body = typeof invitedRoomName === "string" && invitedRoomName.trim()
          ? translations.invitedToRoom(invitedRoomName.trim())
          : translations.genericNotification;
        isMessage = true;
        senderId = typeof matrixEvent.sender === "string"
          ? matrixEvent.sender
          : null;
      } else if (matrixEvent.type === "m.room.encrypted") {
        try {
          const result = await decryptMatrixEvent(
            databaseId, roomId, eventId, matrixEvent
          );

          // Megolm can carry encrypted state events too. Only notify for messages.
          if (
            result.eventType === "m.room.message" ||
            result.eventType === "org.matrix.msc3381.poll.start"
          ) {
            isMessage = true;
            isPoll = result.eventType === "org.matrix.msc3381.poll.start";
            body = typeof result.body === "string" ? result.body : null;
            senderId = typeof result.senderId === "string"
              ? result.senderId
              : matrixEvent.sender || null;
          }

          debugPushEvent("Decrypted event type:", result.eventType);
        } catch (error) {
          debugPushEvent("Decryption failed for m.room.encrypted event:", error);
        }
      } else {
        // Membership, invite, name/topic changes and all other state events
        // must never produce a chat-message notification.
        debugPushEvent("Ignored Matrix event:", matrixEvent.type);
        return;
      }
    } catch (error) {
      debugPushEvent("Could not identify Matrix event; notification suppressed:", error);
      return;
    }

    // If decryption was unavailable, a previously decrypted message in the
    // local event store is still sufficient to classify and display it.
    if (!isMessage || typeof body !== "string" || !body.trim()) {
      try {
        const storedEvent = await getStoredEvent(databaseId, roomId, eventId);
        if (
          storedEvent?.type === "m.room.message" &&
          typeof storedEvent.content?.body === "string" &&
          storedEvent.content.body.trim()
        ) {
          isMessage = true;
          body = storedEvent.content.body;
          senderId = typeof storedEvent.sender === "string"
            ? storedEvent.sender
            : senderId;
        }
      } catch (error) {
        debugPushEvent("IndexedDB fallback lookup failed:", error);
      }
    }

    // Never fall back to a generic "new message" for unknown/un-decrypted
    // events. That is what caused invites and room state updates to notify.
    if (!isMessage || typeof body !== "string" || !body.trim()) {
      debugPushEvent("Notification suppressed; not a confirmed message event");
      return;
    }

    if (isPoll) {
      body = getNotificationTranslations().poll + body;
    }

    const displayName = senderId
      ? await getSenderDisplayName(databaseId, senderId)
      : null;
    const conversation = await getConversationDetails(databaseId, roomId);

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
      tag: eventId,
      renotify: false,
      data: {
        room_id: roomId,
        event_id: eventId,
        local_client_id: databaseId,
        decrypted: true
      }
    });
  })());
});
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const data = event.notification.data || {};

  event.waitUntil((async () => {
    const targetUrl = new URL("/", self.location.origin);
    if (typeof data.room_id === "string" && data.room_id) {
      targetUrl.searchParams.set("notification_room", data.room_id);
    }
    if (typeof data.local_client_id === "string" && data.local_client_id) {
      targetUrl.searchParams.set("notification_client", data.local_client_id);
    }
    if (typeof data.event_id === "string" && data.event_id) {
      targetUrl.searchParams.set("notification_event", data.event_id);
    }

    const clientList = await clients.matchAll({
      type: "window",
      includeUncontrolled: true
    });

    for (const client of clientList) {
      if (new URL(client.url).origin !== self.location.origin) continue;

      // Reload the app with the target room in its startup URL. The Flutter
      // app reads these parameters before building MainPage.
      if ("navigate" in client) {
        const navigatedClient = await client.navigate(targetUrl.href);
        return (navigatedClient || client).focus();
      }

      return client.focus();
    }

    return clients.openWindow(targetUrl.href);
  })());
});
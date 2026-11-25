import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:matrix/encryption/utils/pickle_key.dart';
import 'package:matrix/matrix.dart' show MatrixSdkDatabase;
import 'package:vodozemac/vodozemac.dart' as vodozemac;
import 'package:vodozemac/src/generated/frb_generated.dart'
    as vodozemac_frb
    show RustLib;

@JS('self.indexedDB')
external JSObject get workerIndexedDB;

@JS('self.__matrixWorkerDbProbeResult')
external void reportResult(JSAny? result);

@JS('self.__matrixWorkerEventJson')
external JSString get workerEventJson;

void report(String message) => reportResult(message.toJS);

Future<void> main() async {
  MatrixSdkDatabase? database;
  var result = '';

  try {
    await vodozemac_frb.RustLib.init(
      externalLibrary: const ExternalLibrary(
        debugInfo: 'Preinitialized in Service Worker',
        wasmBindgenName: 'wasm_bindgen',
      ),
    );
    if (!vodozemac.isInitialized()) {
      throw StateError('Vodozemac did not initialize');
    }

    final request = jsonDecode(workerEventJson.toDart) as Map<String, dynamic>;
    final databaseId = request['database_id'] as String;
    final expectedRoomId = request['room_id'] as String;
    final expectedEventId = request['event_id'] as String;
    final event = request['event'] as Map<String, dynamic>;

    if (event['room_id'] != expectedRoomId ||
        event['event_id'] != expectedEventId) {
      throw StateError('Worker received an unexpected Matrix event');
    }

    database = await MatrixSdkDatabase.init(
      databaseId,
      idbFactory: workerIndexedDB,
    );
    final client = await database.getClient(databaseId);
    if (client == null) throw StateError('Matrix client record was not found');
    final userId = client['user_id'] as String;

    final content = event['content'] as Map<String, dynamic>;
    final sessionId = content['session_id'] as String;
    final senderKey = content['sender_key'] as String;
    final ciphertext = content['ciphertext'] as String;

    final sessions = await database.getAllInboundGroupSessions();
    final matches = sessions.where((session) =>
        session.roomId == expectedRoomId &&
        session.sessionId == sessionId &&
        session.senderKey == senderKey);
    if (matches.isEmpty) {
      throw StateError('No matching persisted inbound Megolm session');
    }
    if (matches.length != 1) {
      throw StateError('Found ${matches.length} matching inbound sessions');
    }

    final session = matches.first;
    vodozemac.InboundGroupSession inbound;
    try {
      inbound = vodozemac.InboundGroupSession.fromPickleEncrypted(
        pickle: session.pickle,
        pickleKey: userId.toPickleKey(),
      );
    } catch (_) {
      inbound = vodozemac.InboundGroupSession.fromOlmPickleEncrypted(
        pickle: session.pickle,
        pickleKey: utf8.encode(userId),
      );
    }

    final decrypted = inbound.decrypt(ciphertext);
    final plaintext = jsonDecode(decrypted.plaintext) as Map<String, dynamic>;
    final messageContent =
        plaintext['content'] as Map<String, dynamic>? ?? <String, dynamic>{};
    result = [
      'PASS: Real Matrix event decrypted in the Service Worker.',
      'User: $userId',
      'Room: $expectedRoomId',
      'Event: $expectedEventId',
      'Session: $sessionId',
      'Decrypted event type: ${plaintext['type']}',
      'Message type: ${messageContent['msgtype']}',
      'Message body: ${messageContent['body']}',
    ].join('\n');
  } catch (error, stackTrace) {
    result = 'FAIL: $error\n$stackTrace';
  } finally {
    try {
      await database?.close();
    } catch (error) {
      result += '\nDatabase close error: $error';
    }
  }
  report(result);
}

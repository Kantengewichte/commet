import 'dart:convert';
import 'dart:js_interop';

import 'package:matrix/encryption/utils/pickle_key.dart';
import 'package:vodozemac/vodozemac.dart' as vodozemac;

import 'matrix_worker_vodozemac_init.dart';

@JS('self.__matrixWorkerDbProbeResult')
external void reportResult(JSAny? result);

@JS('self.__matrixWorkerEventJson')
external JSString get workerEventJson;

void report(String message) => reportResult(message.toJS);

Future<void> main() async {
  var result = '';

  try {
    if (!vodozemac.isInitialized()) {
      await initializeVodozemacForWorker();
    }

    if (!vodozemac.isInitialized()) {
      throw StateError('Vodozemac did not initialize');
    }

    final request = jsonDecode(workerEventJson.toDart) as Map<String, dynamic>;

    final expectedRoomId = request['room_id'] as String;
    final expectedEventId = request['event_id'] as String;
    final userId = request['user_id'] as String;

    final event = request['event'] as Map<String, dynamic>;
    final session = request['session'] as Map<String, dynamic>;

    if (event['room_id'] != expectedRoomId ||
        event['event_id'] != expectedEventId) {
      throw StateError('Worker received an unexpected Matrix event');
    }

    if (event['type'] != 'm.room.encrypted') {
      throw StateError('Expected an encrypted Matrix event');
    }

    final content = event['content'] as Map<String, dynamic>;

    final sessionId = content['session_id'] as String;
    final senderKey = content['sender_key'] as String;
    final ciphertext = content['ciphertext'] as String;

    if (session['room_id'] != expectedRoomId ||
        session['session_id'] != sessionId ||
        session['sender_key'] != senderKey) {
      throw StateError('Stored Megolm session does not match the event');
    }

    final pickle = session['pickle'] as String;

    vodozemac.InboundGroupSession inbound;

    try {
      inbound = vodozemac.InboundGroupSession.fromPickleEncrypted(
        pickle: pickle,
        pickleKey: userId.toPickleKey(),
      );
    } catch (_) {
      inbound = vodozemac.InboundGroupSession.fromOlmPickleEncrypted(
        pickle: pickle,
        pickleKey: utf8.encode(userId),
      );
    }

    final decrypted = inbound.decrypt(ciphertext);

    final plaintext = jsonDecode(decrypted.plaintext) as Map<String, dynamic>;

    final messageContent =
        plaintext['content'] as Map<String, dynamic>? ?? <String, dynamic>{};

    final messageBody = messageContent['body'];

    result = jsonEncode({
      'success': true,
      'body': messageBody is String ? messageBody : null,
      'eventType': plaintext['type'],
    });
  } catch (error, stackTrace) {
    result = jsonEncode({
      'success': false,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
  }

  report(result);
}

import 'dart:js_interop';

import 'package:vodozemac/vodozemac.dart' as vodozemac;

@JS('self.__vodozemacProbeResult')
external void reportResult(JSAny? result);

void report(String message) {
  reportResult(message.toJS);
}

Future<void> main() async {
  try {
    // These paths match the files copied by scripts/prepare-web.sh and
    // Flutter's assets directory in the built web application.
    await vodozemac.init(
      wasmPath: '/assets/assets/vodozemac/',
      libraryPath: '/assets/assets/vodozemac/',
      stem: 'vodozemac_bindings_dart',
    );

    if (!vodozemac.isInitialized()) {
      throw StateError('Vodozemac did not initialize');
    }

    // Exercise the real Megolm implementation in this worker context.
    final outbound = vodozemac.GroupSession();
    final inbound = outbound.toInbound();
    const plaintext = 'Commet service worker crypto test';

    final ciphertext = outbound.encrypt(plaintext);
    final decrypted = inbound.decrypt(ciphertext);

    if (decrypted.plaintext != plaintext) {
      throw StateError('Megolm round-trip returned unexpected plaintext');
    }

    report(
      'PASS: Vodozemac WASM initialized and Megolm encrypt/decrypt '
      'worked in the service worker. Session: ${outbound.sessionId}',
    );
  } catch (error, stackTrace) {
    report('FAIL: $error\n$stackTrace');
  }
}

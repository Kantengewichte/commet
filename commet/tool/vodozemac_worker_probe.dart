import 'dart:js_interop';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:vodozemac/vodozemac.dart' as vodozemac;
import 'package:vodozemac/src/generated/frb_generated.dart'
    as vodozemac_frb
    show RustLib;

@JS('self.__vodozemacProbeResult')
external void reportResult(JSAny? result);

void report(String message) => reportResult(message.toJS);

Future<void> main() async {
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
    final outbound = vodozemac.GroupSession();
    final inbound = outbound.toInbound();
    const plaintext = 'Commet service worker crypto test';
    final decrypted = inbound.decrypt(outbound.encrypt(plaintext));
    if (decrypted.plaintext != plaintext) {
      throw StateError('Megolm round-trip returned unexpected plaintext');
    }
    report('PASS: FRB initialized and Megolm encrypt/decrypt worked in the service worker.');
  } catch (error, stackTrace) {
    report('FAIL: $error\\n$stackTrace');
  }
}

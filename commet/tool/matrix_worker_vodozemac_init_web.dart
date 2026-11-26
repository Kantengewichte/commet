import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_web.dart'
    show ExternalLibrary;
import 'package:vodozemac/src/generated/frb_generated.dart' show RustLib;

Future<void> initializeVodozemacForWorker() => RustLib.init(
  externalLibrary: const ExternalLibrary(
    debugInfo: 'Preinitialized in Service Worker',
    wasmBindgenName: 'wasm_bindgen',
  ),
);

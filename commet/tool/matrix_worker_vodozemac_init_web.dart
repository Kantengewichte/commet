import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:vodozemac/src/generated/frb_generated.dart' show RustLib;

Future<void> initializeVodozemacForWorker() => RustLib.init(
  externalLibrary: ExternalLibrary(
    debugInfo: 'Preinitialized in Service Worker',
    wasmBindgenName: 'wasm_bindgen',
  ),
);

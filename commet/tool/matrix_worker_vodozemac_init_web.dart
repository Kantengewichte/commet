// The analyzer resolves the cross-platform FRB export to its IO implementation.
// The unnamed ExternalLibrary constructor is available in the web implementation.
// ignore_for_file: new_with_undefined_constructor_default

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:vodozemac/src/generated/frb_generated.dart' show RustLib;

Future<void> initializeVodozemacForWorker() => RustLib.init(
  externalLibrary: ExternalLibrary(
    debugInfo: 'Preinitialized in Service Worker',
    wasmBindgenName: 'wasm_bindgen',
  ),
);

import 'package:vodozemac/src/generated/frb_generated.dart' show RustLib;

Future<void> initializeVodozemacForWorker() => RustLib.init();

import 'dart:io';

import 'package:commet/config/platform_utils.dart';
import 'package:win32_registry/win32_registry.dart';

Future<void> registerUriHandlers() async {
  if (PlatformUtils.isWindows) {
    await register('commetchat');
  }
}

Future<void> register(String scheme) async {
  String appPath = Platform.resolvedExecutable;

  String protocolRegKey = 'Software\\Classes\\$scheme';
  RegistryValue protocolRegValue = RegistryValue.string('');

  String protocolCmdRegKey = 'shell\\open\\command';
  RegistryValue protocolCmdRegValue = RegistryValue.string('"$appPath" "%1"');

  final regKey = CURRENT_USER.create(protocolRegKey);

  try {
    regKey.setValue('URL Protocol', protocolRegValue);

    final commandKey = regKey.create(protocolCmdRegKey);

    try {
      commandKey.setValue('', protocolCmdRegValue);
    } finally {
      commandKey.close();
    }
  } finally {
    regKey.close();
  }
}

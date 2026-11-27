import 'dart:async';

import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/push_notification/push_notification_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/setup/setup_menu.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

String get titleEnableWebNotifications => Intl.message(
  "Enable notifications",
  name: "titleEnableWebNotifications",
  desc: "Title of the first-login web push notification setup",
);

String get descriptionEnableWebNotifications => Intl.message(
  "Would you like Commet to send notifications in this browser, even when Commet is closed?",
  name: "descriptionEnableWebNotifications",
  desc: "Explains browser push notifications during first-login setup",
);

String get actionEnableWebNotifications => Intl.message(
  "Enable browser notifications",
  name: "actionEnableWebNotifications",
  desc: "Button to enable browser push notifications",
);

String get statusWebNotificationsEnabled => Intl.message(
  "Browser notifications are enabled.",
  name: "statusWebNotificationsEnabled",
  desc: "Confirmation that browser push notifications were enabled",
);

String get errorEnableWebNotifications => Intl.message(
  "Could not enable browser notifications. You can try again in notification settings.",
  name: "errorEnableWebNotifications",
  desc: "Error shown when browser push notifications could not be enabled",
);

class WebPushSetup implements SetupMenu {
  final StreamController<SetupMenuState> controller = StreamController();

  @override
  Widget builder(BuildContext context) => const WebPushSetupView();

  @override
  Stream<SetupMenuState> get onStateChanged => controller.stream;

  @override
  SetupMenuState state = SetupMenuState.canProgress;

  @override
  Future<void> submit() async {
    await preferences.webPushSetupCompleted.set(true);
  }
}

class WebPushSetupView extends StatefulWidget {
  const WebPushSetupView({super.key});

  @override
  State<WebPushSetupView> createState() => _WebPushSetupViewState();
}

class _WebPushSetupViewState extends State<WebPushSetupView> {
  bool loading = false;
  bool enabled = false;
  bool failed = false;

  Future<void> enableNotifications() async {
    if (loading || enabled) return;

    setState(() {
      loading = true;
      failed = false;
    });

    try {
      final success =
          await NotificationManager.notifier?.requestPermission() ?? false;

      if (success) {
        await preferences.enableNotifications.set(true);
        await PushNotificationComponent.updateAllPushers();
      }

      if (mounted) {
        setState(() {
          enabled = success;
          failed = !success;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.largeTitle(titleEnableWebNotifications),
        tiamat.Text.label(descriptionEnableWebNotifications),
        const SizedBox(height: 16),
        if (enabled)
          tiamat.Text.label(statusWebNotificationsEnabled)
        else
          tiamat.Button(
            text: actionEnableWebNotifications,
            onTap: enableNotifications,
          ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: CircularProgressIndicator(),
          ),
        if (failed)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: tiamat.Text.labelLow(errorEnableWebNotifications),
          ),
      ],
    );
  }
}

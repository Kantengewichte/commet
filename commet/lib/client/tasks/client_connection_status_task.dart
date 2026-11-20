import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:intl/intl.dart';

class ClientConnectionStatusTask extends BackgroundTaskWithOptionalProgress {
  Client client;

  StreamController<void> controller = StreamController.broadcast();

  StreamSubscription? sub;

  @override
  bool get canCallAction => false;

  @override
  double? progress;

  String labelTaskStatus(String? user) => client.self == null
      ? switch (status) {
          BackgroundTaskStatus.running => Intl.message(
            "Connecting...",
            desc: "Label for background task when connecting to server",
            name: "labelBackgroundTaskStatusConnecting",
          ),
          BackgroundTaskStatus.failed => Intl.message(
            "Disconnected",
            desc: "Label for background task when disconnected from server",
            name: "labelBackgroundTaskStatusDisconnected",
          ),
          BackgroundTaskStatus.completed => Intl.message(
            "Connected",
            desc: "Label for background task when connected to server",
            name: "labelBackgroundTaskStatusConnected",
          ),
        }
      : switch (status) {
          BackgroundTaskStatus.running => Intl.message(
            "$user connecting...",
            desc: "Label for background task when connecting to server with account name",
            name: "labelBackgroundTaskStatusConnectingWithAccount",
            args: [user!],
          ),
          BackgroundTaskStatus.failed => Intl.message(
            "$user disconnected",
            desc: "Label for background task when disconnected from server with account name",
            name: "labelBackgroundTaskStatusDisconnectedWithAccount",
            args: [user!],
          ),
          BackgroundTaskStatus.completed => Intl.message(
            "$user connected",
            desc: "Label for background task when connected to server with account name",
            name: "labelBackgroundTaskStatusConnectedWithAccount",
            args: [user!],
          ),
        };

  @override
  String get label =>
      labelTaskStatus(client.self == null ? null : client.self?.displayName);

  @override
  Stream<void> get statusChanged => controller.stream;

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  @override
  bool shouldRemoveTask = false;

  @override
  void dispose() {
    sub?.cancel();
  }

  ClientConnectionStatusTask(
    this.client,
    ClientConnectionStatusUpdate initialStatus,
  ) {
    sub = client.connectionStatusChanged.stream.listen(onStatusUpdate);
    onStatusUpdate(initialStatus);
  }

  Timer? timer;

  void onStatusUpdate(ClientConnectionStatusUpdate event) {
    status = switch (event.status) {
      ClientConnectionStatus.unknown => BackgroundTaskStatus.running,
      ClientConnectionStatus.connected => BackgroundTaskStatus.completed,
      ClientConnectionStatus.connecting => BackgroundTaskStatus.running,
      ClientConnectionStatus.disconnected => BackgroundTaskStatus.failed,
    };
    progress = event.progress;

    if (event.status != ClientConnectionStatus.connected) {
      shouldRemoveTask = false;
      timer?.cancel();
      timer = null;
    }

    if (event.status == ClientConnectionStatus.connected && timer == null) {
      timer = Timer(const Duration(seconds: 5), () {
        shouldRemoveTask = true;
        controller.add(null);
      });
    }

    controller.add(null);
  }
}

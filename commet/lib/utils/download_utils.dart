import 'dart:async';
import 'dart:io';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:commet/utils/file_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

Future<Directory?> _getXdgPicturesDirectory() async {
  final homeDirectory = Platform.environment["HOME"];
  if (homeDirectory == null) return null;

  final configHome =
      Platform.environment["XDG_CONFIG_HOME"] ?? "$homeDirectory/.config";
  final userDirsFile = File("$configHome/user-dirs.dirs");

  var picturesPath = r"$HOME/Pictures";
  if (await userDirsFile.exists()) {
    final contents = await userDirsFile.readAsLines();
    for (final line in contents) {
      final match = RegExp(r'^\\s*XDG_PICTURES_DIR\\s*=\\s*(.*?)\\s*$')
          .firstMatch(line);
      if (match != null) {
        picturesPath = match.group(1)!.replaceAll('"', '').replaceAll("'", '');
        break;
      }
    }
  }

  picturesPath = picturesPath
      .replaceAll(r"${HOME}", homeDirectory)
      .replaceAll(r"$HOME", homeDirectory);
  if (picturesPath == "~") {
    picturesPath = homeDirectory;
  } else if (picturesPath.startsWith("~/")) {
    picturesPath = "$homeDirectory/${picturesPath.substring(2)}";
  }

  final directory = Directory(picturesPath);
  await directory.create(recursive: true);
  return directory;
}

class DownloadFileTask implements BackgroundTaskWithOptionalProgress {
  FileProvider file;
  late String filename;

  String? destinationPath;

  @override
  void Function()? action;

  @override
  bool get canCallAction => destinationPath != null && PlatformUtils.isLinux;

  @override
  void dispose() {
    sub?.cancel();
  }

  @override
  late String label;

  @override
  double? progress = 0;

  @override
  bool shouldRemoveTask = false;

  StreamSubscription? sub;

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  StreamController controller = StreamController.broadcast();
  @override
  Stream<void> get statusChanged => controller.stream;

  String labelTaskStatus(String filename) => Intl.message(
    "Downloading '$filename'...",
    desc: "Label for background task when downloading a file",
    name: "labelBackgroundTaskStatusDownloadingFile",
    args: [filename],
  );

  DownloadFileTask(this.file, String? fileName) {
    filename = fileName ?? "unnamed";

    this.label = labelTaskStatus(filename);

    action = navigateToFile;
  }

  void navigateToFile() {
    if (destinationPath != null) {
      FileUtils.navigateToFile(destinationPath!);
    }
  }

  Future<void> run() async {
    try {
      var result = await _doDownload();
      status = switch (result) {
        true => BackgroundTaskStatus.completed,
        false => BackgroundTaskStatus.failed,
      };
    } catch (exception, trace) {
      Log.onError(exception, trace);
      status = BackgroundTaskStatus.failed;
    }

    controller.add(());

    Timer(const Duration(seconds: 5), () {
      shouldRemoveTask = true;
      controller.add(null);
    });
  }

  Future<bool> _doDownload() async {
    sub = file.onProgressChanged?.listen((downloadProgress) {
      final amount =
          downloadProgress.downloaded.toDouble() /
          downloadProgress.total.toDouble();
      progress = amount;

      controller.add(());
    });

    if (PlatformUtils.isAndroid || kIsWeb) {
      final bytes = await file.getFileData();
      if (bytes != null) {
        destinationPath = await FilePicker.platform.saveFile(
          fileName: filename,
          initialDirectory: preferences.lastDownloadLocation.value,
          bytes: bytes,
        );

        return destinationPath != null;
      } else {
        return false;
      }
    }

    var initialDirectory = preferences.lastDownloadLocation.value;
    if (initialDirectory == null && PlatformUtils.isLinux) {
      initialDirectory = (await _getXdgPicturesDirectory())?.path;
    }

    destinationPath = await FilePicker.platform.saveFile(
      fileName: filename,
      initialDirectory: initialDirectory,
    );

    if (destinationPath != null) {
      await file.save(destinationPath!);
      return true;
    } else {
      return false;
    }
  }
}

class DownloadUtils {
  static Future<void> downloadAttachment(Attachment attachment) async {
    FileProvider? file;
    String name = "untitled";

    if (attachment is FileAttachment) {
      file = attachment.file;
      if (attachment.name != null) {
        name = attachment.name!;
      }
    } else {
      return;
    }

    final task = DownloadFileTask(file, name);
    backgroundTaskManager.addTask(task);
    await task.run();
  }
}

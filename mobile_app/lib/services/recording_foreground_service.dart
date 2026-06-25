import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

const int recordingForegroundServiceId = 256;

@pragma('vm:entry-point')
void recordingServiceCallback() {
  FlutterForegroundTask.setTaskHandler(_RecordingTaskHandler());
}

class _RecordingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      FlutterForegroundTask.sendDataToMain({'action': 'stop'});
    }
  }
}

class RecordingForegroundService {
  RecordingForegroundService._();

  static bool get isSupported => Platform.isAndroid;

  static Future<void> init() async {
    if (!isSupported) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'drop_recording',
        channelName: 'Registrazione Drop',
        channelDescription: 'Notifica durante la registrazione audio in background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<void> requestPermissions() async {
    if (!isSupported) return;

    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  static Future<bool> start({required String elapsedLabel}) async {
    if (!isSupported) return true;

    await requestPermissions();

    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: recordingForegroundServiceId,
      serviceTypes: const [ForegroundServiceTypes.microphone],
      notificationTitle: 'Drop — Registrazione in corso',
      notificationText: elapsedLabel,
      notificationButtons: const [
        NotificationButton(id: 'stop', text: 'Stop'),
      ],
      callback: recordingServiceCallback,
    );

    return result is ServiceRequestSuccess;
  }

  static Future<void> updateElapsed(String elapsedLabel) async {
    if (!isSupported) return;
    if (!await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Drop — Registrazione in corso',
      notificationText: elapsedLabel,
    );
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }
}

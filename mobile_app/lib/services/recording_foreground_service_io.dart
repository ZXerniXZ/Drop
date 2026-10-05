import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'recording_clock.dart';

const int recordingForegroundServiceId = 256;

const String recordingNotificationTitle = 'Drop - Registrazione in corso';

typedef RecordingTaskDataCallback = void Function(Object data);

@pragma('vm:entry-point')
void recordingServiceCallback() {
  FlutterForegroundTask.setTaskHandler(_RecordingTaskHandler());
}

class _RecordingTaskHandler extends TaskHandler {
  bool _hasClock = false;
  bool _paused = false;
  int _accumulatedMs = 0;
  int _segmentStartedAtMs = 0;
  String _lastLabel = '';
  bool _updating = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    FlutterForegroundTask.sendDataToMain({'action': 'clock'});
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _publish(DateTime.now());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final accumulated = data['accumulatedMs'];
    if (accumulated is! num) return;
    _accumulatedMs = accumulated.toInt();
    final started = data['segmentStartedAtMs'];
    _segmentStartedAtMs = started is num ? started.toInt() : 0;
    _paused = data['paused'] == true;
    _hasClock = true;
    _lastLabel = '';
    _publish(DateTime.now());
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      FlutterForegroundTask.sendDataToMain({'action': 'stop'});
    }
  }

  void _publish(DateTime now) {
    if (!_hasClock || _updating) return;
    final elapsed = recordingElapsedFromPayload(
      {
        'accumulatedMs': _accumulatedMs,
        'segmentStartedAtMs': _segmentStartedAtMs,
      },
      now,
    );
    final label = recordingNotificationText(elapsed: elapsed, paused: _paused);
    if (label == _lastLabel) return;
    _lastLabel = label;
    _updating = true;
    FlutterForegroundTask.updateService(
      notificationTitle: recordingNotificationTitle,
      notificationText: label,
    ).whenComplete(() => _updating = false);
  }
}

class RecordingForegroundService {
  RecordingForegroundService._();

  static bool get isSupported => Platform.isAndroid;

  static Future<void> init() async {
    FlutterForegroundTask.initCommunicationPort();
    if (!isSupported) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'drop_recording',
        channelName: 'Registrazione Drop',
        channelDescription:
            'Notifica durante la registrazione audio in background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(250),
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static void addTaskDataCallback(RecordingTaskDataCallback callback) {
    FlutterForegroundTask.addTaskDataCallback(callback);
  }

  static void removeTaskDataCallback(RecordingTaskDataCallback callback) {
    FlutterForegroundTask.removeTaskDataCallback(callback);
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

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: recordingNotificationTitle,
        notificationText: elapsedLabel,
      );
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: recordingForegroundServiceId,
      serviceTypes: const [ForegroundServiceTypes.microphone],
      notificationTitle: recordingNotificationTitle,
      notificationText: elapsedLabel,
      notificationButtons: const [
        NotificationButton(id: 'stop', text: 'Stop'),
      ],
      callback: recordingServiceCallback,
    );

    return result is ServiceRequestSuccess;
  }

  /// Invia l'ancora dell'orologio al servizio. La notifica calcola i secondi
  /// da sola, con la stessa formula dello schermo.
  static void syncClock({
    required int accumulatedMs,
    required int segmentStartedAtMs,
    required bool paused,
  }) {
    if (!isSupported) return;
    FlutterForegroundTask.sendDataToTask({
      'accumulatedMs': accumulatedMs,
      'segmentStartedAtMs': segmentStartedAtMs,
      'paused': paused,
    });
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }
}

import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

const int processingForegroundServiceId = 257;

const String processingNotificationTitle = 'Drop';

@pragma('vm:entry-point')
void processingServiceCallback() {
  FlutterForegroundTask.setTaskHandler(_ProcessingTaskHandler());
}

class _ProcessingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}
}

/// Tiene il processo vivo durante invio, trascrizione e analisi.
/// Senza un servizio in primo piano Android chiude l'app e l'invio si spezza.
class ProcessingForegroundService {
  ProcessingForegroundService._();

  static int _holders = 0;
  static bool _ownsService = false;
  static bool _suspended = false;
  static String _text = 'Elaborazione in corso';

  static bool get isSupported => Platform.isAndroid;

  static void _configure() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'drop_processing',
        channelName: 'Elaborazione Drop',
        channelDescription:
            'Notifica durante invio, trascrizione e analisi in background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> acquire(String text) async {
    _holders++;
    _text = text;
    if (_suspended) return;
    await _ensureStarted();
  }

  static Future<void> update(String text) async {
    _text = text;
    if (!isSupported || _suspended || !_ownsService) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: processingNotificationTitle,
      notificationText: text,
    );
  }

  static Future<void> release() async {
    if (_holders > 0) _holders--;
    if (_holders > 0 || _suspended) return;
    await _stopOwned();
  }

  /// La registrazione usa lo stesso servizio, con il microfono.
  /// Lo cede e lo riprende allo stop.
  static Future<bool> suspendForRecording() async {
    if (!_ownsService) return false;
    _suspended = true;
    await _stopOwned();
    return true;
  }

  static Future<void> resumeAfterRecording() async {
    if (!_suspended) return;
    _suspended = false;
    if (_holders <= 0) return;
    await _ensureStarted();
  }

  static Future<void> _ensureStarted() async {
    if (!isSupported) return;
    _configure();

    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) {
      if (!_ownsService) return;
      await FlutterForegroundTask.updateService(
        notificationTitle: processingNotificationTitle,
        notificationText: _text,
      );
      return;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: processingForegroundServiceId,
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: processingNotificationTitle,
      notificationText: _text,
      callback: processingServiceCallback,
    );
    _ownsService = result is ServiceRequestSuccess;
  }

  static Future<void> _stopOwned() async {
    _ownsService = false;
    if (!isSupported) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }
}

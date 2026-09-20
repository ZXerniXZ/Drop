typedef RecordingTaskDataCallback = void Function(Object data);

class RecordingForegroundService {
  RecordingForegroundService._();

  static bool get isSupported => false;

  static Future<void> init() async {}

  static void addTaskDataCallback(RecordingTaskDataCallback callback) {}

  static void removeTaskDataCallback(RecordingTaskDataCallback callback) {}

  static Future<void> requestPermissions() async {}

  static Future<bool> start({required String elapsedLabel}) async => true;

  static Future<void> updateElapsed(String elapsedLabel) async {}

  static Future<void> stop() async {}
}

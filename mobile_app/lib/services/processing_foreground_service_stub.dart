class ProcessingForegroundService {
  ProcessingForegroundService._();

  static Future<void> acquire(String text) async {}

  static Future<void> update(String text) async {}

  static Future<void> release() async {}

  static Future<bool> suspendForRecording() async => false;

  static Future<void> resumeAfterRecording() async {}
}

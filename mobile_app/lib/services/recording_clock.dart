/// Orologio della registrazione basato sull'ora reale.
///
/// Il tempo mostrato non dipende da quanti tick arrivano: un tick in ritardo
/// o doppio non accelera né ferma i secondi. UI e notifica usano gli stessi
/// numeri, così restano allineate anche con l'app in background.
class RecordingClock {
  RecordingClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  Duration _accumulated = Duration.zero;
  DateTime? _segmentStartedAt;
  bool _paused = false;

  bool get isRunning => _segmentStartedAt != null;
  bool get isPaused => _paused;

  int get accumulatedMilliseconds => _accumulated.inMilliseconds;

  int get segmentStartedAtMilliseconds =>
      _segmentStartedAt?.millisecondsSinceEpoch ?? 0;

  void start() {
    _accumulated = Duration.zero;
    _paused = false;
    _segmentStartedAt = _now();
  }

  void pause() {
    final started = _segmentStartedAt;
    if (started == null) return;
    final delta = _now().difference(started);
    if (!delta.isNegative) {
      _accumulated += delta;
    }
    _segmentStartedAt = null;
    _paused = true;
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _segmentStartedAt = _now();
  }

  void reset() {
    _accumulated = Duration.zero;
    _segmentStartedAt = null;
    _paused = false;
  }

  Duration elapsed() {
    final started = _segmentStartedAt;
    if (started == null) return _accumulated;
    final delta = _now().difference(started);
    if (delta.isNegative) return _accumulated;
    return _accumulated + delta;
  }

  Map<String, Object> toPayload() => {
        'accumulatedMs': accumulatedMilliseconds,
        'segmentStartedAtMs': segmentStartedAtMilliseconds,
        'paused': _paused,
      };
}

String formatRecordingElapsed(Duration duration) {
  final totalSeconds = duration.isNegative ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds ~/ 60) % 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:$mm:$ss';
  }
  return '$mm:$ss';
}

String recordingNotificationText({
  required Duration elapsed,
  required bool paused,
}) {
  final time = formatRecordingElapsed(elapsed);
  return paused ? 'In pausa · $time' : time;
}

Duration recordingElapsedFromPayload(Map<dynamic, dynamic> data, DateTime now) {
  final accumulatedMs = (data['accumulatedMs'] as num?)?.toInt() ?? 0;
  final startedMs = (data['segmentStartedAtMs'] as num?)?.toInt() ?? 0;
  if (startedMs <= 0) return Duration(milliseconds: accumulatedMs);
  final delta = now.millisecondsSinceEpoch - startedMs;
  return Duration(milliseconds: accumulatedMs + (delta < 0 ? 0 : delta));
}

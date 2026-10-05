import 'package:drop/services/recording_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('elapsed follows wall clock and freezes while paused', () {
    var now = DateTime(2026, 1, 1, 12);
    final clock = RecordingClock(now: () => now);

    clock.start();
    now = now.add(const Duration(seconds: 3, milliseconds: 200));
    expect(formatRecordingElapsed(clock.elapsed()), '00:03');

    clock.pause();
    now = now.add(const Duration(seconds: 10));
    expect(clock.elapsed().inSeconds, 3);

    clock.resume();
    now = now.add(const Duration(seconds: 2));
    expect(formatRecordingElapsed(clock.elapsed()), '00:05');
  });

  test('notification payload matches the on-screen second', () {
    var now = DateTime(2026, 1, 1, 12);
    final clock = RecordingClock(now: () => now);
    clock.start();
    now = now.add(const Duration(minutes: 1, seconds: 8));

    final fromPayload = recordingElapsedFromPayload(clock.toPayload(), now);
    expect(fromPayload.inSeconds, clock.elapsed().inSeconds);
    expect(
      recordingNotificationText(elapsed: fromPayload, paused: false),
      '01:08',
    );

    clock.pause();
    expect(
      recordingNotificationText(elapsed: clock.elapsed(), paused: true),
      'In pausa · 01:08',
    );
  });

  test('hours stay visible after 60 minutes', () {
    expect(
      formatRecordingElapsed(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '01:02:03',
    );
  });
}

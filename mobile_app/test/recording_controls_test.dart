import 'package:drop/widgets/drop_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pause and discard sit beside the orb and receive taps', (
    tester,
  ) async {
    var paused = 0;
    var cancelled = 0;
    var finished = 0;
    final amplitude = ValueNotifier<double>(0);
    addTearDown(amplitude.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Spacer(),
              DropBottomNav(
                activeTab: DropNavTab.file,
                onTabChanged: (_) {},
                onStartRecording: () {},
                onPauseResume: () => paused++,
                onFinishRecording: () => finished++,
                onCancelRecording: () => cancelled++,
                isRecording: true,
                isPaused: false,
                elapsedLabel: '00:12',
                amplitudeLevel: amplitude,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('recording-pause')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('recording-discard')));
    await tester.pump();

    expect(paused, 1);
    expect(cancelled, 1);
    expect(finished, 0);
  });

  testWidgets('file and my data stay tappable while idle', (tester) async {
    var tab = DropNavTab.file;
    final amplitude = ValueNotifier<double>(0);
    addTearDown(amplitude.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Spacer(),
              DropBottomNav(
                activeTab: tab,
                onTabChanged: (next) => tab = next,
                onStartRecording: () {},
                onPauseResume: () {},
                onFinishRecording: () {},
                onCancelRecording: () {},
                isRecording: false,
                isPaused: false,
                amplitudeLevel: amplitude,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('My data'));
    await tester.pump();
    expect(tab, DropNavTab.settings);
  });
}

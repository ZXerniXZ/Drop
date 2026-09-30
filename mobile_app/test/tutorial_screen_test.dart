import 'package:drop/screens/tutorial_screen.dart';
import 'package:drop/services/app_preferences_service.dart';
import 'package:drop/theme/drop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferencesService.instance.init();
  });

  testWidgets('walks the six pages and closes on the last', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DropTheme.light(),
        home: const TutorialScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('La voce resta'), findsOneWidget);
    expect(find.text('Salta'), findsOneWidget);
    expect(find.text('Avanti'), findsOneWidget);

    await tester.tap(find.text('Avanti'));
    await tester.pumpAndSettle();
    expect(find.text('Il tasto al centro'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Pronta'), findsOneWidget);
    expect(find.text('Registra'), findsOneWidget);
    expect(find.text('Salta'), findsNothing);

    await tester.tap(find.text('Registra'));
    await tester.pumpAndSettle();

    expect(find.byType(TutorialScreen), findsNothing);
    expect(await AppPreferencesService.instance.hasSeenTutorial(), isTrue);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:drop/app.dart';
import 'package:drop/services/app_preferences_service.dart';
import 'package:drop/services/local_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDatabaseService.instance.init();
    await AppPreferencesService.instance.init();
  });

  testWidgets('shows recorder screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DropApp());
    await tester.pump();

    expect(find.text('Drop'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('0 note'), findsOneWidget);
  });
}

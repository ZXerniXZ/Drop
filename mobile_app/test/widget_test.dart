import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:drop/app.dart';
import 'package:drop/services/local_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  setUp(() async {
    await LocalDatabaseService.instance.init();
  });

  testWidgets('shows recorder screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DropApp());
    await tester.pump();

    expect(find.text('DROP'), findsOneWidget);
    expect(find.text('FILE'), findsOneWidget);
    expect(find.text('NOTE (0)'), findsOneWidget);
  });
}

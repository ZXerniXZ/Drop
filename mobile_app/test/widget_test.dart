import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:drop/main.dart';
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

    expect(find.text('Drop'), findsOneWidget);
    expect(find.text('Tocca per registrare'), findsOneWidget);
    expect(find.text('Trascrizioni'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });
}

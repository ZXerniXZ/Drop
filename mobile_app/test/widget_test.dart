import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drop/main.dart';

void main() {
  testWidgets('shows recorder screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DropApp());

    expect(find.text('Drop'), findsOneWidget);
    expect(find.text('Tocca per registrare'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });
}

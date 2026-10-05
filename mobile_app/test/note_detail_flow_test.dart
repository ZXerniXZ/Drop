import 'package:drop/models/audio_note.dart';
import 'package:drop/models/note_structured_data.dart';
import 'package:drop/screens/note_detail_screen.dart';
import 'package:drop/theme/drop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('summary opens the analysis marks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DropTheme.light(),
        home: NoteDetailScreen(
          note: AudioNote(
            id: '1',
            title: 'Lezione',
            dateTime: DateTime(2026, 10, 1),
            audioPath: '',
            transcription: 'testo',
            summary: 'Un paragrafo breve sulla lezione.',
          ),
          onDelete: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Lezione'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Highlights'), findsNothing);
    expect(find.byIcon(Icons.add), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('Highlights'), findsOneWidget);
    expect(find.text('Speakers'), findsOneWidget);
    expect(find.text('Key data'), findsOneWidget);
    expect(find.text('Chiedi a Drop su questa nota...'), findsOneWidget);
  });

  testWidgets('a ready mark opens its section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DropTheme.light(),
        home: NoteDetailScreen(
          note: AudioNote(
            id: '1',
            title: 'Lezione',
            dateTime: DateTime(2026, 10, 1),
            audioPath: '',
            transcription: 'testo',
            summary: 'Un paragrafo breve.',
            structuredData: const NoteStructuredData(
              highlights: ['Manda gli appunti'],
              analysisState: {NoteStructuredData.highlightsKind: 'ready'},
            ),
          ),
          onDelete: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Highlights'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);

    await tester.tap(find.text('Highlights'));
    await tester.pump();

    expect(find.text('Manda gli appunti'), findsOneWidget);
    expect(find.text('Genera mappa mentale'), findsNothing);
    expect(find.text('Meeting template'), findsNothing);
  });

  testWidgets('mind map shows titles until a point is opened', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DropTheme.light(),
        home: NoteDetailScreen(
          note: AudioNote(
            id: '1',
            title: 'Lezione',
            dateTime: DateTime(2026, 10, 1),
            audioPath: '',
            transcription: 'testo',
            summary: 'Un paragrafo breve.',
            structuredData: const NoteStructuredData(
              mindMap: [
                MindMapNode(
                  title: 'Energia',
                  body: r'La relazione è $E=mc^2$.',
                  children: [
                    MindMapNode(title: 'Massa', body: 'La massa a riposo.'),
                  ],
                ),
              ],
              analysisState: {NoteStructuredData.mindMapKind: 'ready'},
            ),
          ),
          onDelete: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Mind map'));
    await tester.pump();

    expect(find.text('Energia'), findsOneWidget);
    expect(find.text('Massa'), findsNothing);

    await tester.tap(find.text('Energia'));
    await tester.pump();

    expect(find.text('Massa'), findsOneWidget);
    expect(find.text('Mappa'), findsOneWidget);
  });
}

import 'package:drop/models/note_folder.dart';
import 'package:drop/widgets/note_folder_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dragging a note onto the bottom target moves it out', (
    tester,
  ) async {
    final accepted = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _DragHarness(accepted: accepted),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Lezione')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Fuori dalla cartella'), findsOneWidget);

    await gesture.moveTo(tester.getCenter(find.byKey(const Key('move-out-folder'))));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(accepted, ['n1']);
  });

  testWidgets('dragging a note onto a folder assigns that folder', (
    tester,
  ) async {
    String? droppedFolder;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              NoteFolderBar(
                folders: [
                  NoteFolder(
                    id: 'folder-1',
                    name: 'Lezioni',
                    createdAt: DateTime.utc(2026, 1, 1),
                  ),
                ],
                noteCount: (_) => 0,
                dragging: true,
                onCreate: () {},
                onOpen: (_) {},
                onDelete: (_) {},
                onDropNote: (_, folderId) => droppedFolder = folderId,
              ),
              DraggableLibraryNote(
                noteId: 'n1',
                title: 'Lezione',
                onDragStarted: () {},
                onDragEnded: () {},
                child: const SizedBox(
                  height: 80,
                  child: Text('Lezione'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Lezione')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveTo(tester.getCenter(find.text('Lezioni')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(droppedFolder, 'folder-1');
  });
}

class _DragHarness extends StatefulWidget {
  const _DragHarness({required this.accepted});

  final List<String> accepted;

  @override
  State<_DragHarness> createState() => _DragHarnessState();
}

class _DragHarnessState extends State<_DragHarness> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: DraggableLibraryNote(
            noteId: 'n1',
            title: 'Lezione',
            onDragStarted: () => setState(() => _dragging = true),
            onDragEnded: () => setState(() => _dragging = false),
            child: const SizedBox(
              height: 72,
              width: 220,
              child: Text('Lezione'),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: MoveOutFolderTarget(
            visible: _dragging,
            onAccept: widget.accepted.add,
          ),
        ),
      ],
    );
  }
}

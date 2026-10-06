import 'package:drop/models/audio_note.dart';
import 'package:drop/models/note_filters.dart';
import 'package:drop/utils/note_library.dart';
import 'package:flutter_test/flutter_test.dart';

AudioNote _note({
  required String id,
  String? folderId,
  String title = 'Nota',
}) {
  return AudioNote(
    id: id,
    title: title,
    dateTime: DateTime.utc(2026, 3, 1),
    audioPath: '',
    transcription: 'testo $title',
    summary: '',
    folderId: folderId,
  );
}

void main() {
  test('home hides notes that live in a folder', () {
    final notes = [
      _note(id: 'a', title: 'Libera'),
      _note(id: 'b', title: 'Dentro', folderId: 'folder-1'),
    ];

    final visible = visibleLibraryNotes(
      notes: notes,
      openFolderId: null,
      filters: const NoteFilters(),
      knownFolderIds: const {'folder-1'},
    );

    expect(visible.map((note) => note.id), ['a']);
  });

  test('a note left in a deleted folder returns to the home', () {
    final notes = [
      _note(id: 'a', folderId: 'gone'),
    ];

    final visible = visibleLibraryNotes(
      notes: notes,
      openFolderId: null,
      filters: const NoteFilters(),
      knownFolderIds: const {},
    );

    expect(visible.map((note) => note.id), ['a']);
  });

  test('search on home includes notes inside folders', () {
    final notes = [
      _note(id: 'a', title: 'Libera'),
      _note(id: 'b', title: 'Lezione', folderId: 'folder-1'),
    ];

    final visible = visibleLibraryNotes(
      notes: notes,
      openFolderId: null,
      filters: const NoteFilters(searchQuery: 'lezione'),
      knownFolderIds: const {'folder-1'},
    );

    expect(visible.map((note) => note.id), ['b']);
  });

  test('open folder shows only its notes', () {
    final notes = [
      _note(id: 'a'),
      _note(id: 'b', folderId: 'folder-1'),
      _note(id: 'c', folderId: 'folder-2'),
    ];

    final visible = visibleLibraryNotes(
      notes: notes,
      openFolderId: 'folder-1',
      filters: const NoteFilters(),
      knownFolderIds: const {'folder-1', 'folder-2'},
    );

    expect(visible.map((note) => note.id), ['b']);
    expect(notesInFolderCount(notes, 'folder-1'), 1);
    expect(folderNotesLabel(1), '1 nota');
    expect(folderNotesLabel(2), '2 note');
  });

  test('folder id survives a copy and can be cleared', () {
    final note = _note(id: 'a', folderId: 'folder-1');
    expect(note.copyWith(title: 'Altro').folderId, 'folder-1');
    expect(note.copyWith(clearFolder: true).folderId, isNull);
    expect(note.toMap()['folder_id'], 'folder-1');
    expect(AudioNote.fromMap(note.toMap()).folderId, 'folder-1');
  });
}

import '../models/audio_note.dart';
import '../models/note_filters.dart';
import 'note_filter_utils.dart';

/// Note visibili nella home.
///
/// Senza filtri, la home mostra solo le note fuori dalle cartelle.
/// Una nota il cui id cartella non esiste piu' torna visibile in home.
/// Con ricerca o filtri attivi mostra anche quelle dentro, cosi' non
/// spariscono dai risultati. Dentro una cartella si vedono solo le sue.
List<AudioNote> visibleLibraryNotes({
  required List<AudioNote> notes,
  required String? openFolderId,
  required NoteFilters filters,
  required Set<String> knownFolderIds,
}) {
  final Iterable<AudioNote> located;
  if (openFolderId != null) {
    located = notes.where((note) => note.folderId == openFolderId);
  } else if (filters.hasActiveFilters) {
    located = notes;
  } else {
    located = notes.where((note) {
      final id = note.folderId;
      if (id == null || id.isEmpty) return true;
      return !knownFolderIds.contains(id);
    });
  }
  return applyNoteFilters(located.toList(), filters);
}

int notesInFolderCount(List<AudioNote> notes, String folderId) {
  var count = 0;
  for (final note in notes) {
    if (note.folderId == folderId) count++;
  }
  return count;
}

String folderNotesLabel(int count) {
  if (count == 1) return '1 nota';
  return '$count note';
}

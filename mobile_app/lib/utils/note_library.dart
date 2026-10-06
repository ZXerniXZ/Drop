import '../models/audio_note.dart';
import '../models/note_folder.dart';
import '../models/note_filters.dart';
import 'note_filter_utils.dart';

String? normalizeFolderId(String? id) {
  if (id == null || id.isEmpty) return null;
  return id;
}

/// Cartelle direttamente dentro [parentId]. Null è la home.
List<NoteFolder> foldersIn(List<NoteFolder> folders, String? parentId) {
  final parent = normalizeFolderId(parentId);
  return [
    for (final folder in folders)
      if (normalizeFolderId(folder.parentId) == parent) folder,
  ];
}

/// I genitori prima dei figli, così un invio al server non crea un figlio
/// prima della cartella che lo contiene.
List<NoteFolder> foldersParentsFirst(List<NoteFolder> folders) {
  final byId = {for (final folder in folders) folder.id: folder};
  final ordered = <NoteFolder>[];
  final seen = <String>{};

  void visit(NoteFolder folder) {
    if (!seen.add(folder.id)) return;
    final parentId = normalizeFolderId(folder.parentId);
    final parent = parentId == null ? null : byId[parentId];
    if (parent != null) visit(parent);
    ordered.add(folder);
  }

  for (final folder in folders) {
    visit(folder);
  }
  return ordered;
}

/// La cartella e tutte quelle annidate dentro di lei.
Set<String> folderSubtreeIds(List<NoteFolder> folders, String rootId) {
  final childrenOf = <String, List<String>>{};
  for (final folder in folders) {
    final parent = normalizeFolderId(folder.parentId);
    if (parent == null) continue;
    childrenOf.putIfAbsent(parent, () => []).add(folder.id);
  }

  final ids = <String>{};
  void walk(String id) {
    if (!ids.add(id)) return;
    for (final child in childrenOf[id] ?? const <String>[]) {
      walk(child);
    }
  }

  walk(rootId);
  return ids;
}

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

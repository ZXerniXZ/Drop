import '../models/audio_note.dart';
import '../models/note_filters.dart';

List<AudioNote> applyNoteFilters(List<AudioNote> notes, NoteFilters filters) {
  final query = filters.searchQuery.trim().toLowerCase();

  return notes.where((note) {
    if (query.isNotEmpty && !note.searchableText.contains(query)) {
      return false;
    }

    if (filters.tagFilter != null &&
        note.tag.toLowerCase() != filters.tagFilter!.toLowerCase()) {
      return false;
    }

    switch (filters.durationFilter) {
      case DurationFilter.short:
        if (note.durationSeconds >= 5 * 60) return false;
      case DurationFilter.medium:
        if (note.durationSeconds < 5 * 60 || note.durationSeconds > 15 * 60) {
          return false;
        }
      case DurationFilter.long:
        if (note.durationSeconds <= 15 * 60) return false;
      case DurationFilter.all:
        break;
    }

    switch (filters.statusFilter) {
      case StatusFilter.processing:
        if (!note.analysisStatus.isProcessing) return false;
      case StatusFilter.ready:
        if (note.analysisStatus != NoteAnalysisStatus.ready) return false;
      case StatusFilter.failed:
        if (note.analysisStatus != NoteAnalysisStatus.failed) return false;
      case StatusFilter.all:
        break;
    }

    return true;
  }).toList();
}

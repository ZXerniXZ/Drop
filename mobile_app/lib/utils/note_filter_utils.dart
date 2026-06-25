import '../models/audio_note.dart';
import '../models/note_filters.dart';

List<AudioNote> applyNoteFilters(List<AudioNote> notes, NoteFilters filters) {
  final query = filters.searchQuery.trim().toLowerCase();
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final weekStart = todayStart.subtract(const Duration(days: 7));

  return notes.where((note) {
    if (query.isNotEmpty && !note.searchableText.contains(query)) {
      return false;
    }

    switch (filters.dateFilter) {
      case DateFilter.today:
        if (note.dateTime.isBefore(todayStart)) return false;
      case DateFilter.week:
        if (note.dateTime.isBefore(weekStart)) return false;
      case DateFilter.all:
        break;
    }

    switch (filters.tagFilter) {
      case TagFilter.meeting:
        if (note.tag != NoteTag.meeting) return false;
      case TagFilter.lezione:
        if (note.tag != NoteTag.lezione) return false;
      case TagFilter.diario:
        if (note.tag != NoteTag.diario) return false;
      case TagFilter.all:
        break;
    }

    return true;
  }).toList();
}

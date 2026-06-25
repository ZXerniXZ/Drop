enum DateFilter { all, today, week }

enum TagFilter { all, meeting, lezione, diario }

class NoteFilters {
  const NoteFilters({
    this.dateFilter = DateFilter.all,
    this.tagFilter = TagFilter.all,
    this.searchQuery = '',
  });

  final DateFilter dateFilter;
  final TagFilter tagFilter;
  final String searchQuery;

  NoteFilters copyWith({
    DateFilter? dateFilter,
    TagFilter? tagFilter,
    String? searchQuery,
  }) {
    return NoteFilters(
      dateFilter: dateFilter ?? this.dateFilter,
      tagFilter: tagFilter ?? this.tagFilter,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  bool get hasActiveFilters =>
      dateFilter != DateFilter.all ||
      tagFilter != TagFilter.all ||
      searchQuery.trim().isNotEmpty;
}

enum DurationFilter { all, short, medium, long }

enum StatusFilter { all, processing, ready, failed }

class NoteFilters {
  const NoteFilters({
    this.tagFilter,
    this.durationFilter = DurationFilter.all,
    this.statusFilter = StatusFilter.all,
    this.searchQuery = '',
  });

  /// null = tutti i tag
  final String? tagFilter;
  final DurationFilter durationFilter;
  final StatusFilter statusFilter;
  final String searchQuery;

  NoteFilters copyWith({
    String? tagFilter,
    bool clearTagFilter = false,
    DurationFilter? durationFilter,
    StatusFilter? statusFilter,
    String? searchQuery,
  }) {
    return NoteFilters(
      tagFilter: clearTagFilter ? null : (tagFilter ?? this.tagFilter),
      durationFilter: durationFilter ?? this.durationFilter,
      statusFilter: statusFilter ?? this.statusFilter,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  bool get hasActiveFilters =>
      tagFilter != null ||
      durationFilter != DurationFilter.all ||
      statusFilter != StatusFilter.all ||
      searchQuery.trim().isNotEmpty;
}

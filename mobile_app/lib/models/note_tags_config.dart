class NoteTagsConfig {
  const NoteTagsConfig({this.tags = defaultTags});

  static const defaultTags = [
    'Meeting',
    'Lezione',
    'Diario',
    'Lavoro',
    'Intervista',
    'Brainstorm',
    'Memo',
    'Chiamata',
  ];

  final List<String> tags;

  NoteTagsConfig copyWith({List<String>? tags}) {
    return NoteTagsConfig(tags: tags ?? this.tags);
  }

  static String normalizeTag(String? value, {List<String>? allowed}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Memo';

    final pool = allowed ?? defaultTags;
    final match = pool.where(
      (t) => t.toLowerCase() == trimmed.toLowerCase(),
    );
    if (match.isNotEmpty) return match.first;
    return trimmed;
  }
}

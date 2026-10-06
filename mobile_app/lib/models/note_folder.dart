class NoteFolder {
  const NoteFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.parentId,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  /// Cartella che la contiene. Null: sta nella home.
  final String? parentId;

  factory NoteFolder.fromMap(Map<String, Object?> map) {
    final parent = map['parent_id'] as String?;
    return NoteFolder(
      id: map['id'] as String,
      name: map['name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      parentId: (parent == null || parent.isEmpty) ? null : parent,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'parent_id': parentId,
    };
  }
}

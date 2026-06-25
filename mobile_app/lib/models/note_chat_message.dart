class NoteChatMessage {
  const NoteChatMessage({
    required this.id,
    required this.noteId,
    required this.role,
    required this.content,
    this.reasoning,
    required this.createdAt,
  });

  final String id;
  final String noteId;
  final String role;
  final String content;
  final String? reasoning;
  final DateTime createdAt;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  factory NoteChatMessage.fromMap(Map<String, Object?> map) {
    return NoteChatMessage(
      id: map['id'] as String,
      noteId: map['note_id'] as String,
      role: map['role'] as String,
      content: map['content'] as String? ?? '',
      reasoning: map['reasoning'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'note_id': noteId,
      'role': role,
      'content': content,
      'reasoning': reasoning,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

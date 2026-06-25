import 'dart:convert';

class SpeakerBlock {
  const SpeakerBlock({
    required this.speaker,
    required this.text,
    this.time,
  });

  final String speaker;
  final String text;
  final String? time;

  factory SpeakerBlock.fromMap(Map<String, dynamic> map) {
    return SpeakerBlock(
      speaker: map['speaker'] as String? ?? 'Speaker 0',
      text: map['text'] as String? ?? '',
      time: map['time'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'speaker': speaker,
        'text': text,
        if (time != null) 'time': time,
      };
}

class NoteStructuredData {
  const NoteStructuredData({
    this.highlights = const [],
    this.location = '',
    this.participants = const [],
    this.speakerView = const [],
  });

  final List<String> highlights;
  final String location;
  final List<String> participants;
  final List<SpeakerBlock> speakerView;

  bool get hasData =>
      highlights.isNotEmpty ||
      location.isNotEmpty ||
      participants.isNotEmpty ||
      speakerView.isNotEmpty;

  factory NoteStructuredData.fromResponse(Map<String, dynamic> data) {
    final highlightsRaw = data['highlights'];
    final highlights = highlightsRaw is List
        ? highlightsRaw.map((e) => e.toString()).toList()
        : <String>[];

    final keyData = data['key_data'];
    var location = '';
    var participants = <String>[];
    if (keyData is Map<String, dynamic>) {
      location = keyData['location'] as String? ?? '';
      final p = keyData['participants'];
      if (p is List) {
        participants = p.map((e) => e.toString()).toList();
      }
    }

    final speakerRaw = data['speaker_view'];
    final speakerView = speakerRaw is List
        ? speakerRaw
            .whereType<Map<String, dynamic>>()
            .map(SpeakerBlock.fromMap)
            .where((b) => b.text.isNotEmpty)
            .toList()
        : <SpeakerBlock>[];

    return NoteStructuredData(
      highlights: highlights,
      location: location,
      participants: participants,
      speakerView: speakerView,
    );
  }

  factory NoteStructuredData.fromJsonString(String? json) {
    if (json == null || json.isEmpty) return const NoteStructuredData();
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return NoteStructuredData.fromResponse(decoded);
    } catch (_) {
      return const NoteStructuredData();
    }
  }

  String toJsonString() {
    return jsonEncode({
      'highlights': highlights,
      'key_data': {
        'location': location,
        'participants': participants,
      },
      'speaker_view': speakerView.map((b) => b.toMap()).toList(),
    });
  }
}

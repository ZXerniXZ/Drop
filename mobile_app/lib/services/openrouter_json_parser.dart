import 'dart:convert';

/// Parses the first JSON object from LLM output (handles trailing text / fences).
Map<String, dynamic> loadFirstJsonObject(String content) {
  var text = content.trim();
  if (text.startsWith('```')) {
    text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```[\s\S]*$'), '');
    text = text.trim();
  }

  final start = text.indexOf('{');
  if (start == -1) {
    throw FormatException('LLM response missing JSON object');
  }

  final slice = text.substring(start);
  final result = _rawDecodeObject(slice);
  if (result == null) {
    throw FormatException('LLM response JSON root must be an object');
  }
  return result;
}

Map<String, dynamic>? _rawDecodeObject(String text) {
  const decoder = JsonDecoder();
  var depth = 0;
  var inString = false;
  var escape = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (escape) {
      escape = false;
      continue;
    }
    if (ch == '\\' && inString) {
      escape = true;
      continue;
    }
    if (ch == '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) {
        final snippet = text.substring(0, i + 1);
        final data = decoder.convert(snippet);
        if (data is Map<String, dynamic>) return data;
        if (data is Map) return Map<String, dynamic>.from(data);
        return null;
      }
    }
  }
  return null;
}

List<String> asStringList(dynamic value) {
  if (value is! List) return [];
  return value
      .map((e) => e.toString().trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

List<Map<String, String>> normalizeSpeakerView(dynamic value) {
  if (value is! List) return [];
  final blocks = <Map<String, String>>[];
  for (final item in value) {
    if (item is! Map) continue;
    final speaker =
        (item['speaker']?.toString().trim().isNotEmpty == true)
            ? item['speaker'].toString().trim()
            : 'Speaker 0';
    final text = item['text']?.toString().trim() ?? '';
    if (text.isEmpty) continue;
    final block = <String, String>{'speaker': speaker, 'text': text};
    final time = item['time']?.toString().trim();
    if (time != null && time.isNotEmpty) block['time'] = time;
    blocks.add(block);
  }
  return blocks;
}

Map<String, dynamic> normalizeKeyData(
  dynamic value,
  List<String> allowedTags,
) {
  final pool = allowedTags.where((t) => t.trim().isNotEmpty).toList();
  final tags = pool.isEmpty ? defaultAnalysisTagsForParser : pool;

  if (value is! Map) {
    return {'location': '', 'participants': <String>[], 'tags': tags.first};
  }

  final participants = value['participants'];
  final participantList = participants is List
      ? participants
            .map((p) => p.toString().trim())
            .where((p) => p.isNotEmpty)
            .toList()
      : <String>[];

  var tag = value['tags']?.toString().trim() ?? tags.first;
  if (tag.isEmpty) tag = tags.first;
  final matched = tags.firstWhere(
    (t) => t.toLowerCase() == tag.toLowerCase(),
    orElse: () => tags.first,
  );

  return {
    'location': value['location']?.toString().trim() ?? '',
    'participants': participantList,
    'tags': matched,
  };
}

const defaultAnalysisTagsForParser = [
  'Meeting',
  'Lezione',
  'Diario',
  'Lavoro',
  'Intervista',
  'Brainstorm',
  'Memo',
  'Chiamata',
];

String speakerViewToFormatted(List<Map<String, String>> speakerView) {
  if (speakerView.isEmpty) return '';
  return speakerView.map((block) {
    final label = block['speaker'] ?? 'Speaker 0';
    final time = block['time'];
    final suffix = time != null && time.isNotEmpty ? ' [$time]' : '';
    return '$label$suffix: ${block['text']}';
  }).join('\n\n');
}

Map<String, dynamic> parseLlmAnalysisJson(
  String content,
  List<String> allowedTags,
) {
  final data = loadFirstJsonObject(content);
  final pool = allowedTags.where((t) => t.trim().isNotEmpty).toList();
  final tags = pool.isEmpty ? defaultAnalysisTagsForParser : pool;

  var title = data['title']?.toString().trim() ?? '';
  final summary = data['summary']?.toString().trim() ?? '';
  final highlights = asStringList(data['highlights']);
  final keyData = normalizeKeyData(data['key_data'], tags);
  final speakerView = normalizeSpeakerView(data['speaker_view']);

  var formatted = data['formatted_transcript']?.toString().trim() ?? '';
  if (formatted.isEmpty) {
    formatted = speakerViewToFormatted(speakerView);
  }

  if (summary.isEmpty) {
    throw FormatException('LLM response missing summary');
  }
  if (title.isEmpty) title = 'Nota vocale';

  return {
    'title': title.length > 80 ? title.substring(0, 80) : title,
    'summary': summary,
    'highlights': highlights,
    'key_data': keyData,
    'speaker_view': speakerView,
    'formatted_transcript': formatted.isNotEmpty ? formatted : summary,
  };
}

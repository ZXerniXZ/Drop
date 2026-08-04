import 'dart:convert';

/// Parola con i suoi tempi reali, usata per l'evidenziazione karaoke.
class TranscriptWord {
  const TranscriptWord({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final Duration start;
  final Duration end;

  factory TranscriptWord.fromMap(Map<String, dynamic> map) {
    return TranscriptWord(
      text: (map['w'] as String? ?? '').trim(),
      start: _durationFromSeconds(map['start']),
      end: _durationFromSeconds(map['end']),
    );
  }

  Map<String, dynamic> toMap() => {
        'w': text,
        'start': start.inMilliseconds / 1000,
        'end': end.inMilliseconds / 1000,
      };
}

/// Frase trascritta con i tempi di inizio e fine restituiti da Whisper.
class TranscriptSegment {
  const TranscriptSegment({
    required this.start,
    required this.end,
    required this.text,
    this.words = const [],
  });

  final Duration start;
  final Duration end;
  final String text;
  final List<TranscriptWord> words;

  bool contains(Duration position) => position >= start && position < end;

  /// Indice dell'ultima parola gia' pronunciata, -1 se il segmento non e'
  /// ancora iniziato o se le parole non hanno tempi utilizzabili.
  int activeWordIndex(Duration position) {
    var index = -1;
    for (var i = 0; i < words.length; i++) {
      if (position >= words[i].start) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  factory TranscriptSegment.fromMap(Map<String, dynamic> map) {
    final wordsRaw = map['words'];
    return TranscriptSegment(
      start: _durationFromSeconds(map['start']),
      end: _durationFromSeconds(map['end']),
      text: (map['text'] as String? ?? '').trim(),
      words: wordsRaw is List
          ? wordsRaw
              .whereType<Map<String, dynamic>>()
              .map(TranscriptWord.fromMap)
              .where((w) => w.text.isNotEmpty)
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toMap() => {
        'start': start.inMilliseconds / 1000,
        'end': end.inMilliseconds / 1000,
        'text': text,
        'words': words.map((w) => w.toMap()).toList(),
      };

  static List<TranscriptSegment> listFromResponse(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(TranscriptSegment.fromMap)
        .where((s) => s.text.isNotEmpty)
        .toList();
  }

  static List<TranscriptSegment> listFromJsonString(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return listFromResponse(jsonDecode(json));
    } catch (_) {
      return const [];
    }
  }

  static String listToJsonString(List<TranscriptSegment> segments) {
    if (segments.isEmpty) return '';
    return jsonEncode(segments.map((s) => s.toMap()).toList());
  }

  /// Segmento attivo alla posizione data, oppure il piu' recente gia' passato
  /// se la posizione cade in una pausa fra due frasi.
  static int indexAt(List<TranscriptSegment> segments, Duration position) {
    var index = -1;
    for (var i = 0; i < segments.length; i++) {
      if (position < segments[i].start) break;
      index = i;
    }
    return index;
  }
}

Duration _durationFromSeconds(dynamic value) {
  final seconds = value is num ? value.toDouble() : 0.0;
  return Duration(milliseconds: (seconds * 1000).round());
}

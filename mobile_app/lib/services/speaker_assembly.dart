// Monta speaker_view dai segmenti Whisper + speaker_ids dell'LLM.

String formatMmSs(num seconds) {
  final total = seconds.isNaN ? 0 : seconds.round().clamp(0, 24 * 3600);
  final minutes = (total ~/ 60).toString().padLeft(2, '0');
  final secs = (total % 60).toString().padLeft(2, '0');
  return '$minutes:$secs';
}

List<int> normalizeSpeakerIds(dynamic value, int segmentCount) {
  if (segmentCount <= 0) return const [];
  if (value is! List) return List<int>.filled(segmentCount, 0);

  final ids = <int>[];
  for (final item in value) {
    final parsed = item is num ? item.toInt() : int.tryParse('$item') ?? 0;
    ids.add(parsed < 0 ? 0 : parsed);
  }

  if (ids.length < segmentCount) {
    final pad = ids.isEmpty ? 0 : ids.last;
    ids.addAll(List<int>.filled(segmentCount - ids.length, pad));
  } else if (ids.length > segmentCount) {
    return ids.sublist(0, segmentCount);
  }
  return ids;
}

List<Map<String, String>> buildSpeakerView(
  List<Map<String, dynamic>> segments,
  dynamic speakerIds,
) {
  if (segments.isEmpty) return const [];

  final ids = normalizeSpeakerIds(speakerIds, segments.length);
  final blocks = <Map<String, String>>[];

  var currentSpeaker = ids[0];
  var currentStart = (segments[0]['start'] as num?)?.toDouble() ?? 0.0;
  final texts = <String>[];

  void flush() {
    final joined = texts.where((t) => t.isNotEmpty).join(' ').trim();
    texts.clear();
    if (joined.isEmpty) return;
    blocks.add({
      'speaker': 'Speaker $currentSpeaker',
      'text': joined,
      'time': formatMmSs(currentStart),
    });
  }

  for (var i = 0; i < segments.length; i++) {
    final text = (segments[i]['text'] as String? ?? '').trim();
    final speaker = ids[i];
    final start = (segments[i]['start'] as num?)?.toDouble() ?? 0.0;

    if (speaker != currentSpeaker && texts.isNotEmpty) {
      flush();
      currentSpeaker = speaker;
      currentStart = start;
    }

    if (texts.isEmpty) {
      currentSpeaker = speaker;
      currentStart = start;
    }
    if (text.isNotEmpty) texts.add(text);
  }
  flush();
  return blocks;
}

String speakerViewToFormatted(List<Map<String, String>> speakerView) {
  if (speakerView.isEmpty) return '';
  return speakerView.map((block) {
    final time = block['time'];
    final timeSuffix = (time != null && time.isNotEmpty) ? ' - $time' : '';
    return '[${block['speaker']}$timeSuffix]: ${block['text']}';
  }).join('\n');
}

({List<Map<String, String>> speakerView, String formatted})
    buildFromRawTranscript(String transcript) {
  final text = transcript.trim();
  if (text.isEmpty) {
    return (speakerView: <Map<String, String>>[], formatted: '');
  }
  final view = [
    {'speaker': 'Speaker 0', 'text': text, 'time': '00:00'},
  ];
  return (speakerView: view, formatted: speakerViewToFormatted(view));
}

String formatSegmentsForDiarization(
  List<Map<String, dynamic>> segments, {
  int maxCharsPerSegment = 280,
}) {
  final lines = <String>[];
  for (var i = 0; i < segments.length; i++) {
    final start = formatMmSs((segments[i]['start'] as num?) ?? 0);
    var text = (segments[i]['text'] as String? ?? '')
        .trim()
        .replaceAll('\n', ' ');
    if (text.length > maxCharsPerSegment) {
      text = '${text.substring(0, maxCharsPerSegment - 1)}…';
    }
    lines.add('[$i] [$start] $text');
  }
  return lines.join('\n');
}

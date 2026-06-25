import 'package:drop/models/chat_stream_event.dart';
import 'package:drop/services/note_chat_service.dart';
import 'package:drop/services/openrouter_json_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseServerSseDataLine', () {
    test('parses reasoning SSE event', () {
      final event = parseServerSseDataLine(
        'data: {"type":"reasoning","delta":"Analizzo..."}',
      );
      expect(event, isA<ChatReasoningDelta>());
      expect((event! as ChatReasoningDelta).delta, 'Analizzo...');
    });

    test('parses content and done SSE events', () {
      final content = parseServerSseDataLine(
        'data: {"type":"content","delta":"Ciao"}',
      );
      expect(content, isA<ChatContentDelta>());

      final done = parseServerSseDataLine(
        'data: {"type":"done","reasoning":"think","content":"risposta"}',
      );
      expect(done, isA<ChatStreamDone>());
      final d = done! as ChatStreamDone;
      expect(d.reasoning, 'think');
      expect(d.content, 'risposta');
    });
  });

  group('loadFirstJsonObject', () {
    test('parses JSON with trailing text (Extra data case)', () {
      const raw = '''
{
  "title": "Riunione team",
  "summary": "## Overview\\nDiscussione sprint.",
  "highlights": ["Punto 1"],
  "key_data": {"location": "", "participants": [], "tags": "Meeting"},
  "speaker_view": [],
  "formatted_transcript": "Testo"
}
Extra commentary after JSON''';

      final data = loadFirstJsonObject(raw);
      expect(data['title'], 'Riunione team');
      expect(data['summary'], contains('Overview'));
    });

    test('parseLlmAnalysisJson normalizes output', () {
      const raw = '''
{"title":"Test","summary":"## Overview\\nOk","highlights":["a"],"key_data":{"tags":"Meeting"},"speaker_view":[],"formatted_transcript":"t"}''';

      final result = parseLlmAnalysisJson(raw, ['Meeting', 'Memo']);
      expect(result['title'], 'Test');
      expect(result['key_data'], isA<Map>());
      expect((result['key_data'] as Map)['tags'], 'Meeting');
    });
  });
}

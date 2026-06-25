import 'dart:convert';

import 'package:drop/models/chat_stream_event.dart';
import 'package:flutter_test/flutter_test.dart';

ChatStreamEvent? parseSseDataLine(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('data:')) return null;
  final dataStr = trimmed.substring(5).trim();
  if (dataStr == '[DONE]') return null;

  final parsed = jsonDecode(dataStr) as Map<String, dynamic>;
  final type = parsed['type'] as String?;
  switch (type) {
    case 'reasoning':
      return ChatReasoningDelta(parsed['delta'] as String? ?? '');
    case 'content':
      return ChatContentDelta(parsed['delta'] as String? ?? '');
    case 'done':
      return ChatStreamDone(
        content: parsed['content'] as String? ?? '',
        reasoning: parsed['reasoning'] as String?,
      );
    case 'error':
      return ChatStreamError(parsed['message'] as String? ?? 'Errore');
    default:
      return null;
  }
}

void main() {
  test('parses reasoning SSE event', () {
    final event = parseSseDataLine(
      'data: {"type":"reasoning","delta":"Analizzo..."}',
    );
    expect(event, isA<ChatReasoningDelta>());
    expect((event! as ChatReasoningDelta).delta, 'Analizzo...');
  });

  test('parses content and done SSE events', () {
    final content = parseSseDataLine(
      'data: {"type":"content","delta":"Ciao"}',
    );
    expect(content, isA<ChatContentDelta>());

    final done = parseSseDataLine(
      'data: {"type":"done","reasoning":"think","content":"risposta"}',
    );
    expect(done, isA<ChatStreamDone>());
    final d = done! as ChatStreamDone;
    expect(d.reasoning, 'think');
    expect(d.content, 'risposta');
  });
}

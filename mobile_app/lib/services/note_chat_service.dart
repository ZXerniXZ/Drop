import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/audio_note.dart';
import '../models/chat_stream_event.dart';
import '../models/note_chat_message.dart';
import 'api_url_resolver.dart';
import 'app_preferences_service.dart';
import 'drop_api_headers.dart';
import 'http_client.dart';
import 'http_text.dart';
import 'local_database_service.dart';
import 'openrouter_client.dart';
import 'supabase_auth_service.dart';

ChatStreamEvent? parseServerSseDataLine(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('data:')) return null;
  final dataStr = trimmed.substring(5).trim();
  if (dataStr == '[DONE]') return null;

  final parsed = jsonDecode(dataStr) as Map<String, dynamic>;
  final type = parsed['type'] as String?;
  switch (type) {
    case 'reasoning':
      final delta = parsed['delta'] as String? ?? '';
      if (delta.isEmpty) return null;
      return ChatReasoningDelta(delta);
    case 'content':
      final delta = parsed['delta'] as String? ?? '';
      if (delta.isEmpty) return null;
      return ChatContentDelta(delta);
    case 'done':
      return ChatStreamDone(
        content: parsed['content'] as String? ?? '',
        reasoning: parsed['reasoning'] as String?,
      );
    case 'error':
      return ChatStreamError(
        parsed['message'] as String? ?? 'Errore sconosciuto',
      );
    default:
      return null;
  }
}

/// Collapses a full SSE body into one result. Web chat waits for this
/// instead of painting each delta.
ChatStreamEvent foldServerSse(String body) {
  var reasoning = '';
  var content = '';
  for (final line in body.split('\n')) {
    final event = parseServerSseDataLine(line);
    switch (event) {
      case ChatReasoningDelta(:final delta):
        reasoning += delta;
      case ChatContentDelta(:final delta):
        content += delta;
      case ChatStreamError(:final message):
        return ChatStreamError(message);
      case ChatStreamDone(
        content: final doneContent,
        reasoning: final doneReasoning,
      ):
        final text = doneContent.isNotEmpty ? doneContent : content;
        final thought =
            (doneReasoning != null && doneReasoning.trim().isNotEmpty)
            ? doneReasoning
            : (reasoning.isEmpty ? null : reasoning);
        return _doneOrEmpty(text, thought);
      case null:
        break;
    }
  }
  return _doneOrEmpty(content, reasoning.isEmpty ? null : reasoning);
}

ChatStreamEvent _doneOrEmpty(String content, String? reasoning) {
  if (content.trim().isEmpty &&
      (reasoning == null || reasoning.trim().isEmpty)) {
    return const ChatStreamError('Nessuna risposta.');
  }
  return ChatStreamDone(content: content, reasoning: reasoning);
}

String serverChatErrorMessage(int statusCode, String errorBody) {
  var message = 'Errore server ($statusCode)';
  try {
    final parsed = jsonDecode(errorBody) as Map<String, dynamic>;
    final detail = parsed['detail'];
    if (detail != null) message = detail.toString();
  } catch (_) {
    if (errorBody.isNotEmpty) {
      message = errorBody.length > 160
          ? '${errorBody.substring(0, 160)}...'
          : errorBody;
    }
  }
  return message;
}

class NoteChatService {
  NoteChatService._();

  static final NoteChatService instance = NoteChatService._();
  static final _random = Random();

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';

  Map<String, dynamic> _noteContextFromAudioNote(AudioNote note) {
    final sd = note.structuredData;
    return {
      'title': note.title,
      'tag': note.tag,
      'date_time': note.dateTime.toIso8601String(),
      'raw_transcription': note.rawTranscription,
      'formatted_transcription': note.transcription,
      'summary': note.summary,
      'highlights': sd.highlights,
      'key_data': {...sd.keyDataPayload(), 'tags': note.tag},
      'mind_map': sd.mindMap.map((node) => node.toMap()).toList(),
      'speaker_view': sd.speakerView
          .map(
            (b) => {
              'speaker': b.speaker,
              'text': b.text,
              if (b.time != null) 'time': b.time,
            },
          )
          .toList(),
    };
  }

  Future<NoteChatMessage> saveUserMessage({
    required String noteId,
    required String content,
  }) async {
    final message = NoteChatMessage(
      id: _newId(),
      noteId: noteId,
      role: 'user',
      content: content,
      createdAt: DateTime.now(),
    );
    await LocalDatabaseService.instance.saveChatMessage(message);
    return message;
  }

  Future<NoteChatMessage> saveAssistantMessage({
    required String noteId,
    required String content,
    String? reasoning,
  }) async {
    final message = NoteChatMessage(
      id: _newId(),
      noteId: noteId,
      role: 'assistant',
      content: content,
      reasoning: reasoning?.trim().isEmpty == true ? null : reasoning?.trim(),
      createdAt: DateTime.now(),
    );
    await LocalDatabaseService.instance.saveChatMessage(message);
    return message;
  }

  Stream<ChatStreamEvent> sendMessageStream({
    required AudioNote note,
    required String message,
  }) async* {
    final prefs = await AppPreferencesService.instance.loadAiPreferences();
    final history = await LocalDatabaseService.instance.getChatMessages(
      note.id,
    );
    var historyForApi = history;
    if (historyForApi.isNotEmpty &&
        historyForApi.last.isUser &&
        historyForApi.last.content == message) {
      historyForApi = historyForApi.sublist(0, historyForApi.length - 1);
    }

    final apiKey = await AppPreferencesService.instance.loadOpenRouterApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      yield* OpenRouterClient.instance.streamNoteChat(
        apiKey: apiKey,
        note: note,
        message: message,
        history: historyForApi,
        aiModel: prefs.model.openRouterId,
      );
      return;
    }

    yield* _streamViaServer(
      note: note,
      message: message,
      history: historyForApi,
      aiModel: prefs.model.openRouterId,
    );
  }

  Stream<ChatStreamEvent> _streamViaServer({
    required AudioNote note,
    required String message,
    required List<NoteChatMessage> history,
    required String aiModel,
  }) async* {
    final historyPayload = history
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    final url = await ApiUrlResolver.resolveEndpoint('/chat-note/stream');
    final accessToken = SupabaseAuthService.instance.currentAccessToken;
    if (accessToken == null || accessToken.isEmpty) {
      yield const ChatStreamError(
        'Sessione scaduta. Effettua di nuovo l\'accesso.',
      );
      return;
    }

    final body = jsonEncode({
      'message': message,
      'note_id': note.id,
      'history': historyPayload,
      'ai_model': aiModel,
      'output_language': note.outputLanguage,
      'note_context': _noteContextFromAudioNote(note),
    });

    if (kIsWeb) {
      yield* _bufferedServerEvents(
        url: Uri.parse(url),
        headers: DropApiHeaders.json(accessToken),
        body: body,
      );
      return;
    }

    final client = createHttpClient();
    try {
      final request = http.Request('POST', Uri.parse(url))
        ..headers.addAll(DropApiHeaders.json(accessToken))
        ..body = body;

      final response = await client.send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        yield ChatStreamError(
          serverChatErrorMessage(response.statusCode, errorBody),
        );
        return;
      }

      var buffer = '';
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        while (true) {
          final lineEnd = buffer.indexOf('\n');
          if (lineEnd == -1) break;

          final line = buffer.substring(0, lineEnd);
          buffer = buffer.substring(lineEnd + 1);

          final event = parseServerSseDataLine(line);
          if (event == null) continue;
          yield event;
          if (event is ChatStreamError) return;
        }
      }
    } catch (e) {
      yield ChatStreamError('Errore di rete: $e');
    } finally {
      client.close();
    }
  }

  Stream<ChatStreamEvent> _bufferedServerEvents({
    required Uri url,
    required Map<String, String> headers,
    required String body,
  }) async* {
    try {
      final response = await postText(
        url: url,
        headers: headers,
        body: body,
        timeout: const Duration(seconds: 300),
      );
      if (response.statusCode != 200) {
        yield ChatStreamError(
          serverChatErrorMessage(response.statusCode, response.body),
        );
        return;
      }
      yield foldServerSse(response.body);
    } catch (e) {
      yield ChatStreamError('Errore di rete: $e');
    }
  }
}

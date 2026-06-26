import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/audio_note.dart';
import '../models/chat_stream_event.dart';
import '../models/note_chat_message.dart';
import 'api_url_resolver.dart';
import 'app_preferences_service.dart';
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
      'key_data': {
        'location': sd.location,
        'participants': sd.participants,
        'tags': note.tag,
      },
      'speaker_view': sd.speakerView
          .map((b) => {
                'speaker': b.speaker,
                'text': b.text,
                if (b.time != null) 'time': b.time,
              })
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
    final history = await LocalDatabaseService.instance.getChatMessages(note.id);
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
      yield const ChatStreamError('Sessione scaduta. Effettua di nuovo l\'accesso.');
      return;
    }

    final body = jsonEncode({
      'message': message,
      'note_id': note.id,
      'history': historyPayload,
      'ai_model': aiModel,
      'note_context': _noteContextFromAudioNote(note),
    });

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(url))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $accessToken'
        ..body = body;

      final response = await client.send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        String message = 'Errore server (${response.statusCode})';
        try {
          final parsed = jsonDecode(errorBody) as Map<String, dynamic>;
          final detail = parsed['detail'];
          if (detail != null) {
            message = detail.toString();
          }
        } catch (_) {
          if (errorBody.isNotEmpty) {
            message = errorBody.length > 160
                ? '${errorBody.substring(0, 160)}...'
                : errorBody;
          }
        }
        yield ChatStreamError(message);
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
}

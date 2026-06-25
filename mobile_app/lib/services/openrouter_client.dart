import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/ai_preferences.dart';
import '../models/audio_note.dart';
import '../models/chat_stream_event.dart';
import '../models/note_chat_message.dart';
import 'openrouter_json_parser.dart';
import 'openrouter_prompts.dart';

const openRouterChatUrl = 'https://openrouter.ai/api/v1/chat/completions';
const openRouterTranscriptionsUrl =
    'https://openrouter.ai/api/v1/audio/transcriptions';
const openRouterModelsUrl = 'https://openrouter.ai/api/v1/models';
const whisperModel = 'openai/whisper-large-v3';
const defaultLlmModel = 'google/gemini-3.5-flash';

const transcriptionTimeout = Duration(seconds: 600);
const llmTimeout = Duration(seconds: 300);
const chatTimeout = Duration(seconds: 120);

const maxHistoryMessages = 10;
const maxTranscriptChars = 12000;
const headTailChars = 4000;

const _modelAliases = <String, String>{
  'gemini_35_flash': 'google/gemini-3.5-flash',
  'gemini35flash': 'google/gemini-3.5-flash',
  'gemini 3.5 flash': 'google/gemini-3.5-flash',
  'google/gemini-3.5-flash': 'google/gemini-3.5-flash',
  'gemini_flash': 'google/gemini-2.5-flash',
  'geminiflash': 'google/gemini-2.5-flash',
  'gemini 2.5 flash': 'google/gemini-2.5-flash',
  'google/gemini-2.5-flash': 'google/gemini-2.5-flash',
  'gemini_pro': 'google/gemini-2.5-pro',
  'geminipro': 'google/gemini-2.5-pro',
  'gemini 2.5 pro': 'google/gemini-2.5-pro',
  'google/gemini-2.5-pro': 'google/gemini-2.5-pro',
};

const _formatMap = {
  '.m4a': 'm4a',
  '.mp3': 'mp3',
  '.wav': 'wav',
  '.flac': 'flac',
  '.ogg': 'ogg',
  '.webm': 'webm',
  '.aac': 'aac',
};

const _languageCodes = {
  'italian': 'it',
  'italiano': 'it',
  'english': 'en',
  'inglese': 'en',
  'automatic': null,
  'automatico': null,
};

class OpenRouterClient {
  OpenRouterClient._();

  static final OpenRouterClient instance = OpenRouterClient._();

  String resolveLlmModel(String? aiModel) {
    if (aiModel == null || aiModel.trim().isEmpty) return defaultLlmModel;
    final stripped = aiModel.trim();
    if (stripped.contains('/')) return stripped;
    final normalized = stripped.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    return _modelAliases[normalized] ??
        _modelAliases[stripped.toLowerCase()] ??
        defaultLlmModel;
  }

  Map<String, String> _headers(String apiKey) => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': openRouterAppReferer,
        'X-Title': openRouterAppTitle,
      };

  String _audioFormat(String filePath) {
    final suffix = p.extension(filePath).toLowerCase();
    return _formatMap[suffix] ?? 'm4a';
  }

  String? _languageCode(String? language) {
    if (language == null || language.trim().isEmpty) return null;
    final key = language.trim().toLowerCase();
    if (_languageCodes.containsKey(key)) return _languageCodes[key];
    if (key.length == 2) return key;
    return null;
  }

  Future<String> transcribeAudio({
    required String filePath,
    required String apiKey,
    String? language,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    final audioB64 = base64Encode(bytes);

    final payload = <String, dynamic>{
      'model': whisperModel,
      'input_audio': {
        'data': audioB64,
        'format': _audioFormat(filePath),
      },
    };

    final langCode = _languageCode(language);
    if (langCode != null) payload['language'] = langCode;

    final response = await http
        .post(
          Uri.parse(openRouterTranscriptionsUrl),
          headers: _headers(apiKey),
          body: jsonEncode(payload),
        )
        .timeout(transcriptionTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'OpenRouter transcription error ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final text = data['text'] as String?;
    if (text == null || text.isEmpty) {
      throw Exception('OpenRouter returned an empty transcription');
    }
    return text;
  }

  Future<Map<String, dynamic>> analyzeTranscript({
    required String transcript,
    required String apiKey,
    required AiPreferences prefs,
    required List<String> availableTags,
  }) async {
    final tagsPool = availableTags.where((t) => t.trim().isNotEmpty).toList();
    final pool = tagsPool.isEmpty ? defaultAnalysisTags : tagsPool;
    final resolvedModel = resolveLlmModel(prefs.model.openRouterId);

    final payload = {
      'model': resolvedModel,
      'messages': [
        {
          'role': 'system',
          'content': buildAnalysisSystemPrompt(pool),
        },
        {
          'role': 'user',
          'content': buildAnalysisUserPrompt(
            transcript: transcript,
            customPrompt: prefs.customPrompt,
            language: prefs.transcriptionLanguage.name,
          ),
        },
      ],
      'response_format': {'type': 'json_object'},
    };

    final response = await http
        .post(
          Uri.parse(openRouterChatUrl),
          headers: _headers(apiKey),
          body: jsonEncode(payload),
        )
        .timeout(llmTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'OpenRouter LLM error ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Unexpected OpenRouter chat response format');
    }
    final message = choices.first['message'] as Map<String, dynamic>?;
    final content = message?['content'] as String?;
    if (content == null || content.isEmpty) {
      throw Exception('Unexpected OpenRouter chat response format');
    }

    return parseLlmAnalysisJson(content, pool);
  }

  Future<Map<String, dynamic>> processAudioFile({
    required String filePath,
    required String apiKey,
    required AiPreferences prefs,
    required List<String> availableTags,
  }) async {
    final transcription = await transcribeAudio(
      filePath: filePath,
      apiKey: apiKey,
      language: prefs.transcriptionLanguage.name,
    );
    final processed = await analyzeTranscript(
      transcript: transcription,
      apiKey: apiKey,
      prefs: prefs,
      availableTags: availableTags,
    );

    return {
      'success': true,
      'raw_transcription': transcription,
      'title': processed['title'],
      'formatted_transcription': processed['formatted_transcript'],
      'summary': processed['summary'],
      'highlights': processed['highlights'],
      'key_data': processed['key_data'],
      'speaker_view': processed['speaker_view'],
    };
  }

  Future<bool> testConnection(String apiKey) async {
    final response = await http
        .get(
          Uri.parse(openRouterModelsUrl),
          headers: _headers(apiKey),
        )
        .timeout(const Duration(seconds: 15));
    return response.statusCode == 200;
  }

  String _truncateTranscript(String text) {
    if (text.length <= maxTranscriptChars) return text;
    final head = text.substring(0, headTailChars);
    final tail = text.substring(text.length - headTailChars);
    final omitted = text.length - headTailChars * 2;
    return '$head\n\n[... $omitted caratteri omessi ...]\n\n$tail';
  }

  String _buildNoteContextBlock(Map<String, dynamic> ctx) {
    var transcript =
        (ctx['formatted_transcription'] as String?) ??
        (ctx['raw_transcription'] as String?) ??
        '';
    transcript = _truncateTranscript(transcript);

    final parts = <String>[
      'Titolo: ${ctx['title'] ?? ''}',
      'Data: ${ctx['date_time'] ?? ''}',
      'Tag: ${ctx['tag'] ?? ''}',
    ];

    final keyData = ctx['key_data'];
    if (keyData is Map) {
      final location = keyData['location']?.toString().trim() ?? '';
      if (location.isNotEmpty) parts.add('Luogo: $location');
      final participants = keyData['participants'];
      if (participants is List && participants.isNotEmpty) {
        parts.add('Partecipanti: ${participants.join(', ')}');
      }
    }

    final summary = ctx['summary']?.toString().trim() ?? '';
    if (summary.isNotEmpty) parts.add('\n## Riepilogo\n$summary');

    final highlights = ctx['highlights'];
    if (highlights is List && highlights.isNotEmpty) {
      final bullets = highlights.map((h) => '- $h').join('\n');
      parts.add('\n## Highlights\n$bullets');
    }

    final speakerView = ctx['speaker_view'];
    if (speakerView is List && speakerView.isNotEmpty) {
      final blocks = <String>[];
      for (final block in speakerView.take(20)) {
        if (block is! Map) continue;
        final speaker = block['speaker'] ?? 'Speaker';
        final text = block['text'] ?? '';
        if (text.toString().isNotEmpty) {
          blocks.add('$speaker: $text');
        }
      }
      if (blocks.isNotEmpty) {
        parts.add('\n## Speaker view\n${blocks.join('\n')}');
      }
    }

    if (transcript.trim().isNotEmpty) {
      parts.add('\n## Trascrizione\n${transcript.trim()}');
    }

    return parts.join('\n');
  }

  List<Map<String, String>> _buildChatMessages({
    required String message,
    required List<NoteChatMessage> history,
    required Map<String, dynamic> noteContext,
  }) {
    final contextBlock = _buildNoteContextBlock(noteContext);
    final systemContent =
        '$noteChatSystemPrompt\n\n--- CONTESTO NOTA ---\n$contextBlock\n--- FINE CONTESTO ---';

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemContent},
    ];

    final trimmedHistory = history.length > maxHistoryMessages
        ? history.sublist(history.length - maxHistoryMessages)
        : history;
    for (final item in trimmedHistory) {
      messages.add({'role': item.role, 'content': item.content});
    }
    messages.add({'role': 'user', 'content': message.trim()});
    return messages;
  }

  String _extractReasoningDelta(Map<String, dynamic> delta) {
    final reasoning = delta['reasoning'];
    if (reasoning is String && reasoning.isNotEmpty) return reasoning;

    final details = delta['reasoning_details'];
    if (details is! List) return '';

    final parts = <String>[];
    for (final detail in details) {
      if (detail is! Map) continue;
      if (detail['type'] == 'reasoning.text') {
        final text = detail['text'];
        if (text is String && text.isNotEmpty) parts.add(text);
      }
    }
    return parts.join();
  }

  Stream<ChatStreamEvent> streamNoteChat({
    required String apiKey,
    required AudioNote note,
    required String message,
    required List<NoteChatMessage> history,
    required String aiModel,
  }) async* {
    if (message.trim().isEmpty) {
      yield const ChatStreamError('Message is empty');
      return;
    }

    final noteContext = _noteContextFromAudioNote(note);
    final messages = _buildChatMessages(
      message: message,
      history: history,
      noteContext: noteContext,
    );

    final payload = {
      'model': resolveLlmModel(aiModel),
      'stream': true,
      'reasoning': {'effort': 'medium'},
      'messages': messages,
    };

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(openRouterChatUrl))
        ..headers.addAll(_headers(apiKey))
        ..body = jsonEncode(payload);

      final response = await client.send(request).timeout(chatTimeout);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        yield ChatStreamError(
          'OpenRouter error ${response.statusCode}: $errorBody',
        );
        return;
      }

      var fullReasoning = '';
      var fullContent = '';
      var buffer = '';

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        while (true) {
          final lineEnd = buffer.indexOf('\n');
          if (lineEnd == -1) break;

          var line = buffer.substring(0, lineEnd).trim();
          buffer = buffer.substring(lineEnd + 1);

          if (line.isEmpty || line.startsWith(':')) continue;
          if (!line.startsWith('data:')) continue;

          final dataStr = line.substring(5).trim();
          if (dataStr == '[DONE]') break;

          Map<String, dynamic> parsed;
          try {
            parsed = jsonDecode(dataStr) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }

          if (parsed['error'] != null) {
            final err = parsed['error'];
            final errMsg = err is Map
                ? err['message']?.toString() ?? err.toString()
                : err.toString();
            yield ChatStreamError(errMsg);
            return;
          }

          final choices = parsed['choices'];
          if (choices is! List || choices.isEmpty) continue;

          final delta = choices.first['delta'];
          if (delta is! Map<String, dynamic>) continue;

          final reasoningDelta = _extractReasoningDelta(delta);
          if (reasoningDelta.isNotEmpty) {
            fullReasoning += reasoningDelta;
            yield ChatReasoningDelta(reasoningDelta);
          }

          final contentDelta = delta['content'];
          if (contentDelta is String && contentDelta.isNotEmpty) {
            fullContent += contentDelta;
            yield ChatContentDelta(contentDelta);
          }
        }
      }

      yield ChatStreamDone(
        content: fullContent,
        reasoning: fullReasoning.isEmpty ? null : fullReasoning,
      );
    } catch (e) {
      yield ChatStreamError('Errore di rete: $e');
    } finally {
      client.close();
    }
  }

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
}

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/audio_note.dart';
import '../models/note_structured_data.dart';
import '../models/note_tags_config.dart';
import '../models/transcript_segment.dart';
import 'api_url_resolver.dart';
import 'app_preferences_service.dart';
import 'drop_api_headers.dart';
import 'local_database_service.dart';
import 'processing_foreground_service.dart';
import 'server_quota_service.dart';
import 'supabase_auth_service.dart';

/// Avvia una sola analisi (highlights, speakers, key data) su una nota
/// gia' trascritta. Non ri-trascrive e non segna la nota come in elaborazione.
class NoteAnalysisService {
  NoteAnalysisService._();

  static final NoteAnalysisService instance = NoteAnalysisService._();

  Future<AudioNote> run({
    required AudioNote note,
    required String kind,
  }) async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Sessione scaduta. Effettua di nuovo l\'accesso.');
    }

    final prefs = await AppPreferencesService.instance.loadAiPreferences();
    final tags = await AppPreferencesService.instance.loadNoteTags();
    final apiKey = await AppPreferencesService.instance.loadOpenRouterApiKey();
    final outputLanguage = note.outputLanguage ?? prefs.outputLanguage.id;
    final customPrompt = prefs.customPrompt.trim();

    final url = await ApiUrlResolver.resolveEndpoint(
      '/notes/${note.id}/analyses/$kind',
    );
    await ProcessingForegroundService.acquire(
      kind == 'mind_map' ? 'Mappa mentale in corso' : 'Analisi in corso',
    );
    try {
    final response = await http.post(
      Uri.parse(url),
      headers: DropApiHeaders.json(token),
      body: jsonEncode({
        'ai_model': prefs.model.openRouterId,
        'output_language': outputLanguage,
        if (customPrompt.isNotEmpty) 'custom_prompt': customPrompt,
        'available_tags': tags.tags,
        if (apiKey != null && apiKey.isNotEmpty) 'openrouter_api_key': apiKey,
      }),
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Sessione scaduta. Effettua di nuovo l\'accesso.');
    }
    final quotaError = ServerQuotaService.parseError(response);
    if (quotaError != null) throw quotaError;
    if (response.statusCode == 409) {
      throw Exception('Manca la trascrizione: impossibile analizzare.');
    }
    if (response.statusCode != 200) {
      throw Exception('Analisi non avviata (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final jobId = data['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw Exception('Risposta server senza job_id');
    }

      final result = await _poll(jobId, token);
      final fresh = await LocalDatabaseService.instance.getNote(note.id) ?? note;
      final updated = mergeAnalysisResult(fresh, result);
      await LocalDatabaseService.instance.saveNote(updated);
      return updated;
    } finally {
      await ProcessingForegroundService.release();
    }
  }

  Future<Map<String, dynamic>> _poll(String jobId, String accessToken) async {
    const pollInterval = Duration(seconds: 2);
    const maxAttempts = 90;
    var gatewayFailures = 0;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final url = await ApiUrlResolver.resolveEndpoint('/jobs/$jobId');
      final token = SupabaseAuthService.instance.currentAccessToken;
      final response = await http.get(
        Uri.parse(url),
        headers: DropApiHeaders.auth(
          token == null || token.isEmpty ? accessToken : token,
        ),
      );

      if (response.statusCode == 502 ||
          response.statusCode == 503 ||
          response.statusCode == 504 ||
          response.statusCode == 500) {
        gatewayFailures++;
        if (gatewayFailures >= 8) {
          throw Exception('Server temporaneamente non disponibile');
        }
        await Future<void>.delayed(pollInterval);
        continue;
      }

      if (response.statusCode != 200) {
        throw Exception('Polling fallito (${response.statusCode})');
      }

      gatewayFailures = 0;
      final job = jsonDecode(response.body) as Map<String, dynamic>;
      final status = job['status'] as String?;
      if (status == 'completed') {
        final result = job['result'];
        if (result is Map<String, dynamic>) return result;
        throw Exception('Risposta job incompleta');
      }
      if (status == 'failed') {
        throw Exception(job['error'] as String? ?? 'Analisi fallita');
      }
      await Future<void>.delayed(pollInterval);
    }

    throw Exception('Analisi troppo lunga');
  }
}

AudioNote mergeAnalysisResult(AudioNote local, Map<String, dynamic> data) {
  final incoming = NoteStructuredData.fromResponse(data);
  final structured = incoming.copyWith(
    checkedHighlights: local.structuredData.checkedHighlights,
  );
  final title = (data['title'] as String?)?.trim();
  final summary = data['summary'] as String?;
  final formatted = data['formatted_transcription'] as String?;
  final raw = data['raw_transcription'] as String?;
  final segments = data['transcript_segments'];

  return local.copyWith(
    title: (title != null && title.isNotEmpty) ? title : local.title,
    summary: (summary != null && summary.isNotEmpty) ? summary : local.summary,
    transcription: (formatted != null && formatted.isNotEmpty)
        ? formatted
        : local.transcription,
    rawTranscription: (raw != null && raw.isNotEmpty) ? raw : local.rawTranscription,
    structuredData: structured,
    tag: structured.isReady(NoteStructuredData.keyDataKind)
        ? NoteTagsConfig.normalizeTag(structured.tagLabel)
        : local.tag,
    transcriptSegments: segments != null
        ? TranscriptSegment.listFromResponse(segments)
        : local.transcriptSegments,
    analysisStatus: NoteAnalysisStatus.ready,
    clearAnalysisProgress: true,
    sourceLanguage: data['source_language'] as String? ?? local.sourceLanguage,
    outputLanguage: data['output_language'] as String? ?? local.outputLanguage,
  );
}

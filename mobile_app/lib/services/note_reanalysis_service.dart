import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_preferences.dart';
import 'api_url_resolver.dart';
import 'drop_api_headers.dart';
import 'server_quota_service.dart';
import 'supabase_auth_service.dart';

/// Chiede al backend di ri-trascrivere e rianalizzare una nota gia' esistente,
/// riusando l'audio conservato sul server.
class NoteReanalysisService {
  NoteReanalysisService._();

  static final NoteReanalysisService instance = NoteReanalysisService._();

  /// Restituisce il job_id da seguire in polling.
  Future<String> requestReanalysis({
    required String noteId,
    required AiPreferences prefs,
    required List<String> availableTags,
  }) async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Sessione scaduta. Effettua di nuovo l\'accesso.');
    }

    final url = await ApiUrlResolver.resolveEndpoint(
      '/notes/$noteId/reanalyze',
    );
    final customPrompt = prefs.customPrompt.trim();

    final response = await http.post(
      Uri.parse(url),
      headers: DropApiHeaders.json(token),
      body: jsonEncode({
        'ai_model': prefs.model.openRouterId,
        'language': prefs.transcriptionLanguage.name,
        if (customPrompt.isNotEmpty) 'custom_prompt': customPrompt,
        'available_tags': availableTags,
      }),
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Sessione scaduta. Effettua di nuovo l\'accesso.');
    }
    final quotaError = ServerQuotaService.parseError(response);
    if (quotaError != null) throw quotaError;
    if (response.statusCode == 409) {
      throw Exception(
        'L\'audio non e\' piu\' sul server: impossibile rifare l\'analisi.',
      );
    }
    if (response.statusCode == 404) {
      throw Exception('Nota non trovata sul server.');
    }
    if (response.statusCode != 200) {
      throw Exception('Rianalisi non avviata (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final jobId = data['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw Exception('Risposta server senza job_id');
    }
    return jobId;
  }
}

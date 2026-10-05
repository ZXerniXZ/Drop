import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_preferences.dart';
import '../models/app_language.dart';
import '../models/audio_note.dart';
import 'api_url_resolver.dart';
import 'audio_binary_store.dart';
import 'chunked_upload_service.dart';
import 'drop_api_headers.dart';
import 'share_link.dart';
import 'supabase_auth_service.dart';

class NoteShareException implements Exception {
  NoteShareException(this.message);
  final String message;

  @override
  String toString() => message;
}

class NoteShareService {
  NoteShareService._();

  static final NoteShareService instance = NoteShareService._();

  Future<String> _requireToken() async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) {
      throw NoteShareException('Accesso richiesto. Effettua di nuovo l\'accesso.');
    }
    return token;
  }

  Future<bool> _noteExistsOnServer(String noteId, String accessToken) async {
    final url = await ApiUrlResolver.resolveEndpoint('/notes/$noteId');
    final response = await http.get(
      Uri.parse(url),
      headers: DropApiHeaders.auth(accessToken),
    );
    return response.statusCode == 200;
  }

  Future<void> publishNote(
    AudioNote note, {
    String? uploadId,
    AiPreferences? prefs,
    bool uploadAudio = true,
  }) async {
    final accessToken = await _requireToken();
    var resolvedUploadId = uploadId;

    if (uploadAudio &&
        (resolvedUploadId == null || resolvedUploadId.isEmpty) &&
        note.audioPath.isNotEmpty &&
        await AudioBinaryStore.instance.exists(note.audioPath)) {
      final completed = await ChunkedUploadService.instance.uploadFile(
        filePath: note.audioPath,
        accessToken: accessToken,
        prefs: prefs ?? const AiPreferences(),
        availableTags: const [],
        noteId: note.id,
        durationSeconds: note.durationSeconds,
        deferAnalysis: true,
      );
      resolvedUploadId = completed.uploadId;
    }

    final url = await ApiUrlResolver.resolveEndpoint('/notes/publish');
    final sd = note.structuredData;
    final response = await http.post(
      Uri.parse(url),
      headers: DropApiHeaders.json(accessToken),
      body: jsonEncode({
        'note_id': note.id,
        if (resolvedUploadId != null && resolvedUploadId.isNotEmpty)
          'upload_id': resolvedUploadId,
        'title': note.title,
        'summary': note.summary,
        'formatted_transcription': note.transcription,
        'raw_transcription': note.rawTranscription,
        'highlights': sd.highlights,
        'key_data': {
          ...sd.keyDataPayload(),
          'tags': sd.tagLabel.isNotEmpty ? sd.tagLabel : note.tag,
        },
        'analysis_state': sd.analysisState,
        'speaker_view': sd.speakerView
            .map(
              (b) => {
                'speaker': b.speaker,
                'text': b.text,
                if (b.time != null) 'time': b.time,
              },
            )
            .toList(),
        'transcript_segments': note.transcriptSegments
            .map((s) => s.toMap())
            .toList(),
        'audio_duration': note.durationSeconds,
        if (note.sourceLanguage != null) 'source_language': note.sourceLanguage,
        if (note.outputLanguage != null) 'output_language': note.outputLanguage,
      }),
    );
    if (response.statusCode != 200) {
      throw NoteShareException(
        'Impossibile pubblicare la nota (${response.statusCode})',
      );
    }
  }

  Future<String> createShareUrl(AudioNote note, {AiPreferences? prefs}) async {
    final accessToken = await _requireToken();
    final alreadyOnServer = await _noteExistsOnServer(note.id, accessToken);
    await publishNote(
      note,
      prefs: prefs,
      uploadAudio: !alreadyOnServer,
    );

    final url = await ApiUrlResolver.resolveEndpoint('/notes/${note.id}/share');
    final response = await http.post(
      Uri.parse(url),
      headers: DropApiHeaders.json(accessToken),
    );
    if (response.statusCode == 409) {
      throw NoteShareException('La nota non e\' ancora pronta da condividere');
    }
    if (response.statusCode != 200) {
      throw NoteShareException(
        'Impossibile creare il link (${response.statusCode})',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw NoteShareException('Risposta server senza token');
    }
    return ShareLink.buildUrl(token);
  }

  Future<bool> hasActiveShare(String noteId) async {
    final accessToken = await _requireToken();
    final url = await ApiUrlResolver.resolveEndpoint('/notes/$noteId/share');
    final response = await http.get(
      Uri.parse(url),
      headers: DropApiHeaders.auth(accessToken),
    );
    if (response.statusCode != 200) return false;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['active'] == true;
  }

  Future<void> revokeShare(String noteId) async {
    final accessToken = await _requireToken();
    final url = await ApiUrlResolver.resolveEndpoint('/notes/$noteId/share');
    final response = await http.delete(
      Uri.parse(url),
      headers: DropApiHeaders.auth(accessToken),
    );
    if (response.statusCode != 200) {
      throw NoteShareException('Impossibile revocare il link');
    }
  }

  Future<AudioNote> claimShare(String token) async {
    final accessToken = await _requireToken();
    final url = await ApiUrlResolver.resolveEndpoint('/shares/$token/claim');
    final response = await http.post(
      Uri.parse(url),
      headers: DropApiHeaders.json(accessToken),
    );
    if (response.statusCode == 404) {
      throw NoteShareException('Link non valido o scaduto');
    }
    if (response.statusCode != 200) {
      throw NoteShareException(
        'Impossibile aprire la nota (${response.statusCode})',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AudioNote.fromServerNote(data);
  }
}

class DetectedLanguages {
  const DetectedLanguages({
    this.detected,
    this.sourceLanguage = AppLanguage.automatic,
    this.outputLanguage = AppLanguage.italian,
  });

  final AppLanguage? detected;
  final AppLanguage sourceLanguage;
  final AppLanguage outputLanguage;
}

class LanguageDetectService {
  LanguageDetectService._();

  static final LanguageDetectService instance = LanguageDetectService._();

  Uri _withNoiseReduction(Uri uri, bool noiseReduction) {
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'noise_reduction': noiseReduction ? 'true' : 'false',
      },
    );
  }

  Future<String> _requireToken() async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Sessione scaduta. Effettua di nuovo l\'accesso.');
    }
    return token;
  }

  DetectedLanguages _parse(
    Map<String, dynamic> data, {
    required AppLanguage fallbackOutput,
  }) {
    final detected = AppLanguage.fromKey(data['detected_language'] as String?);
    final source = AppLanguage.fromKey(
      data['source_language'] as String? ?? data['detected_language'] as String?,
    );
    final outputRaw = data['output_language'] as String?;
    final output = outputRaw == null || outputRaw.isEmpty
        ? (detected.isAutomatic ? fallbackOutput : detected)
        : AppLanguage.outputFromKey(outputRaw);
    return DetectedLanguages(
      detected: detected.isAutomatic ? null : detected,
      sourceLanguage: source,
      outputLanguage: output,
    );
  }

  Future<DetectedLanguages> detectFromUpload(
    String uploadId, {
    required AppLanguage fallbackOutput,
    bool noiseReduction = false,
  }) async {
    final accessToken = await _requireToken();
    final url = await ApiUrlResolver.resolveEndpoint(
      '/upload-audio/sessions/$uploadId/detect-language',
    );
    final response = await http.post(
      _withNoiseReduction(Uri.parse(url), noiseReduction),
      headers: DropApiHeaders.json(accessToken),
    );
    if (response.statusCode != 200) {
      return DetectedLanguages(
        sourceLanguage: AppLanguage.automatic,
        outputLanguage: fallbackOutput,
      );
    }
    return _parse(
      jsonDecode(response.body) as Map<String, dynamic>,
      fallbackOutput: fallbackOutput,
    );
  }

  Future<DetectedLanguages> detectFromNote(
    String noteId, {
    required AppLanguage fallbackOutput,
    bool noiseReduction = false,
  }) async {
    final accessToken = await _requireToken();
    final url = await ApiUrlResolver.resolveEndpoint(
      '/notes/$noteId/detect-language',
    );
    final response = await http.post(
      _withNoiseReduction(Uri.parse(url), noiseReduction),
      headers: DropApiHeaders.json(accessToken),
    );
    if (response.statusCode != 200) {
      return DetectedLanguages(
        sourceLanguage: AppLanguage.automatic,
        outputLanguage: fallbackOutput,
      );
    }
    return _parse(
      jsonDecode(response.body) as Map<String, dynamic>,
      fallbackOutput: fallbackOutput,
    );
  }
}

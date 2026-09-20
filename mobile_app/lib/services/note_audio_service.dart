import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_url_resolver.dart';
import 'audio_binary_store.dart';
import 'audio_recording_config.dart';
import 'supabase_auth_service.dart';

/// Recupera dal backend l'audio di una nota quando non e' piu' sul telefono,
/// per esempio dopo una reinstallazione o su un secondo dispositivo.
class NoteAudioService {
  NoteAudioService._();

  static final NoteAudioService instance = NoteAudioService._();

  /// Percorso/handle locale dell'audio se e' presente sul dispositivo.
  ///
  /// Il nome del file deriva dall'id della nota, quindi un audio scaricato in
  /// precedenza si ritrova anche se la nota in database non ha un audio_path.
  Future<String?> localPathIfExists(
    String noteId, {
    String? currentPath,
  }) async {
    final store = AudioBinaryStore.instance;
    if (currentPath != null &&
        currentPath.isNotEmpty &&
        await store.exists(currentPath)) {
      return currentPath;
    }

    final canonical = await store.canonicalHandle(noteId);
    if (await store.exists(canonical)) return canonical;
    return null;
  }

  /// Restituisce l'handle locale dell'audio, scaricandolo se serve.
  /// Restituisce null se il server non ha piu' il file.
  Future<String?> ensureLocalAudio(
    String noteId, {
    String? currentPath,
  }) async {
    final local = await localPathIfExists(noteId, currentPath: currentPath);
    if (local != null) return local;
    return downloadAudio(noteId);
  }

  Future<String?> downloadAudio(String noteId) async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Sessione scaduta. Effettua di nuovo l\'accesso.');
    }

    final url = await ApiUrlResolver.resolveEndpoint('/notes/$noteId/audio');
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['Authorization'] = 'Bearer $token';
      final response = await client.send(request);

      if (response.statusCode == 404) return null;
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Sessione scaduta. Effettua di nuovo l\'accesso.');
      }
      if (response.statusCode != 200) {
        throw Exception('Download audio fallito (${response.statusCode})');
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) return null;

      final mime = (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim();
      final extension = AudioRecordingConfig.extensionFromMime(
        mime.isEmpty ? null : mime,
      );

      return await AudioBinaryStore.instance.saveBytes(
        noteId: noteId,
        bytes: bytes,
        extension: extension,
        mimeType: mime.isEmpty
            ? AudioRecordingConfig.mimeFromExtension(extension)
            : mime,
      );
    } finally {
      client.close();
    }
  }
}

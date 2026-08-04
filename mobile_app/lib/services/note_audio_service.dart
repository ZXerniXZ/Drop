import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api_url_resolver.dart';
import 'audio_recording_config.dart';
import 'supabase_auth_service.dart';

/// Recupera dal backend l'audio di una nota quando non e' piu' sul telefono,
/// per esempio dopo una reinstallazione o su un secondo dispositivo.
class NoteAudioService {
  NoteAudioService._();

  static final NoteAudioService instance = NoteAudioService._();

  /// Percorso locale dell'audio se e' presente sul telefono.
  ///
  /// Il nome del file deriva dall'id della nota, quindi un audio scaricato in
  /// precedenza si ritrova anche se la nota in database non ha un audio_path.
  Future<String?> localPathIfExists(
    String noteId, {
    String? currentPath,
  }) async {
    if (currentPath != null &&
        currentPath.isNotEmpty &&
        await File(currentPath).exists()) {
      return currentPath;
    }

    final canonical = await _destinationFor(noteId);
    if (await File(canonical).exists()) return canonical;
    return null;
  }

  /// Restituisce il percorso locale dell'audio, scaricandolo se serve.
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
    File? partial;
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

      final destination = await _destinationFor(noteId);
      // Scrittura in streaming: un audio lungo non deve stare tutto in memoria.
      partial = File('$destination.part');
      final sink = partial.openWrite();
      await response.stream.pipe(sink);

      if (await partial.length() == 0) {
        await partial.delete();
        return null;
      }

      final file = await partial.rename(destination);
      partial = null;
      return file.path;
    } finally {
      if (partial != null && await partial.exists()) {
        await partial.delete();
      }
      client.close();
    }
  }

  Future<String> _destinationFor(String noteId) async {
    final dir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${dir.path}/recordings');
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    return AudioRecordingConfig.buildPersistedPath(recordingsDir.path, noteId);
  }
}

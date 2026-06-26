import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/ai_preferences.dart';
import 'api_url_resolver.dart';

const int chunkedUploadChunkSize = 2 * 1024 * 1024;
const int legacyUploadMaxBytes = 4 * 1024 * 1024;
const int maxChunkRetries = 3;

typedef UploadProgressCallback = void Function(int uploadedChunks, int totalChunks);

class ChunkedUploadService {
  ChunkedUploadService._();

  static final ChunkedUploadService instance = ChunkedUploadService._();

  Future<String> uploadFileAndStartJob({
    required String filePath,
    required String accessToken,
    required AiPreferences prefs,
    required List<String> availableTags,
    String? existingUploadSessionId,
    int? lastUploadedChunkIndex,
    UploadProgressCallback? onProgress,
    Future<void> Function(String uploadSessionId, int uploadedChunks)?
        onSessionProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File audio non trovato');
    }

    final totalSize = await file.length();
    final totalChunks = (totalSize + chunkedUploadChunkSize - 1) ~/ chunkedUploadChunkSize;
    if (totalChunks == 0) {
      throw Exception('File audio vuoto');
    }

    var uploadId = existingUploadSessionId;
    var startChunk = (lastUploadedChunkIndex ?? -1) + 1;

    if (uploadId != null && uploadId.isNotEmpty) {
      final status = await _getSession(uploadId, accessToken);
      final received = (status['received_chunks'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .toSet();
      if (received.length == totalChunks) {
        return _completeSession(uploadId, accessToken);
      }
      startChunk = 0;
      for (var i = 0; i < totalChunks; i++) {
        if (!received.contains(i)) {
          startChunk = i;
          break;
        }
      }
    } else {
      uploadId = await _createSession(
        accessToken: accessToken,
        filename: filePath.split(Platform.pathSeparator).last,
        totalSize: totalSize,
        totalChunks: totalChunks,
        prefs: prefs,
        availableTags: availableTags,
      );
      await onSessionProgress?.call(uploadId, -1);
      startChunk = 0;
    }

    final randomAccess = await file.open();

    try {
      for (var index = startChunk; index < totalChunks; index++) {
        final chunkLength = index < totalChunks - 1
            ? chunkedUploadChunkSize
            : totalSize - (chunkedUploadChunkSize * (totalChunks - 1));

        await randomAccess.setPosition(index * chunkedUploadChunkSize);
        final chunkBytes = await randomAccess.read(chunkLength);

        await _uploadChunkWithRetry(
          uploadId: uploadId,
          index: index,
          bytes: chunkBytes,
          accessToken: accessToken,
        );

        onProgress?.call(index + 1, totalChunks);
        await onSessionProgress?.call(uploadId, index);
      }
    } finally {
      await randomAccess.close();
    }

    return _completeSession(uploadId, accessToken);
  }

  Future<String> _createSession({
    required String accessToken,
    required String filename,
    required int totalSize,
    required int totalChunks,
    required AiPreferences prefs,
    required List<String> availableTags,
  }) async {
    final url = await ApiUrlResolver.resolveEndpoint('/upload-audio/sessions');
    final body = <String, dynamic>{
      'filename': filename,
      'total_size': totalSize,
      'total_chunks': totalChunks,
      'ai_model': prefs.model.openRouterId,
      'language': prefs.transcriptionLanguage.name,
      'available_tags': availableTags,
    };
    if (prefs.customPrompt.trim().isNotEmpty) {
      body['custom_prompt'] = prefs.customPrompt.trim();
    }

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    _ensureAuthOrThrow(response);
    if (response.statusCode != 200) {
      throw Exception(_errorDetail(response, 'Creazione sessione upload fallita'));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final uploadId = data['upload_id'] as String?;
    if (uploadId == null || uploadId.isEmpty) {
      throw Exception('Risposta server senza upload_id');
    }
    return uploadId;
  }

  Future<Map<String, dynamic>> _getSession(
    String uploadId,
    String accessToken,
  ) async {
    final url = await ApiUrlResolver.resolveEndpoint(
      '/upload-audio/sessions/$uploadId',
    );
    final response = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    _ensureAuthOrThrow(response);
    if (response.statusCode != 200) {
      throw Exception(_errorDetail(response, 'Lettura sessione upload fallita'));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _uploadChunkWithRetry({
    required String uploadId,
    required int index,
    required List<int> bytes,
    required String accessToken,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < maxChunkRetries; attempt++) {
      try {
        await _uploadChunk(
          uploadId: uploadId,
          index: index,
          bytes: bytes,
          accessToken: accessToken,
        );
        return;
      } catch (e) {
        lastError = e;
        if (attempt < maxChunkRetries - 1) {
          final delayMs = (500 * pow(2, attempt)).toInt();
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        }
      }
    }
    throw Exception('Chunk $index fallito dopo $maxChunkRetries tentativi: $lastError');
  }

  Future<void> _uploadChunk({
    required String uploadId,
    required int index,
    required List<int> bytes,
    required String accessToken,
  }) async {
    final url = await ApiUrlResolver.resolveEndpoint(
      '/upload-audio/sessions/$uploadId/chunks/$index',
    );
    final response = await http.put(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
    );
    _ensureAuthOrThrow(response);
    if (response.statusCode != 200) {
      throw Exception(_errorDetail(response, 'Upload chunk $index fallito'));
    }
  }

  Future<String> _completeSession(String uploadId, String accessToken) async {
    final url = await ApiUrlResolver.resolveEndpoint(
      '/upload-audio/sessions/$uploadId/complete',
    );
    final response = await http.post(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    _ensureAuthOrThrow(response);
    if (response.statusCode != 200) {
      throw Exception(_errorDetail(response, 'Completamento upload fallito'));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final jobId = data['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw Exception('Risposta server senza job_id');
    }
    return jobId;
  }

  void _ensureAuthOrThrow(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Sessione scaduta. Effettua di nuovo l\'accesso.');
    }
  }

  String _errorDetail(http.Response response, String fallback) {
    try {
      final errJson = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = errJson['detail'];
      if (detail != null) return '$fallback (${response.statusCode}): $detail';
    } catch (_) {}
    return '$fallback (${response.statusCode}): ${response.body}';
  }
}

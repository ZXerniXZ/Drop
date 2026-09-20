import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'audio_recording_config.dart';
import 'audio_storage_info.dart';

class _MemAudio {
  _MemAudio({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
  String? objectUrl;
}

class AudioBinaryStore {
  AudioBinaryStore._();

  static final AudioBinaryStore instance = AudioBinaryStore._();

  final Map<String, _MemAudio> _memory = {};
  int _seq = 0;

  bool get playbackUsesUrl => true;

  Future<String> createRecordingDestination({String extension = 'm4a'}) async {
    return 'recording.$extension';
  }

  Future<String> adoptRecorderOutput(
    String recorderPath, {
    String suggestedExtension = 'm4a',
  }) async {
    if (recorderPath.isEmpty) {
      throw Exception('File audio non trovato');
    }
    if (recorderPath.startsWith('mem:') && _memory.containsKey(recorderPath)) {
      return recorderPath;
    }

    final response = await http.get(Uri.parse(recorderPath));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw Exception('File audio non trovato');
    }

    final mime = (response.headers['content-type'] ?? '')
        .split(';')
        .first
        .trim();
    final ext = AudioRecordingConfig.extensionFromMime(
      mime.isEmpty ? null : mime,
      fallback: suggestedExtension,
    );
    final id = 'mem:${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
    _memory[id] = _MemAudio(
      bytes: response.bodyBytes,
      filename: 'recording.$ext',
      mimeType: mime.isEmpty
          ? AudioRecordingConfig.mimeFromExtension(ext)
          : mime,
    );
    return id;
  }

  Future<String> persistForNote(String handle, String noteId) async {
    final existing = _memory[handle];
    if (existing == null) return handle;
    final id = 'mem:$noteId';
    if (id == handle) return handle;
    _revoke(existing);
    _memory[id] = _MemAudio(
      bytes: existing.bytes,
      filename: '$noteId.${_extensionOf(existing.filename)}',
      mimeType: existing.mimeType,
    );
    if (handle != id) _memory.remove(handle);
    return id;
  }

  Future<String> canonicalHandle(String noteId) async => 'mem:$noteId';

  Future<int> byteLength(String handle) async {
    final entry = _memory[handle];
    if (entry == null) throw Exception('File audio non trovato');
    return entry.bytes.length;
  }

  Future<bool> exists(String handle) async {
    if (handle.isEmpty) return false;
    return _memory.containsKey(handle);
  }

  Future<void> delete(String handle) async {
    final entry = _memory.remove(handle);
    if (entry != null) _revoke(entry);
  }

  Future<Uint8List> readAll(String handle) async {
    final entry = _memory[handle];
    if (entry == null) throw Exception('File audio non trovato');
    return entry.bytes;
  }

  Future<Uint8List> readRange(String handle, int start, int length) async {
    final entry = _memory[handle];
    if (entry == null) throw Exception('File audio non trovato');
    final end = (start + length).clamp(0, entry.bytes.length);
    final begin = start.clamp(0, entry.bytes.length);
    return Uint8List.fromList(entry.bytes.sublist(begin, end));
  }

  String filenameOf(String handle) {
    return _memory[handle]?.filename ?? 'recording.m4a';
  }

  Future<String> saveBytes({
    required String noteId,
    required Uint8List bytes,
    String extension = 'm4a',
    String mimeType = 'audio/mp4',
  }) async {
    final id = 'mem:$noteId';
    final previous = _memory[id];
    if (previous != null) _revoke(previous);
    _memory[id] = _MemAudio(
      bytes: bytes,
      filename: '$noteId.$extension',
      mimeType: mimeType,
    );
    return id;
  }

  Future<String?> playbackUri(String handle) async {
    final entry = _memory[handle];
    if (entry == null) return null;
    final cached = entry.objectUrl;
    if (cached != null) return cached;
    final blob = web.Blob(
      [entry.bytes.toJS].toJS,
      web.BlobPropertyBag(type: entry.mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    entry.objectUrl = url;
    return url;
  }

  Future<AudioStorageInfo> getStorageInfo() async {
    return const AudioStorageInfo(
      bytesUsed: 0,
      fileCount: 0,
      browserManaged: true,
    );
  }

  Future<int> clearCache() async {
    final count = _memory.length;
    for (final entry in _memory.values) {
      _revoke(entry);
    }
    _memory.clear();
    return count;
  }

  void _revoke(_MemAudio entry) {
    final url = entry.objectUrl;
    if (url == null) return;
    web.URL.revokeObjectURL(url);
    entry.objectUrl = null;
  }

  String _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return 'm4a';
    return filename.substring(dot + 1);
  }
}

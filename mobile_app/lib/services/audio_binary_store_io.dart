import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'audio_recording_config.dart';
import 'audio_storage_info.dart';

class AudioBinaryStore {
  AudioBinaryStore._();

  static final AudioBinaryStore instance = AudioBinaryStore._();

  bool get playbackUsesUrl => false;

  Future<Directory> _recordingsDir({bool create = true}) async {
    final dir = await getApplicationDocumentsDirectory();
    final recordings = Directory('${dir.path}/recordings');
    if (create && !await recordings.exists()) {
      await recordings.create(recursive: true);
    }
    return recordings;
  }

  Future<String> createRecordingDestination({String extension = 'm4a'}) async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.$extension';
  }

  Future<String> adoptRecorderOutput(
    String recorderPath, {
    String suggestedExtension = 'm4a',
  }) async {
    if (recorderPath.isEmpty) {
      throw Exception('File audio non trovato');
    }
    if (!await File(recorderPath).exists()) {
      throw Exception('File audio non trovato');
    }
    return recorderPath;
  }

  Future<String> persistForNote(String handle, String noteId) async {
    try {
      final recordings = await _recordingsDir();
      final ext = p.extension(handle).replaceFirst('.', '');
      final suffix = ext.isEmpty ? 'm4a' : ext;
      final dest = '${recordings.path}/$noteId.$suffix';
      if (p.normalize(handle) == p.normalize(dest)) return dest;
      await File(handle).copy(dest);
      return dest;
    } catch (_) {
      return handle;
    }
  }

  Future<String> canonicalHandle(String noteId) async {
    final recordings = await _recordingsDir();
    return AudioRecordingConfig.buildPersistedPath(recordings.path, noteId);
  }

  Future<int> byteLength(String handle) async => File(handle).length();

  Future<bool> exists(String handle) async {
    if (handle.isEmpty) return false;
    return File(handle).exists();
  }

  Future<void> delete(String handle) async {
    if (handle.isEmpty) return;
    final file = File(handle);
    if (await file.exists()) await file.delete();
  }

  Future<Uint8List> readAll(String handle) async {
    return File(handle).readAsBytes();
  }

  Future<Uint8List> readRange(String handle, int start, int length) async {
    final file = await File(handle).open();
    try {
      await file.setPosition(start);
      return await file.read(length);
    } finally {
      await file.close();
    }
  }

  String filenameOf(String handle) => p.basename(handle);

  Future<String> saveBytes({
    required String noteId,
    required Uint8List bytes,
    String extension = 'm4a',
    String mimeType = 'audio/mp4',
  }) async {
    final recordings = await _recordingsDir();
    final dest = '${recordings.path}/$noteId.$extension';
    final partial = File('$dest.part');
    await partial.writeAsBytes(bytes, flush: true);
    if (await File(dest).exists()) {
      await File(dest).delete();
    }
    await partial.rename(dest);
    return dest;
  }

  Future<String?> playbackUri(String handle) async => handle;

  Future<AudioStorageInfo> getStorageInfo() async {
    final recordings = await _recordingsDir(create: false);
    if (!await recordings.exists()) {
      return const AudioStorageInfo(bytesUsed: 0, fileCount: 0);
    }

    var bytes = 0;
    var count = 0;
    await for (final entity in recordings.list()) {
      if (entity is File && _isAudioFile(entity.path)) {
        bytes += await entity.length();
        count++;
      }
    }
    return AudioStorageInfo(bytesUsed: bytes, fileCount: count);
  }

  Future<int> clearCache() async {
    final recordings = await _recordingsDir(create: false);
    if (!await recordings.exists()) return 0;

    var deleted = 0;
    await for (final entity in recordings.list()) {
      if (entity is File && _isAudioFile(entity.path)) {
        await entity.delete();
        deleted++;
      }
    }
    return deleted;
  }

  bool _isAudioFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return const {'.m4a', '.mp3', '.wav', '.aac', '.ogg', '.webm', '.flac'}
        .contains(ext);
  }
}

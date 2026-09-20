import 'dart:typed_data';

import 'audio_storage_info.dart';

/// Cross-platform handle for a recorded or downloaded audio blob.
///
/// Native: filesystem path. Web: `mem:{id}` key into an in-memory map.
class AudioBinaryStore {
  AudioBinaryStore._();

  static final AudioBinaryStore instance = AudioBinaryStore._();

  bool get playbackUsesUrl => false;

  Future<String> createRecordingDestination({String extension = 'm4a'}) async {
    return 'recording.$extension';
  }

  Future<String> adoptRecorderOutput(
    String recorderPath, {
    String suggestedExtension = 'm4a',
  }) async {
    return recorderPath;
  }

  Future<String> persistForNote(String handle, String noteId) async => handle;

  Future<String> canonicalHandle(String noteId) async => noteId;

  Future<int> byteLength(String handle) async => 0;

  Future<bool> exists(String handle) async => false;

  Future<void> delete(String handle) async {}

  Future<Uint8List> readAll(String handle) async => Uint8List(0);

  Future<Uint8List> readRange(String handle, int start, int length) async {
    return Uint8List(0);
  }

  String filenameOf(String handle) {
    final slash = handle.replaceAll('\\', '/').lastIndexOf('/');
    return slash >= 0 ? handle.substring(slash + 1) : handle;
  }

  Future<String> saveBytes({
    required String noteId,
    required Uint8List bytes,
    String extension = 'm4a',
    String mimeType = 'audio/mp4',
  }) async {
    return noteId;
  }

  Future<String?> playbackUri(String handle) async => handle;

  Future<AudioStorageInfo> getStorageInfo() async {
    return const AudioStorageInfo(
      bytesUsed: 0,
      fileCount: 0,
      browserManaged: true,
    );
  }

  Future<int> clearCache() async => 0;
}

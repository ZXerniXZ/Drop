import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_database_service.dart';

class AudioStorageInfo {
  const AudioStorageInfo({required this.bytesUsed, required this.fileCount});

  final int bytesUsed;
  final int fileCount;

  String get formattedSize {
    if (bytesUsed < 1024) return '$bytesUsed B';
    if (bytesUsed < 1024 * 1024) {
      return '${(bytesUsed / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytesUsed / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class AudioStorageService {
  AudioStorageService._();

  static Future<Directory?> _recordingsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final recordings = Directory('${dir.path}/recordings');
    if (!await recordings.exists()) return null;
    return recordings;
  }

  static Future<AudioStorageInfo> getStorageInfo() async {
    final dir = await _recordingsDir();
    if (dir == null) {
      return const AudioStorageInfo(bytesUsed: 0, fileCount: 0);
    }

    var bytes = 0;
    var count = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.m4a')) {
        bytes += await entity.length();
        count++;
      }
    }
    return AudioStorageInfo(bytesUsed: bytes, fileCount: count);
  }

  static Future<int> clearAudioCache() async {
    final dir = await _recordingsDir();
    if (dir == null) return 0;

    var deleted = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.m4a')) {
        await entity.delete();
        deleted++;
      }
    }

    await LocalDatabaseService.instance.clearAllAudioPaths();
    return deleted;
  }
}

import 'audio_binary_store.dart';
import 'audio_storage_info.dart';
import 'local_database_service.dart';

export 'audio_storage_info.dart';

class AudioStorageService {
  AudioStorageService._();

  static Future<AudioStorageInfo> getStorageInfo() {
    return AudioBinaryStore.instance.getStorageInfo();
  }

  static Future<int> clearAudioCache() async {
    final deleted = await AudioBinaryStore.instance.clearCache();
    await LocalDatabaseService.instance.clearAllAudioPaths();
    return deleted;
  }
}

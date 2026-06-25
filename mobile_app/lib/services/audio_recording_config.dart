import 'package:record/record.dart';

/// Registrazione vocale compressa AAC in container M4A (non WAV grezzo).
class AudioRecordingConfig {
  AudioRecordingConfig._();

  static const String fileExtension = 'm4a';

  static const RecordConfig recordConfig = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 96000,
    sampleRate: 44100,
    numChannels: 1,
  );

  static String buildTempPath(String directory) {
    return '$directory/recording_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
  }

  static String buildPersistedPath(String directory, String noteId) {
    return '$directory/$noteId.$fileExtension';
  }
}

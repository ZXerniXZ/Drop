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

  static const RecordConfig opusConfig = RecordConfig(
    encoder: AudioEncoder.opus,
    bitRate: 96000,
    sampleRate: 48000,
    numChannels: 1,
  );

  static const RecordConfig wavConfig = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 44100,
    numChannels: 1,
  );

  static Future<RecordConfig> resolve(AudioRecorder recorder) async {
    if (await recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      return recordConfig;
    }
    if (await recorder.isEncoderSupported(AudioEncoder.opus)) {
      return opusConfig;
    }
    if (await recorder.isEncoderSupported(AudioEncoder.wav)) {
      return wavConfig;
    }
    return recordConfig;
  }

  static String extensionFor(RecordConfig config) {
    switch (config.encoder) {
      case AudioEncoder.opus:
        return 'webm';
      case AudioEncoder.wav:
        return 'wav';
      case AudioEncoder.flac:
        return 'flac';
      case AudioEncoder.aacLc:
      case AudioEncoder.aacEld:
      case AudioEncoder.aacHe:
        return 'm4a';
      default:
        return 'm4a';
    }
  }

  static String mimeFor(RecordConfig config) {
    return mimeFromExtension(extensionFor(config));
  }

  static String extensionFromMime(String? mime, {String fallback = 'm4a'}) {
    switch (mime) {
      case 'audio/mp4':
      case 'audio/m4a':
      case 'audio/aac':
      case 'audio/x-m4a':
        return 'm4a';
      case 'audio/webm':
      case 'video/webm':
        return 'webm';
      case 'audio/mpeg':
      case 'audio/mp3':
        return 'mp3';
      case 'audio/wav':
      case 'audio/x-wav':
      case 'audio/wave':
        return 'wav';
      case 'audio/ogg':
      case 'audio/opus':
        return 'ogg';
      case 'audio/flac':
        return 'flac';
      default:
        return fallback;
    }
  }

  static String mimeFromExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'm4a':
      case 'aac':
        return 'audio/mp4';
      case 'webm':
        return 'audio/webm';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      case 'flac':
        return 'audio/flac';
      default:
        return 'application/octet-stream';
    }
  }

  static String buildTempPath(String directory) {
    return '$directory/recording_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
  }

  static String buildPersistedPath(String directory, String noteId) {
    return '$directory/$noteId.$fileExtension';
  }
}

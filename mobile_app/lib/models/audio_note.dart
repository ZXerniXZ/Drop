class AudioNote {
  const AudioNote({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.audioPath,
    required this.transcription,
    required this.summary,
    this.rawTranscription = '',
    this.durationSeconds = 0,
  });

  final String id;
  final String title;
  final DateTime dateTime;
  final String audioPath;
  final String transcription;
  final String summary;
  final String rawTranscription;
  final int durationSeconds;

  static String titleFromDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return 'Nota $day/$month $hour:$minute';
  }

  /// Es. `15m 56s`, `45s`, `1h 2m 3s`
  static String formatDurationLabel(int totalSeconds) {
    if (totalSeconds <= 0) return '';

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  String get durationLabel => formatDurationLabel(durationSeconds);

  factory AudioNote.fromMap(Map<String, Object?> map) {
    return AudioNote(
      id: map['id'] as String,
      title: map['title'] as String,
      dateTime: DateTime.parse(map['date_time'] as String),
      audioPath: map['audio_path'] as String? ?? '',
      transcription: map['transcription'] as String? ?? '',
      summary: map['summary'] as String? ?? '',
      rawTranscription: map['raw_transcription'] as String? ?? '',
      durationSeconds: map['duration_seconds'] as int? ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'date_time': dateTime.toIso8601String(),
      'audio_path': audioPath,
      'transcription': transcription,
      'summary': summary,
      'raw_transcription': rawTranscription,
      'duration_seconds': durationSeconds,
    };
  }
}

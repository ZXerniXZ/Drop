class AudioNote {
  const AudioNote({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.audioPath,
    required this.transcription,
    required this.summary,
    this.rawTranscription = '',
  });

  final String id;
  final String title;
  final DateTime dateTime;
  final String audioPath;
  final String transcription;
  final String summary;
  final String rawTranscription;

  static String titleFromDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return 'Nota $day/$month $hour:$minute';
  }

  factory AudioNote.fromMap(Map<String, Object?> map) {
    return AudioNote(
      id: map['id'] as String,
      title: map['title'] as String,
      dateTime: DateTime.parse(map['date_time'] as String),
      audioPath: map['audio_path'] as String? ?? '',
      transcription: map['transcription'] as String? ?? '',
      summary: map['summary'] as String? ?? '',
      rawTranscription: map['raw_transcription'] as String? ?? '',
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
    };
  }
}

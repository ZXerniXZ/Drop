import 'note_structured_data.dart';
import 'note_tags_config.dart';

enum NoteAnalysisStatus {
  processing('processing'),
  ready('ready'),
  failed('failed');

  const NoteAnalysisStatus(this.dbValue);
  final String dbValue;

  static NoteAnalysisStatus fromString(String? value) {
    return NoteAnalysisStatus.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => NoteAnalysisStatus.ready,
    );
  }

  bool get isProcessing => this == NoteAnalysisStatus.processing;
}

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
    this.isNew = false,
    this.tag = 'Memo',
    this.analysisStatus = NoteAnalysisStatus.ready,
    this.structuredData = const NoteStructuredData(),
  });

  final String id;
  final String title;
  final DateTime dateTime;
  final String audioPath;
  final String transcription;
  final String summary;
  final String rawTranscription;
  final int durationSeconds;
  final bool isNew;
  final String tag;
  final NoteAnalysisStatus analysisStatus;
  final NoteStructuredData structuredData;

  bool get isProcessing => analysisStatus.isProcessing;

  bool get isFailed => analysisStatus == NoteAnalysisStatus.failed;

  String get searchableText =>
      '$title $tag $transcription $summary $rawTranscription'.toLowerCase();

  static String titleFromDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return 'Nota $day/$month $hour:$minute';
  }

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

  AudioNote copyWith({
    String? id,
    String? title,
    DateTime? dateTime,
    String? audioPath,
    String? transcription,
    String? summary,
    String? rawTranscription,
    int? durationSeconds,
    bool? isNew,
    String? tag,
    NoteAnalysisStatus? analysisStatus,
    NoteStructuredData? structuredData,
  }) {
    return AudioNote(
      id: id ?? this.id,
      title: title ?? this.title,
      dateTime: dateTime ?? this.dateTime,
      audioPath: audioPath ?? this.audioPath,
      transcription: transcription ?? this.transcription,
      summary: summary ?? this.summary,
      rawTranscription: rawTranscription ?? this.rawTranscription,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isNew: isNew ?? this.isNew,
      tag: tag ?? this.tag,
      analysisStatus: analysisStatus ?? this.analysisStatus,
      structuredData: structuredData ?? this.structuredData,
    );
  }

  factory AudioNote.fromServerNote(Map<String, dynamic> data) {
    final id = data['note_id'] as String? ?? data['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('Server note missing id');
    }

    var tag = NoteTagsConfig.defaultTags.first;
    final keyData = data['key_data'];
    if (keyData is Map<String, dynamic>) {
      final tagLabel = keyData['tags'] as String?;
      if (tagLabel != null && tagLabel.isNotEmpty) {
        tag = NoteTagsConfig.normalizeTag(tagLabel);
      }
    }

    final createdAtRaw = data['created_at'] as String?;
    final dateTime = createdAtRaw != null && createdAtRaw.isNotEmpty
        ? DateTime.parse(createdAtRaw).toLocal()
        : DateTime.now();

    return AudioNote(
      id: id,
      title: (data['title'] as String?)?.trim().isNotEmpty == true
          ? (data['title'] as String).trim()
          : titleFromDateTime(dateTime),
      dateTime: dateTime,
      audioPath: '',
      transcription: data['formatted_transcription'] as String? ?? '',
      summary: data['summary'] as String? ?? '',
      rawTranscription: data['raw_transcription'] as String? ?? '',
      isNew: true,
      tag: tag,
      analysisStatus: NoteAnalysisStatus.ready,
      structuredData: NoteStructuredData.fromResponse(data),
    );
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
      durationSeconds: map['duration_seconds'] as int? ?? 0,
      isNew: (map['is_new'] as int? ?? 0) == 1,
      tag: NoteTagsConfig.normalizeTag(map['tag'] as String?),
      analysisStatus:
          NoteAnalysisStatus.fromString(map['analysis_status'] as String?),
      structuredData: NoteStructuredData.fromJsonString(
        map['structured_json'] as String?,
      ),
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
      'is_new': isNew ? 1 : 0,
      'tag': tag,
      'analysis_status': analysisStatus.dbValue,
      'structured_json': structuredData.toJsonString(),
    };
  }
}

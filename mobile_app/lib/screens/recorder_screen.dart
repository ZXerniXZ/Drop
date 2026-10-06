import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/api_url_resolver.dart';
import '../models/ai_preferences.dart';
import '../models/app_language.dart';
import '../models/audio_note.dart';
import '../models/note_structured_data.dart';
import '../models/note_tags_config.dart';
import '../models/record_orb_style.dart';
import '../models/transcript_segment.dart';
import '../services/app_identity.dart';
import '../services/app_preferences_service.dart';
import '../services/app_update_service.dart';
import '../models/note_filters.dart';
import '../models/note_folder.dart';
import '../services/chunked_upload_service.dart';
import '../services/drop_api_headers.dart';
import '../services/audio_binary_store.dart';
import '../services/audio_recording_config.dart';
import '../services/cloud_sync_service.dart';
import '../services/legal_acceptance.dart';
import '../services/local_account_service.dart';
import '../services/local_database_service.dart';
import '../services/note_audio_service.dart';
import '../services/note_reanalysis_service.dart';
import '../services/note_share_service.dart';
import '../services/recording_clock.dart';
import '../services/processing_foreground_service.dart';
import '../services/processing_notification.dart';
import '../services/recording_foreground_service.dart';
import '../services/server_quota_service.dart';
import '../services/supabase_auth_service.dart';
import '../theme/drop_motion.dart';
import '../theme/drop_theme.dart';
import '../utils/note_library.dart';
import '../widgets/analysis_language_dialog.dart';
import '../widgets/note_filter_bar.dart';
import '../widgets/note_folder_section.dart';
import '../widgets/drop_bottom_nav.dart';
import '../widgets/drop_logo.dart';
import '../widgets/note_list_card.dart';
import '../widgets/note_swipe_actions.dart';
import '../widgets/staggered_entrance.dart';
import 'note_detail_screen.dart';
import 'update_required_screen.dart';
import 'my_data_screen.dart';
import 'record_orb_preview_screen.dart';
import 'tutorial_screen.dart';

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen>
    with WidgetsBindingObserver {
  final AudioRecorder _recorder = AudioRecorder();
  final TextEditingController _searchController = TextEditingController();

  List<AudioNote> _notes = [];
  List<NoteFolder> _folders = [];
  String? _openFolderId;
  String? _draggingNoteId;
  final Set<String> _deletedNoteIds = {};
  final Set<String> _watchingNoteIds = {};
  NoteFilters _filters = const NoteFilters();
  DropNavTab _activeTab = DropNavTab.file;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isLoadingNotes = true;
  bool _filtersVisible = false;
  List<String> _availableTags = NoteTagsConfig.defaultTags;
  Duration _elapsed = Duration.zero;
  final RecordingClock _clock = RecordingClock();
  final ValueNotifier<double> _amplitudeLevel = ValueNotifier(0);
  RecordOrbStyle _orbStyle = RecordOrbStyle.gradientFluid;
  Timer? _timer;
  bool _isArming = false;
  int _session = 0;
  StreamSubscription<Amplitude>? _amplitudeSub;
  String? _currentPath;
  RecordConfig _recordConfig = AudioRecordingConfig.recordConfig;
  bool _stopping = false;

  NoteFolder? get _openFolder {
    final id = _openFolderId;
    if (id == null) return null;
    for (final folder in _folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  List<AudioNote> get _visibleNotes => visibleLibraryNotes(
        notes: _notes,
        openFolderId: _openFolder?.id,
        filters: _filters,
        knownFolderIds: {for (final folder in _folders) folder.id},
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RecordingForegroundService.addTaskDataCallback(_onForegroundTaskData);
    _loadNotes();
    _loadOrbStyle();
    unawaited(_recorder.hasPermission(request: false));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowTutorial());
    });
  }

  Future<void> _maybeShowTutorial() async {
    if (!mounted || _isRecording || _isPaused) return;
    final pending = await AppPreferencesService.instance.loadPendingShareToken();
    if (!mounted || (pending != null && pending.isNotEmpty)) return;
    final seen = await AppPreferencesService.instance.hasSeenTutorial();
    if (!mounted || seen) return;
    await Navigator.of(context).push(
      DropPageRoute<void>(page: const TutorialScreen()),
    );
  }

  Future<void> _loadOrbStyle() async {
    final style = await AppPreferencesService.instance.loadRecordOrbStyle();
    if (!mounted) return;
    setState(() => _orbStyle = style);
  }

  Future<void> _openOrbPreview() async {
    await Navigator.of(
      context,
    ).push(DropPageRoute<void>(page: const RecordOrbPreviewScreen()));
    await _loadOrbStyle();
  }

  Future<void> _loadTags() async {
    final config = await AppPreferencesService.instance.loadNoteTags();
    if (!mounted) return;
    setState(() => _availableTags = config.tags);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RecordingForegroundService.removeTaskDataCallback(_onForegroundTaskData);
    _timer?.cancel();
    _amplitudeSub?.cancel();
    _amplitudeLevel.dispose();
    _searchController.dispose();
    _recorder.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeProcessingNotes());
      if (_isRecording || _isPaused) {
        _publishElapsed(force: true);
        _pushClockToNotification();
      }
    }
    if (!kIsWeb) return;
    if (!_isRecording && !_isPaused) return;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_stopRecording(interrupted: true));
    }
  }

  void _onForegroundTaskData(Object data) {
    if (data is! Map) return;
    if (data['action'] == 'stop' && (_isRecording || _isPaused)) {
      _stopRecording();
    } else if (data['action'] == 'clock' && (_isRecording || _isPaused)) {
      _pushClockToNotification();
    }
  }

  double _normalizeAmplitude(double db) {
    if (db <= -52) return 0;
    if (db >= -12) return 1;
    return ((db + 52) / 40).clamp(0.0, 1.0);
  }

  Future<void> _loadNotes() async {
    final userId = SupabaseAuthService.instance.currentUser?.id;
    if (userId != null && userId.isNotEmpty) {
      try {
        await LocalAccountService.instance.prepareForUser(userId);
      } catch (error, stack) {
        debugPrint('account locale: $error\n$stack');
      }
    }
    await _loadTags();
    final notes = await LocalDatabaseService.instance.getAllNotes();
    final folders = await LocalDatabaseService.instance.getAllFolders();
    if (!mounted) return;
    setState(() {
      _notes = _withoutDeleted(notes);
      _folders = folders;
      if (_openFolderId != null &&
          !folders.any((folder) => folder.id == _openFolderId)) {
        _openFolderId = null;
      }
      _isLoadingNotes = false;
    });
    unawaited(_syncNotesFromCloud());
    unawaited(_claimPendingShare());
    unawaited(_resumeProcessingNotes());
  }

  Future<void> _claimPendingShare() async {
    final token = await AppPreferencesService.instance.loadPendingShareToken();
    if (token == null || token.isEmpty) return;

    try {
      final claimed = await NoteShareService.instance.claimShare(token);
      await AppPreferencesService.instance.takePendingShareToken();
      if (await LocalDatabaseService.instance.noteExists(claimed.id)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Questa nota e\' gia\' nella tua libreria')),
        );
        return;
      }
      await LocalDatabaseService.instance.saveNote(claimed);
      if (!mounted) return;
      setState(() {
        _notes.insert(0, claimed);
        _activeTab = DropNavTab.file;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nota ricevuta: ${claimed.title}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _syncNotesFromCloud() async {
    final changed = await CloudSyncService.instance.syncNotesFromServer();
    if (!changed || !mounted) return;

    final notes = await LocalDatabaseService.instance.getAllNotes();
    final folders = await LocalDatabaseService.instance.getAllFolders();
    if (!mounted) return;
    setState(() {
      _notes = _withoutDeleted(notes);
      _folders = folders;
      if (_openFolderId != null &&
          !folders.any((folder) => folder.id == _openFolderId)) {
        _openFolderId = null;
      }
    });
  }

  /// Una lettura dal database partita prima di una cancellazione puo'
  /// tornare dopo: senza questo filtro rimetterebbe la nota in lista.
  List<AudioNote> _withoutDeleted(List<AudioNote> notes) {
    if (_deletedNoteIds.isEmpty) return notes;
    return notes.where((n) => !_deletedNoteIds.contains(n.id)).toList();
  }

  void _updateNoteInList(AudioNote note) {
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index == -1) return;
    setState(() => _notes[index] = note);
    if (!note.isProcessing) {
      unawaited(CloudSyncService.instance.pushLibraryOutbox());
    }
  }

  /// Aggiorna la fase mostrata dalla barra di avanzamento della nota.
  /// Parte dalla nota in elenco, non dal placeholder, per non perdere i dati
  /// scritti nel frattempo dalla ripresa dell'upload.
  Future<void> _reportAnalysisProgress(
    String noteId, {
    required NoteAnalysisPhase phase,
    int current = 0,
    int total = 0,
  }) async {
    unawaited(
      ProcessingForegroundService.update(processingNotificationText(phase)),
    );
    final index = _notes.indexWhere((n) => n.id == noteId);
    if (index == -1) return;

    final note = _notes[index];
    if (note.analysisPhase == phase &&
        note.analysisCurrent == current &&
        note.analysisTotal == total) {
      return;
    }

    final updated = note.copyWith(
      analysisPhase: phase,
      analysisCurrent: current,
      analysisTotal: total,
    );
    await LocalDatabaseService.instance.saveNote(updated);
    if (!mounted) return;
    _updateNoteInList(updated);
  }

  void _pushClockToNotification() {
    RecordingForegroundService.syncClock(
      accumulatedMs: _clock.accumulatedMilliseconds,
      segmentStartedAtMs: _clock.segmentStartedAtMilliseconds,
      paused: _clock.isPaused,
    );
  }

  void _publishElapsed({bool force = false}) {
    final next = _clock.elapsed();
    if (!force && next.inSeconds == _elapsed.inSeconds) return;
    _elapsed = next;
    if (!mounted) return;
    setState(() {});
  }

  void _beginElapsedTicker() {
    _timer?.cancel();
    _publishElapsed(force: true);
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !_clock.isRunning) return;
      _publishElapsed();
    });
  }

  void _listenAmplitude() {
    _amplitudeSub?.cancel();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((amp) {
          _amplitudeLevel.value = _normalizeAmplitude(amp.current);
        });
  }

  String _formatNoteDate(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  AudioNote _noteFromResponse(
    Map<String, dynamic> data, {
    required AudioNote placeholder,
    required String audioPath,
  }) {
    final raw =
        data['raw_transcription'] as String? ??
        data['transcription'] as String? ??
        '';
    final formatted = data['formatted_transcription'] as String? ?? raw;
    final summary = data['summary'] as String? ?? '';
    final title = (data['title'] as String?)?.trim();
    final structured = NoteStructuredData.fromResponse(data);
    final tag = structured.tagLabel.isNotEmpty
        ? NoteTagsConfig.normalizeTag(structured.tagLabel, allowed: _availableTags)
        : 'Memo';

    final segments = TranscriptSegment.listFromResponse(
      data['transcript_segments'],
    );
    final serverDuration = (data['audio_duration'] as num?)?.round();

    return placeholder.copyWith(
      title: (title != null && title.isNotEmpty) ? title : placeholder.title,
      audioPath: audioPath,
      transcription: formatted,
      summary: summary,
      rawTranscription: raw,
      analysisStatus: NoteAnalysisStatus.ready,
      structuredData: structured,
      tag: tag,
      transcriptSegments: segments,
      durationSeconds: placeholder.durationSeconds > 0
          ? placeholder.durationSeconds
          : serverDuration,
      sourceLanguage: data['source_language'] as String?,
      outputLanguage: data['output_language'] as String?,
      clearAnalysisProgress: true,
    );
  }

  Future<String?> _persistAudioFile(String tempPath, String noteId) async {
    try {
      return await AudioBinaryStore.instance.persistForNote(tempPath, noteId);
    } catch (_) {
      return tempPath;
    }
  }

  Future<String> _requireAccessToken() async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Sessione scaduta. Effettua di nuovo l\'accesso.');
    }
    return token;
  }

  Future<String> _resolveUploadUrl() async {
    return ApiUrlResolver.resolveEndpoint('/upload-audio');
  }

  Future<String> _resolveJobUrl(String jobId) async {
    return ApiUrlResolver.resolveEndpoint('/jobs/$jobId');
  }

  Future<Map<String, dynamic>?> _pollUploadJob(
    String jobId, {
    required int durationSeconds,
    void Function(NoteAnalysisPhase phase, int current, int total)? onProgress,
  }) async {
    const pollInterval = Duration(seconds: 3);
    const maxGatewayFailures = 20;
    var gatewayFailures = 0;
    final minAttempts = 200;
    final durationBasedAttempts =
        ((durationSeconds * 2) / pollInterval.inSeconds).ceil().clamp(
          minAttempts,
          3600,
        );
    final maxAttempts = durationBasedAttempts;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!mounted) return null;

      final url = await _resolveJobUrl(jobId);
      final accessToken = await _requireAccessToken();
      late final http.Response response;
      try {
        response = await http
            .get(
              Uri.parse(url),
              headers: DropApiHeaders.auth(accessToken),
            )
            .timeout(const Duration(seconds: 20));
      } on TimeoutException {
        await Future<void>.delayed(pollInterval);
        continue;
      } catch (error) {
        gatewayFailures++;
        if (gatewayFailures >= maxGatewayFailures) {
          throw Exception('Connessione interrotta. $error');
        }
        await Future<void>.delayed(pollInterval);
        continue;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Sessione scaduta. Effettua di nuovo l\'accesso.');
      }

      if (response.statusCode == 404) {
        gatewayFailures = 0;
        await Future<void>.delayed(pollInterval);
        continue;
      }

      if (response.statusCode == 502 ||
          response.statusCode == 503 ||
          response.statusCode == 504 ||
          response.statusCode == 500) {
        gatewayFailures++;
        if (gatewayFailures >= maxGatewayFailures) {
          throw Exception(
            'Server temporaneamente non disponibile (${response.statusCode}). '
            'Riprova tra qualche minuto.',
          );
        }
        await Future<void>.delayed(pollInterval);
        continue;
      }

      if (response.statusCode != 200) {
        final detail = response.body.length > 120
            ? '${response.body.substring(0, 120)}...'
            : response.body;
        throw Exception(
          'Polling fallito (${response.statusCode})${detail.isEmpty ? '' : ': $detail'}',
        );
      }

      gatewayFailures = 0;

      final job = jsonDecode(response.body) as Map<String, dynamic>;
      final status = job['status'] as String?;

      if (onProgress != null) {
        final phase = NoteAnalysisPhase.fromString(job['phase'] as String?);
        if (phase != null) {
          final progress = job['progress'];
          final current = progress is Map
              ? (progress['current'] as num?)?.toInt() ?? 0
              : 0;
          final total = progress is Map
              ? (progress['total'] as num?)?.toInt() ?? 0
              : 0;
          onProgress(phase, current, total);
        }
      }

      if (status == 'completed') {
        final result = job['result'];
        if (result is Map<String, dynamic>) return result;
        throw Exception('Risposta job incompleta');
      }

      if (status == 'failed') {
        final error = job['error'] as String? ?? 'Elaborazione fallita';
        throw Exception(error);
      }

      await Future<void>.delayed(pollInterval);
    }

    throw Exception(
      'Timeout elaborazione (oltre ${(maxAttempts * pollInterval.inSeconds) ~/ 60} minuti)',
    );
  }

  Future<CompletedUpload> _uploadAudioDeferred({
    required String filePath,
    required AudioNote placeholder,
    required AiPreferences prefs,
    required List<String> tags,
    required int durationSeconds,
  }) async {
    final accessToken = await _requireAccessToken();
    final fileSize = await AudioBinaryStore.instance.byteLength(filePath);

    await _reportAnalysisProgress(
      placeholder.id,
      phase: NoteAnalysisPhase.uploading,
    );

    if (fileSize <= legacyUploadMaxBytes) {
      final url = await _resolveUploadUrl();
      final request = http.MultipartRequest('POST', Uri.parse(url));
      request.headers.addAll(DropApiHeaders.auth(accessToken));
      final bytes = await AudioBinaryStore.instance.readAll(filePath);
      final filename = AudioBinaryStore.instance.filenameOf(filePath);
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
      request.fields['ai_model'] = prefs.model.openRouterId;
      request.fields['language'] = prefs.transcriptionLanguage.id;
      request.fields['source_language'] = prefs.transcriptionLanguage.id;
      request.fields['output_language'] = prefs.outputLanguage.id;
      request.fields['available_tags'] = jsonEncode(tags);
      request.fields['note_id'] = placeholder.id;
      request.fields['defer_analysis'] = 'true';
      if (prefs.customPrompt.trim().isNotEmpty) {
        request.fields['custom_prompt'] = prefs.customPrompt.trim();
      }
      request.fields['noise_reduction'] =
          prefs.noiseReduction ? 'true' : 'false';
      if (durationSeconds > 0) {
        request.fields['duration_seconds'] = '$durationSeconds';
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        final quotaError = ServerQuotaService.parseError(response);
        if (quotaError != null) throw quotaError;
        var errorDetail = response.body;
        try {
          final errJson = jsonDecode(response.body) as Map<String, dynamic>;
          errorDetail = errJson['detail']?.toString() ?? errorDetail;
        } catch (_) {}
        if (response.statusCode == 401 || response.statusCode == 403) {
          errorDetail = 'Accesso richiesto. Effettua di nuovo l\'accesso.';
        }
        throw Exception(
          'Upload fallito (${response.statusCode}): $errorDetail',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final uploadId = data['upload_id'] as String?;
      if (uploadId == null || uploadId.isEmpty) {
        throw Exception('Risposta server senza upload_id');
      }
      return CompletedUpload(
        uploadId: uploadId,
        savedName: data['saved_name'] as String?,
      );
    }

    return ChunkedUploadService.instance.uploadFile(
      filePath: filePath,
      accessToken: accessToken,
      prefs: prefs,
      availableTags: tags,
      noteId: placeholder.id,
      durationSeconds: durationSeconds,
      deferAnalysis: true,
      existingUploadSessionId: placeholder.uploadSessionId,
      lastUploadedChunkIndex: placeholder.uploadedChunks > 0
          ? placeholder.uploadedChunks - 1
          : null,
      onProgress: (uploadedChunks, totalChunks) {
        unawaited(
          _reportAnalysisProgress(
            placeholder.id,
            phase: NoteAnalysisPhase.uploading,
            current: uploadedChunks,
            total: totalChunks,
          ),
        );
      },
      onSessionProgress: (uploadSessionId, uploadedChunkIndex) async {
        final progressNote = placeholder.copyWith(
          uploadSessionId: uploadSessionId,
          uploadedChunks: uploadedChunkIndex >= 0
              ? uploadedChunkIndex + 1
              : 0,
        );
        await LocalDatabaseService.instance.saveNote(progressNote);
        if (!mounted) return;
        _updateNoteInList(progressNote);
      },
    );
  }

  Future<LanguageChoice?> _askAnalysisLanguages({
    required Future<DetectedLanguages> detection,
    required AiPreferences prefs,
  }) {
    if (!mounted) return Future.value();
    return showAnalysisLanguageDialog(
      context: context,
      detection: detection,
      fallbackSource: prefs.transcriptionLanguage,
      fallbackOutput: prefs.outputLanguage,
    );
  }

  Future<void> _cancelAnalysis(String noteId, String message) async {
    final index = _notes.indexWhere((n) => n.id == noteId);
    if (index == -1) return;
    final cancelled = _notes[index].copyWith(
      analysisStatus: NoteAnalysisStatus.failed,
      transcription: message,
      clearAnalysisProgress: true,
    );
    await LocalDatabaseService.instance.saveNote(cancelled);
    if (!mounted) return;
    _updateNoteInList(cancelled);
  }

  Future<void> _rememberAnalysisJob(String noteId, String jobId) async {
    final index = _notes.indexWhere((note) => note.id == noteId);
    if (index == -1) return;
    final updated = _notes[index].copyWith(analysisJobId: jobId);
    await LocalDatabaseService.instance.saveNote(updated);
    if (!mounted) return;
    _updateNoteInList(updated);
  }

  Future<void> _applyCompletedAnalysis(
    String noteId,
    Map<String, dynamic> result,
  ) async {
    if (await LocalDatabaseService.instance.isNoteDeleted(noteId)) return;
    final index = _notes.indexWhere((note) => note.id == noteId);
    final placeholder = index == -1
        ? await LocalDatabaseService.instance.getNote(noteId)
        : _notes[index];
    if (placeholder == null) return;
    final note = _noteFromResponse(
      result,
      placeholder: placeholder,
      audioPath: placeholder.audioPath,
    ).copyWith(clearUploadSession: true, uploadedChunks: 0, clearAnalysisJob: true);
    await LocalDatabaseService.instance.saveNote(note);
    if (!mounted) return;
    _updateNoteInList(note);
  }

  bool _remoteNoteReady(Map<String, dynamic> data) {
    final summary = (data['summary'] as String?)?.trim() ?? '';
    final raw = (data['raw_transcription'] as String?)?.trim() ?? '';
    final formatted = (data['formatted_transcription'] as String?)?.trim() ?? '';
    return summary.isNotEmpty || raw.isNotEmpty || formatted.isNotEmpty;
  }

  /// [reachable] is false when the request failed, so a missing note is not
  /// confused with a network error.
  Future<({bool reachable, Map<String, dynamic>? note})> _fetchServerNote(
    String noteId,
  ) async {
    try {
      final accessToken = await _requireAccessToken();
      final url = await ApiUrlResolver.resolveEndpoint('/notes/$noteId');
      final response = await http
          .get(Uri.parse(url), headers: DropApiHeaders.auth(accessToken))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 404) return (reachable: true, note: null);
      if (response.statusCode != 200) return (reachable: false, note: null);
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return (reachable: false, note: null);
      }
      return (reachable: true, note: decoded);
    } catch (_) {
      return (reachable: false, note: null);
    }
  }

  /// Null when the server does not list active jobs yet.
  Future<List<Map<String, dynamic>>?> _fetchActiveJobs() async {
    try {
      final accessToken = await _requireAccessToken();
      final url = await ApiUrlResolver.resolveEndpoint('/jobs/active');
      final response = await http
          .get(Uri.parse(url), headers: DropApiHeaders.auth(accessToken))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return null;
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return null;
    }
  }

  String? _matchActiveJob(
    AudioNote note,
    List<Map<String, dynamic>> jobs,
    int processingCount,
  ) {
    for (final job in jobs) {
      if (job['note_id'] == note.id) return job['job_id'] as String?;
    }
    final unbound = jobs.where((job) {
      final id = job['note_id'] as String?;
      return id == null || id.isEmpty;
    }).toList();
    if (processingCount == 1 && unbound.length == 1) {
      return unbound.first['job_id'] as String?;
    }
    return null;
  }

  Future<void> _resumeProcessingNotes() async {
    final pending = _notes.where((note) => note.isProcessing).toList();
    for (final note in pending) {
      unawaited(_reattachNote(note, processingCount: pending.length));
    }
  }

  Future<void> _reattachNote(
    AudioNote note, {
    required int processingCount,
  }) async {
    if (!_watchingNoteIds.add(note.id)) return;
    var handedOff = false;
    await ProcessingForegroundService.acquire(
      processingNotificationText(note.analysisPhase),
    );
    try {
      var jobId = note.analysisJobId;
      if (jobId == null || jobId.isEmpty) {
        final active = await _fetchActiveJobs();
        if (active != null) {
          jobId = _matchActiveJob(note, active, processingCount);
        }
      }
      if (jobId != null && jobId.isNotEmpty) {
        await _rememberAnalysisJob(note.id, jobId);
        final result = await _pollUploadJob(
          jobId,
          durationSeconds: note.durationSeconds,
          onProgress: (phase, current, total) {
            unawaited(
              _reportAnalysisProgress(
                note.id,
                phase: phase,
                current: current,
                total: total,
              ),
            );
          },
        );
        if (result != null) {
          await _applyCompletedAnalysis(note.id, result);
        }
        return;
      }

      final remote = await _fetchServerNote(note.id);
      if (remote.note != null && _remoteNoteReady(remote.note!)) {
        await _applyCompletedAnalysis(note.id, remote.note!);
        return;
      }
      if (!remote.reachable || remote.note != null) return;

      final active = await _fetchActiveJobs();
      final audioReady =
          note.audioPath.isNotEmpty &&
          await AudioBinaryStore.instance.exists(note.audioPath);
      if (active != null && active.isEmpty && audioReady) {
        _watchingNoteIds.remove(note.id);
        handedOff = true;
        await _processUpload(
          noteId: note.id,
          filePath: note.audioPath,
          durationSeconds: note.durationSeconds,
        );
      }
    } catch (e) {
      final index = _notes.indexWhere((item) => item.id == note.id);
      if (index == -1) return;
      final failed = _notes[index].copyWith(
        analysisStatus: NoteAnalysisStatus.failed,
        transcription: 'Errore: $e',
        clearAnalysisJob: true,
        clearAnalysisProgress: true,
      );
      await LocalDatabaseService.instance.saveNote(failed);
      if (!mounted) return;
      _updateNoteInList(failed);
    } finally {
      await ProcessingForegroundService.release();
      if (!handedOff) _watchingNoteIds.remove(note.id);
    }
  }

  Future<void> _processUpload({
    required String noteId,
    required String filePath,
    required int durationSeconds,
  }) async {
    if (!_watchingNoteIds.add(noteId)) return;
    await ProcessingForegroundService.acquire(
      processingNotificationText(NoteAnalysisPhase.uploading),
    );
    try {
      final prefs = await AppPreferencesService.instance.loadAiPreferences();
      final tagsConfig = await AppPreferencesService.instance.loadNoteTags();
      final apiKey = await AppPreferencesService.instance
          .loadOpenRouterApiKey();

      final index = _notes.indexWhere((n) => n.id == noteId);
      if (index == -1) return;
      var placeholder = _notes[index];

      final uploaded = await _uploadAudioDeferred(
        filePath: filePath,
        placeholder: placeholder,
        prefs: prefs,
        tags: tagsConfig.tags,
        durationSeconds: durationSeconds,
      );

      final choice = await _askAnalysisLanguages(
        detection: LanguageDetectService.instance.detectFromUpload(
          uploaded.uploadId,
          fallbackOutput: prefs.outputLanguage,
          noiseReduction: prefs.noiseReduction,
        ),
        prefs: prefs,
      );
      if (choice == null) {
        await _cancelAnalysis(noteId, 'Analisi annullata');
        return;
      }

      await AppPreferencesService.instance.saveAiPreferences(
        prefs.copyWith(
          transcriptionLanguage: choice.sourceLanguage,
          outputLanguage: choice.outputLanguage,
        ),
      );
      final analysisPrefs = prefs.copyWith(
        transcriptionLanguage: choice.sourceLanguage,
        outputLanguage: choice.outputLanguage,
      );

      Map<String, dynamic>? result;

      final accessToken = await _requireAccessToken();
      if (apiKey == null || apiKey.isEmpty) {
        final quota = await ServerQuotaService.instance.fetch();
        if (quota != null &&
            (quota.isExhausted || quota.wouldExceed(durationSeconds))) {
          throw ServerQuotaExceeded(
            message: ServerQuotaService.defaultMessage,
            usedSeconds: quota.usedSeconds,
            limitSeconds: quota.limitSeconds,
            remainingSeconds: quota.remainingSeconds,
          );
        }
      }
      final jobId = await ChunkedUploadService.instance.startAnalyze(
        uploadId: uploaded.uploadId,
        accessToken: accessToken,
        prefs: analysisPrefs,
        availableTags: tagsConfig.tags,
        sourceLanguage: choice.sourceLanguage.id,
        outputLanguage: choice.outputLanguage.id,
        noteId: placeholder.id,
        durationSeconds: durationSeconds,
        openRouterApiKey: apiKey,
      );
      await _rememberAnalysisJob(placeholder.id, jobId);
      result = await _pollUploadJob(
        jobId,
        durationSeconds: durationSeconds,
        onProgress: (phase, current, total) {
          unawaited(
            _reportAnalysisProgress(
              placeholder.id,
              phase: phase,
              current: current,
              total: total,
            ),
          );
        },
      );

      if (result == null) return;
      if (await LocalDatabaseService.instance.isNoteDeleted(noteId)) return;

      final persistedPath =
          await _persistAudioFile(filePath, noteId) ?? filePath;
      final refreshedIndex = _notes.indexWhere((n) => n.id == noteId);
      placeholder = refreshedIndex == -1 ? placeholder : _notes[refreshedIndex];
      final note = _noteFromResponse(
        result,
        placeholder: placeholder,
        audioPath: persistedPath,
      ).copyWith(
        clearUploadSession: true,
        uploadedChunks: 0,
        clearAnalysisJob: true,
        sourceLanguage: choice.sourceLanguage.id,
        outputLanguage: choice.outputLanguage.id,
      );

      if (apiKey != null && apiKey.isNotEmpty) {
        await NoteShareService.instance.publishNote(
          note,
          uploadId: uploaded.uploadId,
          prefs: analysisPrefs,
        );
      }

      await LocalDatabaseService.instance.saveNote(note);
      if (!mounted) return;
      _updateNoteInList(note);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trascrizione completata'),
          backgroundColor: Colors.green,
        ),
      );
    } on ServerQuotaExceeded catch (e) {
      if (!mounted) return;
      final index = _notes.indexWhere((n) => n.id == noteId);
      if (index != -1) {
        final failed = _notes[index].copyWith(
          analysisStatus: NoteAnalysisStatus.failed,
          transcription: e.message,
          clearAnalysisJob: true,
          clearAnalysisProgress: true,
        );
        await LocalDatabaseService.instance.saveNote(failed);
        if (!mounted) return;
        _updateNoteInList(failed);
      }
      await _showServerQuotaDialog(e);
    } catch (e) {
      if (!mounted) return;
      final index = _notes.indexWhere((n) => n.id == noteId);
      if (index == -1) return;
      final failed = _notes[index].copyWith(
        analysisStatus: NoteAnalysisStatus.failed,
        transcription: 'Errore: $e',
        clearAnalysisJob: true,
        clearAnalysisProgress: true,
      );
      await LocalDatabaseService.instance.saveNote(failed);
      if (!mounted) return;
      _updateNoteInList(failed);
    } finally {
      await ProcessingForegroundService.release();
      _watchingNoteIds.remove(noteId);
    }
  }

  Future<void> _showServerQuotaDialog(ServerQuotaExceeded error) async {
    if (!mounted) return;
    final openAccount = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Piano incluso esaurito'),
        content: Text(error.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Chiudi'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apri Account'),
          ),
        ],
      ),
    );
    if (openAccount == true && mounted) {
      setState(() => _activeTab = DropNavTab.settings);
    }
  }

  Future<bool> _confirmDeleteNote(AudioNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina nota'),
        content: Text('Vuoi eliminare "${note.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Elimina',
              style: TextStyle(color: DropColors.recordRed),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _shareListedNote(AudioNote note) async {
    final navigator = Navigator.of(context);
    final loader = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
    navigator.push(loader);
    try {
      final prefs = await AppPreferencesService.instance.loadAiPreferences();
      final url = await NoteShareService.instance.createShareUrl(
        note,
        prefs: prefs,
      );
      if (loader.isActive) navigator.removeRoute(loader);
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Condividi nota'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Chi apre il link accede a Drop e riceve una copia della nota nella propria libreria.',
              ),
              const SizedBox(height: 12),
              SelectableText(
                url,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await NoteShareService.instance.revokeShare(note.id);
                if (context.mounted) Navigator.pop(context, 'revoked');
              },
              child: const Text(
                'Revoca',
                style: TextStyle(color: DropColors.recordRed),
              ),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (context.mounted) Navigator.pop(context, 'copied');
              },
              child: const Text('Copia link'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (action == 'copied') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copiato')),
        );
      } else if (action == 'revoked') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link revocato')),
        );
      }
    } catch (e) {
      if (loader.isActive) navigator.removeRoute(loader);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _deleteNote(AudioNote note) async {
    if (!_deletedNoteIds.add(note.id)) return;
    if (mounted) {
      setState(() => _notes.removeWhere((n) => n.id == note.id));
    }
    await LocalDatabaseService.instance.markNoteDeleted(note.id);
    await LocalDatabaseService.instance.deleteNote(note.id);
    unawaited(CloudSyncService.instance.deleteNoteOnServer(note.id));
    try {
      // Anche l'audio riscaricato dal server, che non passa per audio_path.
      final path = await NoteAudioService.instance.localPathIfExists(
        note.id,
        currentPath: note.audioPath,
      );
      if (path != null) await AudioBinaryStore.instance.delete(path);
    } catch (_) {}
  }

  Future<bool> _ensureMicrophonePermission() async {
    if (await _recorder.hasPermission(request: false)) return true;
    // All'avvio il plugin può non avere ancora l'activity e rispondere false.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return false;
    if (await _recorder.hasPermission(request: false)) return true;
    return _recorder.hasPermission();
  }

  Future<void> _togglePauseResume() async {
    if (_isArming || _stopping) return;

    if (_isPaused) {
      await _recorder.resume();
      if (!mounted) return;
      _clock.resume();
      _listenAmplitude();
      setState(() {
        _isPaused = false;
        _isRecording = true;
        _elapsed = _clock.elapsed();
      });
      _beginElapsedTicker();
      _pushClockToNotification();
      return;
    }

    if (!_isRecording) return;

    _clock.pause();
    _timer?.cancel();
    _timer = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _amplitudeLevel.value = 0;
    if (!mounted) return;
    setState(() {
      _isPaused = true;
      _isRecording = false;
      _elapsed = _clock.elapsed();
    });
    _pushClockToNotification();

    try {
      await _recorder.pause();
    } catch (_) {
      if (!mounted || !_isPaused) return;
      _clock.resume();
      _listenAmplitude();
      setState(() {
        _isPaused = false;
        _isRecording = true;
        _elapsed = _clock.elapsed();
      });
      _beginElapsedTicker();
      _pushClockToNotification();
    }
  }

  Future<bool> _confirmRecordingNotice() async {
    if (LegalAcceptance.hasAcknowledgedRecordingNotice) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Prima di registrare'),
        content: const Text(
          'Registri solo conversazioni e ambienti per cui hai titolo. '
          'Se nell’audio ci sono altre persone, le informi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ho capito'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    try {
      await LegalAcceptance.saveRecordingNotice();
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conferma non salvata. Riprova.'),
          backgroundColor: DropColors.recordRed,
        ),
      );
      return false;
    }
  }

  Future<void> _startRecording() async {
    if (_isArming || _stopping || _isRecording || _isPaused) return;
    _isArming = true;
    final session = ++_session;
    if (mounted) setState(() {});

    try {
      final noticed = await _confirmRecordingNotice();
      if (!noticed || !mounted || session != _session) return;

      final policy = AppUpdateService.instance.lastPolicy;
      if (policy != null &&
          AppIdentity.isBelow(policy.minVersion, policy.minBuild)) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => UpdateRequiredScreen(policy: policy),
          ),
        );
        return;
      }

      final hasPermission = await _ensureMicrophonePermission();
      if (session != _session) return;
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permesso microfono negato')),
        );
        return;
      }

      _recordConfig = await AudioRecordingConfig.resolve(_recorder);
      final path = await AudioBinaryStore.instance.createRecordingDestination(
        extension: AudioRecordingConfig.extensionFor(_recordConfig),
      );
      if (session != _session || !mounted) return;

      try {
        Object? startError;
        for (var attempt = 0; attempt < 2; attempt++) {
          try {
            await _recorder.start(_recordConfig, path: path);
            startError = null;
            break;
          } catch (error) {
            startError = error;
            if (attempt == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 250));
              if (session != _session || !mounted) return;
            }
          }
        }
        if (startError != null) {
          throw startError;
        }
        await WakelockPlus.enable();
      } catch (e) {
        await WakelockPlus.disable();
        if (!mounted || session != _session) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossibile avviare la registrazione: $e')),
        );
        return;
      }

      if (session != _session || !mounted) {
        await _recorder.stop();
        await WakelockPlus.disable();
        return;
      }

      _clock.start();
      _amplitudeLevel.value = 0;
      _listenAmplitude();
      setState(() {
        _isArming = false;
        _isRecording = true;
        _isPaused = false;
        _elapsed = Duration.zero;
        _currentPath = path;
      });
      _beginElapsedTicker();

      await RecordingForegroundService.start(
        elapsedLabel: formatRecordingElapsed(Duration.zero),
      );
      if (session != _session || (!_isRecording && !_isPaused)) {
        await RecordingForegroundService.stop();
        return;
      }
      _pushClockToNotification();
    } finally {
      if (session == _session && _isArming) {
        _isArming = false;
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _stopRecording({bool interrupted = false}) async {
    if (_stopping) return;
    if (!_isRecording && !_isPaused) return;
    _stopping = true;
    _isArming = false;
    _session++;

    _timer?.cancel();
    _timer = null;
    final recordedDuration = _clock.elapsed();
    _clock.reset();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _amplitudeLevel.value = 0;

    try {
      if (_isPaused) {
        await _recorder.resume();
      }
      final path = await _recorder.stop();
      await RecordingForegroundService.stop();
      await WakelockPlus.disable();

      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isPaused = false;
        _elapsed = Duration.zero;
      });

      final recorderPath = path ?? _currentPath;
      _currentPath = null;
      if (recorderPath == null || !mounted) return;

      final savedPath = await AudioBinaryStore.instance.adoptRecorderOutput(
        recorderPath,
        suggestedExtension: AudioRecordingConfig.extensionFor(_recordConfig),
      );

      final createdAt = DateTime.now();
      final noteId = createdAt.millisecondsSinceEpoch.toString();
      final placeholder = AudioNote(
        id: noteId,
        title: AudioNote.titleFromDateTime(createdAt),
        dateTime: createdAt,
        audioPath: savedPath,
        transcription: '',
        summary: '',
        durationSeconds: recordedDuration.inSeconds,
        isNew: true,
        tag: 'Memo',
        analysisStatus: NoteAnalysisStatus.processing,
        analysisPhase: NoteAnalysisPhase.uploading,
        folderId: _activeTab == DropNavTab.file ? _openFolder?.id : null,
      );

      await LocalDatabaseService.instance.saveNote(placeholder);
      final filedFolderId = placeholder.folderId;
      if (filedFolderId != null) {
        unawaited(
          CloudSyncService.instance.queueNotePlacement(
            placeholder.id,
            filedFolderId,
          ),
        );
      }
      if (!mounted) return;

      setState(() {
        _notes.insert(0, placeholder);
        _activeTab = DropNavTab.file;
      });

      if (interrupted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Registrazione interrotta: Drop deve restare aperto e a schermo acceso.',
            ),
          ),
        );
      }

      unawaited(
        _processUpload(
          noteId: noteId,
          filePath: savedPath,
          durationSeconds: recordedDuration.inSeconds,
        ),
      );
    } finally {
      _stopping = false;
    }
  }

  Future<void> _cancelRecording() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annulla registrazione'),
        content: const Text('Vuoi scartare questa registrazione?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continua'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Annulla',
              style: TextStyle(color: DropColors.recordRed),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    if (_stopping) return;
    _stopping = true;
    _isArming = false;
    _session++;

    _timer?.cancel();
    _timer = null;
    _clock.reset();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _amplitudeLevel.value = 0;

    try {
      if (_isPaused) {
        await _recorder.resume();
      }

      final path = await _recorder.stop();
      await RecordingForegroundService.stop();
      await WakelockPlus.disable();

      final toDelete = path ?? _currentPath;
      if (toDelete != null) {
        try {
          final handle =
              toDelete.startsWith('blob:') || toDelete.startsWith('mem:')
              ? await AudioBinaryStore.instance.adoptRecorderOutput(toDelete)
              : toDelete;
          await AudioBinaryStore.instance.delete(handle);
        } catch (_) {}
      }

      _currentPath = null;
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isPaused = false;
        _elapsed = Duration.zero;
      });
    } finally {
      _stopping = false;
    }
  }

  Future<void> _retryAnalysis(AudioNote note) async {
    if (note.isProcessing) return;

    final path = note.audioPath;
    if (path.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File audio non disponibile')),
      );
      return;
    }

    if (!await AudioBinaryStore.instance.exists(path)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File audio non trovato sul dispositivo')),
      );
      return;
    }

    final retrying = note.copyWith(
      analysisStatus: NoteAnalysisStatus.processing,
      transcription: '',
      summary: '',
      rawTranscription: '',
      structuredData: const NoteStructuredData(),
    );
    await LocalDatabaseService.instance.saveNote(retrying);
    if (!mounted) return;
    _updateNoteInList(retrying);

    unawaited(
      _processUpload(
        noteId: note.id,
        filePath: path,
        durationSeconds: note.durationSeconds,
      ),
    );
  }

  /// Ri-trascrive e rianalizza una nota gia' completata usando l'audio che il
  /// backend conserva. In caso di errore la nota precedente viene ripristinata:
  /// il contenuto vecchio resta valido finche' il nuovo non arriva.
  Future<void> _reanalyzeNote(AudioNote note) async {
    if (note.isProcessing) return;

    final prefs = await AppPreferencesService.instance.loadAiPreferences();
    final tagsConfig = await AppPreferencesService.instance.loadNoteTags();
    final choice = await _askAnalysisLanguages(
      detection: LanguageDetectService.instance.detectFromNote(
        note.id,
        fallbackOutput: AppLanguage.outputFromKey(
          note.outputLanguage ?? prefs.outputLanguage.id,
        ),
        noiseReduction: prefs.noiseReduction,
      ),
      prefs: prefs.copyWith(
        transcriptionLanguage: AppLanguage.fromKey(
          note.sourceLanguage ?? prefs.transcriptionLanguage.id,
        ),
        outputLanguage: AppLanguage.outputFromKey(
          note.outputLanguage ?? prefs.outputLanguage.id,
        ),
      ),
    );
    if (choice == null) return;

    await AppPreferencesService.instance.saveAiPreferences(
      prefs.copyWith(
        transcriptionLanguage: choice.sourceLanguage,
        outputLanguage: choice.outputLanguage,
      ),
    );
    final analysisPrefs = prefs.copyWith(
      transcriptionLanguage: choice.sourceLanguage,
      outputLanguage: choice.outputLanguage,
    );

    final processing = note.copyWith(
      analysisStatus: NoteAnalysisStatus.processing,
      analysisPhase: NoteAnalysisPhase.transcribing,
      analysisCurrent: 0,
      analysisTotal: 0,
    );
    await LocalDatabaseService.instance.saveNote(processing);
    if (!mounted) return;
    _updateNoteInList(processing);

    await ProcessingForegroundService.acquire(
      processingNotificationText(NoteAnalysisPhase.transcribing),
    );
    try {
      final apiKey = await AppPreferencesService.instance.loadOpenRouterApiKey();
      final jobId = await NoteReanalysisService.instance.requestReanalysis(
        noteId: note.id,
        prefs: analysisPrefs,
        availableTags: tagsConfig.tags,
        sourceLanguage: choice.sourceLanguage.id,
        outputLanguage: choice.outputLanguage.id,
        openRouterApiKey: apiKey,
      );
      await _rememberAnalysisJob(note.id, jobId);

      final result = await _pollUploadJob(
        jobId,
        durationSeconds: note.durationSeconds,
        onProgress: (phase, current, total) {
          unawaited(
            _reportAnalysisProgress(
              note.id,
              phase: phase,
              current: current,
              total: total,
            ),
          );
        },
      );
      if (result == null) return;

      final updated = _noteFromResponse(
        result,
        placeholder: processing,
        audioPath: note.audioPath,
      ).copyWith(
        clearAnalysisJob: true,
        sourceLanguage: choice.sourceLanguage.id,
        outputLanguage: choice.outputLanguage.id,
      );
      await LocalDatabaseService.instance.saveNote(updated);
      if (!mounted) return;
      _updateNoteInList(updated);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Analisi rifatta'),
          backgroundColor: Colors.green,
        ),
      );
    } on ServerQuotaExceeded catch (e) {
      final restored = note.copyWith(
        analysisStatus: NoteAnalysisStatus.ready,
        clearAnalysisProgress: true,
      );
      await LocalDatabaseService.instance.saveNote(restored);
      if (!mounted) return;
      _updateNoteInList(restored);
      await _showServerQuotaDialog(e);
    } catch (e) {
      final restored = note.copyWith(
        analysisStatus: NoteAnalysisStatus.ready,
        clearAnalysisProgress: true,
      );
      await LocalDatabaseService.instance.saveNote(restored);
      if (!mounted) return;
      _updateNoteInList(restored);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Rianalisi fallita: $e')));
    } finally {
      await ProcessingForegroundService.release();
    }
  }

  Future<void> _openNoteDetail(AudioNote note) async {
    if (note.isProcessing) return;

    if (note.isNew) {
      final opened = note.copyWith(isNew: false);
      await LocalDatabaseService.instance.markNoteOpened(note.id);
      await LocalDatabaseService.instance.saveNote(opened);
      _updateNoteInList(opened);
      note = opened;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      DropPageRoute<void>(
        page: NoteDetailScreen(
          note: note,
          onDelete: () => _deleteNote(note),
          onRetry: note.isFailed ? () => _retryAnalysis(note) : null,
          onReanalyze: note.isFailed ? null : () => _reanalyzeNote(note),
          onChanged: (updated) {
            if (!mounted) return;
            _updateNoteInList(updated);
          },
        ),
      ),
    );
  }

  NoteFolder? _folderById(String? id) {
    final wanted = normalizeFolderId(id);
    if (wanted == null) return null;
    for (final folder in _folders) {
      if (folder.id == wanted) return folder;
    }
    return null;
  }

  Future<void> _createFolder() async {
    final parent = _openFolder;
    final name = await showCreateFolderDialog(
      context,
      insideName: parent?.name,
    );
    if (name == null || !mounted) return;
    final folder = NoteFolder(
      id: 'folder_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      createdAt: DateTime.now(),
      parentId: parent?.id,
    );
    await LocalDatabaseService.instance.saveFolder(folder);
    unawaited(CloudSyncService.instance.queueFolderUpsert(folder));
    if (!mounted) return;
    setState(() => _folders.add(folder));
  }

  Future<void> _confirmDeleteFolder(NoteFolder folder) async {
    final ids = folderSubtreeIds(_folders, folder.id);
    final parent = _folderById(folder.parentId);
    final nested = ids.length > 1;
    final hasNotes = _notes.any(
      (note) => note.folderId != null && ids.contains(note.folderId),
    );
    final detail = _deleteFolderDetail(
      name: folder.name,
      parentName: parent?.name,
      nested: nested,
      hasNotes: hasNotes,
    );
    final confirmed = await confirmDeleteFolder(context, detail: detail);
    if (!confirmed || !mounted) return;
    final destination = normalizeFolderId(folder.parentId);
    final movedNoteIds = [
      for (final note in _notes)
        if (note.folderId != null && ids.contains(note.folderId)) note.id,
    ];
    await LocalDatabaseService.instance.deleteFolders(
      ids: ids,
      moveNotesTo: destination,
    );
    unawaited(
      CloudSyncService.instance.queueFolderDelete(
        folders: List<NoteFolder>.of(_folders),
        rootId: folder.id,
        destinationId: destination,
        movedNoteIds: movedNoteIds,
      ),
    );
    if (!mounted) return;
    setState(() {
      _folders.removeWhere((item) => ids.contains(item.id));
      _notes = [
        for (final note in _notes)
          if (note.folderId != null && ids.contains(note.folderId))
            destination == null
                ? note.copyWith(clearFolder: true)
                : note.copyWith(folderId: destination)
          else
            note,
      ];
      if (_openFolderId != null && ids.contains(_openFolderId)) {
        _openFolderId = destination;
      }
    });
  }

  String _deleteFolderDetail({
    required String name,
    required String? parentName,
    required bool nested,
    required bool hasNotes,
  }) {
    if (!nested && !hasNotes) {
      return 'Vuoi eliminare "$name"?';
    }
    final place = parentName == null ? 'nella home' : 'in "$parentName"';
    if (nested) {
      return 'Le note in "$name" e nelle cartelle al suo interno tornano $place.';
    }
    return 'Le note in "$name" tornano $place.';
  }

  Future<void> _moveNoteToFolder(String noteId, String? folderId) async {
    final index = _notes.indexWhere((note) => note.id == noteId);
    if (index == -1) return;
    final note = _notes[index];
    if ((note.folderId ?? '') == (folderId ?? '')) return;

    final updated = folderId == null
        ? note.copyWith(clearFolder: true)
        : note.copyWith(folderId: folderId);
    try {
      await LocalDatabaseService.instance.saveNote(updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Spostamento non riuscito: $error')),
      );
      return;
    }
    if (!mounted) return;
    unawaited(
      CloudSyncService.instance.queueNotePlacement(noteId, folderId),
    );
    HapticFeedback.selectionClick();
    String? folderName;
    if (folderId != null) {
      for (final folder in _folders) {
        if (folder.id == folderId) folderName = folder.name;
      }
    }
    setState(() => _notes[index] = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          folderName == null
              ? 'Nota spostata fuori dalla cartella'
              : 'Nota spostata in $folderName',
        ),
      ),
    );
  }

  void _onNoteDragStarted(String noteId) {
    if (_draggingNoteId == noteId) return;
    setState(() => _draggingNoteId = noteId);
  }

  void _onNoteDragEnded() {
    if (_draggingNoteId == null) return;
    setState(() => _draggingNoteId = null);
  }

  String? _folderLabelFor(AudioNote note) {
    if (_openFolder != null || !_filters.hasActiveFilters) return null;
    final id = note.folderId;
    if (id == null || id.isEmpty) return null;
    for (final folder in _folders) {
      if (folder.id == id) return folder.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            if (_activeTab == DropNavTab.file) _buildFiltersSection(context),
            Expanded(
              child: AnimatedSwitcher(
                duration: DropMotion.medium,
                switchInCurve: DropMotion.enter,
                switchOutCurve: DropMotion.exit,
                transitionBuilder: (child, animation) =>
                    DropSwitcherTransition(animation: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(_activeTab),
                  child: _buildBody(context),
                ),
              ),
            ),
            if (kIsWeb && (_isRecording || _isPaused))
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  'Su questo dispositivo la registrazione continua solo con Drop aperto e lo schermo acceso.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: DropColors.muted(context),
                    height: 1.35,
                  ),
                ),
              ),
            DropBottomNav(
              activeTab: _activeTab,
              onTabChanged: (tab) {
                setState(() => _activeTab = tab);
                if (tab == DropNavTab.file) {
                  _loadTags();
                  _loadOrbStyle();
                }
              },
              onStartRecording: _startRecording,
              onPauseResume: _togglePauseResume,
              onFinishRecording: () => _stopRecording(),
              onCancelRecording: _cancelRecording,
              isRecording: _isRecording,
              isPaused: _isPaused,
              isArming: _isArming,
              elapsedLabel: (_isRecording || _isPaused)
                  ? formatRecordingElapsed(_elapsed)
                  : null,
              amplitudeLevel: _amplitudeLevel,
              orbStyle: _orbStyle,
              onOrbPreview: _openOrbPreview,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final folder = _activeTab == DropNavTab.file ? _openFolder : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(folder == null ? 24 : 4, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: DropMotion.medium,
              switchInCurve: DropMotion.enter,
              switchOutCurve: DropMotion.exit,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    ...previousChildren,
                    ?currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.15),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: folder != null
                  ? Row(
                      key: ValueKey('folder-header-${folder.id}'),
                      children: [
                        IconButton(
                          key: const Key('close-folder'),
                          tooltip: normalizeFolderId(folder.parentId) == null
                              ? 'Torna alla home'
                              : 'Indietro',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(
                            () => _openFolderId = normalizeFolderId(
                              folder.parentId,
                            ),
                          ),
                          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                        ),
                        Expanded(
                          child: Text(
                            folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3,
                                ),
                          ),
                        ),
                        IconButton(
                          key: const Key('delete-open-folder'),
                          tooltip: 'Elimina cartella',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _confirmDeleteFolder(folder),
                          icon: Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: DropColors.muted(context),
                          ),
                        ),
                      ],
                    )
                  : _activeTab == DropNavTab.file
                      ? Row(
                          key: const ValueKey('file-header'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const DropLogo(height: 26),
                            const SizedBox(width: 10),
                            Text(
                              'Drop',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.3,
                                  ),
                            ),
                          ],
                        )
                      : Text(
                          'Impostazioni',
                          key: const ValueKey('settings-header'),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                              ),
                        ),
            ),
          ),
          if (_activeTab == DropNavTab.file) ...[
            const SizedBox(width: 8),
            Text(
              '${_visibleNotes.length} note',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
                color: DropColors.muted(context),
              ),
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            onPressed: widget.onToggleTheme,
            style: IconButton.styleFrom(
              side: BorderSide(color: DropColors.border(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(
              widget.isDarkMode
                  ? Icons.wb_sunny_outlined
                  : Icons.dark_mode_outlined,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersSection(BuildContext context) {
    return FileSearchFilters(
      searchController: _searchController,
      filters: _filters,
      availableTags: _availableTags,
      filtersVisible: _filtersVisible,
      onSearchChanged: (q) =>
          setState(() => _filters = _filters.copyWith(searchQuery: q)),
      onToggleFilters: () => setState(() => _filtersVisible = !_filtersVisible),
      onTagChanged: (tag) => setState(
        () => _filters = _filters.copyWith(
          tagFilter: tag,
          clearTagFilter: tag == null,
        ),
      ),
      onDurationChanged: (d) =>
          setState(() => _filters = _filters.copyWith(durationFilter: d)),
      onStatusChanged: (s) =>
          setState(() => _filters = _filters.copyWith(statusFilter: s)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_activeTab == DropNavTab.settings) {
      return const MyDataScreen();
    }

    if (_isLoadingNotes) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final inFolder = _openFolder != null;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: DropMotion.medium,
            switchInCurve: DropMotion.enter,
            switchOutCurve: DropMotion.exit,
            child: KeyedSubtree(
              key: ValueKey(_openFolder?.id ?? 'root'),
              child: _buildLibrary(context),
            ),
          ),
          if (inFolder)
            Positioned(
              left: 20,
              right: 20,
              bottom: 12,
              child: MoveOutFolderTarget(
                visible: _draggingNoteId != null,
                parentName: _folderById(_openFolder?.parentId)?.name,
                onAccept: (noteId) => _moveNoteToFolder(
                  noteId,
                  normalizeFolderId(_openFolder?.parentId),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLibrary(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NoteFolderBar(
          folders: foldersIn(_folders, _openFolder?.id),
          noteCount: (id) => notesInFolderCount(_notes, id),
          dragging: _draggingNoteId != null,
          onCreate: _createFolder,
          onOpen: (folder) => setState(() => _openFolderId = folder.id),
          onDelete: _confirmDeleteFolder,
          onDropNote: (noteId, folderId) =>
              _moveNoteToFolder(noteId, folderId),
        ),
        Expanded(child: _buildNoteList(context)),
      ],
    );
  }

  Widget _buildNoteList(BuildContext context) {
    final notes = _visibleNotes;
    final inFolder = _openFolder != null;

    if (_notes.isEmpty) {
      return _buildEmptyState(
        context,
        title: 'Nessuna nota',
        subtitle:
            'Tocca il pulsante rosso in basso per registrare il tuo primo audio.',
      );
    }

    if (notes.isEmpty && _filters.hasActiveFilters) {
      return _buildEmptyState(
        context,
        title: 'Nessun risultato',
        subtitle: 'Prova a modificare i filtri o la ricerca.',
      );
    }

    if (notes.isEmpty && inFolder) {
      final hasChildren = foldersIn(_folders, _openFolder?.id).isNotEmpty;
      return _buildEmptyState(
        context,
        title: 'Nessuna nota',
        subtitle: hasChildren
            ? 'Le note di questa cartella compariranno qui.'
            : 'Trascina qui una nota, oppure crea una cartella dentro.',
      );
    }

    if (notes.isEmpty) {
      return _buildEmptyState(
        context,
        title: 'Tutte nelle cartelle',
        subtitle: 'Apri una cartella per vedere le note.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      itemCount: notes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final note = notes[index];
        return StaggeredEntrance(
          // Lo stato di swipe e chiusura appartiene alla nota, non alla
          // posizione: senza chiave passerebbe alla card successiva.
          key: ValueKey(note.id),
          index: index,
          child: DraggableLibraryNote(
            noteId: note.id,
            title: note.title,
            onDragStarted: () => _onNoteDragStarted(note.id),
            onDragEnded: _onNoteDragEnded,
            child: NoteSwipeActions(
              enabled: !note.isProcessing,
              onShare: () => _shareListedNote(note),
              onDelete: () => _deleteNote(note),
              confirmDelete: () => _confirmDeleteNote(note),
              child: NoteListCard(
                note: note,
                dateLabel: _formatNoteDate(note.dateTime),
                onTap: note.isProcessing ? null : () => _openNoteDetail(note),
                onDelete: () => _deleteNote(note),
                onRetry: note.isFailed ? () => _retryAnalysis(note) : null,
                longPressToDelete: false,
                folderLabel: _folderLabelFor(note),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mic_none_outlined,
              size: 48,
              color: DropColors.muted(context),
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

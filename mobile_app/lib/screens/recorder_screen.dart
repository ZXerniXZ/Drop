import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/api_url_resolver.dart';
import '../models/ai_preferences.dart';
import '../models/audio_note.dart';
import '../models/note_structured_data.dart';
import '../models/note_tags_config.dart';
import '../models/record_orb_style.dart';
import '../models/transcript_segment.dart';
import '../services/app_preferences_service.dart';
import '../models/note_filters.dart';
import '../services/chunked_upload_service.dart';
import '../services/drop_api_headers.dart';
import '../services/audio_binary_store.dart';
import '../services/audio_recording_config.dart';
import '../services/cloud_sync_service.dart';
import '../services/local_database_service.dart';
import '../services/note_audio_service.dart';
import '../services/note_reanalysis_service.dart';
import '../services/openrouter_client.dart';
import '../services/recording_foreground_service.dart';
import '../services/server_quota_service.dart';
import '../services/supabase_auth_service.dart';
import '../theme/drop_motion.dart';
import '../theme/drop_theme.dart';
import '../utils/note_filter_utils.dart';
import '../widgets/note_filter_bar.dart';
import '../widgets/drop_bottom_nav.dart';
import '../widgets/drop_logo.dart';
import '../widgets/note_list_card.dart';
import '../widgets/staggered_entrance.dart';
import 'note_detail_screen.dart';
import 'my_data_screen.dart';
import 'record_orb_preview_screen.dart';

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
  NoteFilters _filters = const NoteFilters();
  DropNavTab _activeTab = DropNavTab.file;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isLoadingNotes = true;
  bool _filtersVisible = false;
  List<String> _availableTags = NoteTagsConfig.defaultTags;
  Duration _elapsed = Duration.zero;
  double _amplitudeLevel = 0;
  RecordOrbStyle _orbStyle = RecordOrbStyle.gradientFluid;
  Timer? _timer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  String? _currentPath;
  RecordConfig _recordConfig = AudioRecordingConfig.recordConfig;
  bool _stopping = false;

  List<AudioNote> get _filteredNotes => applyNoteFilters(_notes, _filters);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RecordingForegroundService.addTaskDataCallback(_onForegroundTaskData);
    _loadNotes();
    _loadTags();
    _loadOrbStyle();
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
    _searchController.dispose();
    _recorder.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb) return;
    if (!_isRecording && !_isPaused) return;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_stopRecording(interrupted: true));
    }
  }

  void _onForegroundTaskData(Object data) {
    if (data is Map &&
        data['action'] == 'stop' &&
        (_isRecording || _isPaused)) {
      _stopRecording();
    }
  }

  double _normalizeAmplitude(double db) {
    if (db <= -52) return 0;
    if (db >= -12) return 1;
    return ((db + 52) / 40).clamp(0.0, 1.0);
  }

  Future<void> _loadNotes() async {
    final notes = await LocalDatabaseService.instance.getAllNotes();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _isLoadingNotes = false;
    });
    unawaited(_syncNotesFromCloud());
  }

  Future<void> _syncNotesFromCloud() async {
    final inserted = await CloudSyncService.instance.syncNotesFromServer();
    if (inserted == 0 || !mounted) return;

    final notes = await LocalDatabaseService.instance.getAllNotes();
    if (!mounted) return;
    setState(() => _notes = notes);
  }

  void _updateNoteInList(AudioNote note) {
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index == -1) return;
    setState(() => _notes[index] = note);
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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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

    var tag = placeholder.tag;
    final keyData = data['key_data'];
    if (keyData is Map<String, dynamic>) {
      final tagLabel = keyData['tags'] as String?;
      if (tagLabel != null && tagLabel.isNotEmpty) {
        tag = NoteTagsConfig.normalizeTag(tagLabel, allowed: _availableTags);
      }
    }

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
      final response = await http.get(
        Uri.parse(url),
        headers: DropApiHeaders.auth(accessToken),
      );

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

  Future<Map<String, dynamic>?> _uploadViaBackend({
    required String filePath,
    required AudioNote placeholder,
    required AiPreferences prefs,
    required List<String> tags,
    required int durationSeconds,
  }) async {
    final accessToken = await _requireAccessToken();
    final fileSize = await AudioBinaryStore.instance.byteLength(filePath);
    String jobId;

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
      request.fields['language'] = prefs.transcriptionLanguage.name;
      request.fields['available_tags'] = jsonEncode(tags);
      request.fields['note_id'] = placeholder.id;
      if (prefs.customPrompt.trim().isNotEmpty) {
        request.fields['custom_prompt'] = prefs.customPrompt.trim();
      }
      if (durationSeconds > 0) {
        request.fields['duration_seconds'] = '$durationSeconds';
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final id = data['job_id'] as String?;
        if (id == null || id.isEmpty) {
          throw Exception('Risposta server senza job_id');
        }
        jobId = id;
      } else {
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
    } else {
      jobId = await ChunkedUploadService.instance.uploadFileAndStartJob(
        filePath: filePath,
        accessToken: accessToken,
        prefs: prefs,
        availableTags: tags,
        noteId: placeholder.id,
        durationSeconds: durationSeconds,
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

    return _pollUploadJob(
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
  }

  Future<void> _processUpload({
    required String noteId,
    required String filePath,
    required int durationSeconds,
  }) async {
    try {
      final prefs = await AppPreferencesService.instance.loadAiPreferences();
      final tagsConfig = await AppPreferencesService.instance.loadNoteTags();
      final apiKey = await AppPreferencesService.instance
          .loadOpenRouterApiKey();

      final index = _notes.indexWhere((n) => n.id == noteId);
      if (index == -1) return;
      final placeholder = _notes[index];

      Map<String, dynamic>? result;

      if (apiKey != null && apiKey.isNotEmpty) {
        result = await OpenRouterClient.instance.processAudioFile(
          filePath: filePath,
          apiKey: apiKey,
          prefs: prefs,
          availableTags: tagsConfig.tags,
        );
      } else {
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
        result = await _uploadViaBackend(
          filePath: filePath,
          placeholder: placeholder,
          prefs: prefs,
          tags: tagsConfig.tags,
          durationSeconds: durationSeconds,
        );
      }

      if (!mounted) return;

      if (result == null) return;

      final persistedPath =
          await _persistAudioFile(filePath, noteId) ?? filePath;
      final note = _noteFromResponse(
        result,
        placeholder: placeholder,
        audioPath: persistedPath,
      ).copyWith(clearUploadSession: true, uploadedChunks: 0);

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
      );
      await LocalDatabaseService.instance.saveNote(failed);
      if (!mounted) return;
      _updateNoteInList(failed);
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

  Future<void> _deleteNote(AudioNote note) async {
    await LocalDatabaseService.instance.deleteNote(note.id);
    try {
      // Anche l'audio riscaricato dal server, che non passa per audio_path.
      final path = await NoteAudioService.instance.localPathIfExists(
        note.id,
        currentPath: note.audioPath,
      );
      if (path != null) await AudioBinaryStore.instance.delete(path);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _notes.removeWhere((n) => n.id == note.id));
  }

  Future<void> _togglePauseResume() async {
    if (_isPaused) {
      await _recorder.resume();
      if (!mounted) return;
      setState(() {
        _isPaused = false;
        _isRecording = true;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
        RecordingForegroundService.updateElapsed(_formatDuration(_elapsed));
      });
      return;
    }

    if (!_isRecording) return;

    await _recorder.pause();
    _timer?.cancel();
    if (!mounted) return;
    setState(() {
      _isPaused = true;
      _isRecording = false;
      _amplitudeLevel = 0;
    });
    await RecordingForegroundService.updateElapsed(
      'In pausa · ${_formatDuration(_elapsed)}',
    );
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
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

    try {
      await _recorder.start(_recordConfig, path: path);
      await WakelockPlus.enable();
    } catch (e) {
      await WakelockPlus.disable();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossibile avviare la registrazione: $e')),
      );
      return;
    }

    await RecordingForegroundService.start(
      elapsedLabel: _formatDuration(Duration.zero),
    );

    _amplitudeSub?.cancel();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((amp) {
          if (!mounted) return;
          setState(() => _amplitudeLevel = _normalizeAmplitude(amp.current));
        });

    setState(() {
      _isRecording = true;
      _isPaused = false;
      _elapsed = Duration.zero;
      _amplitudeLevel = 0;
      _currentPath = path;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      RecordingForegroundService.updateElapsed(_formatDuration(_elapsed));
    });
  }

  Future<void> _stopRecording({bool interrupted = false}) async {
    if (_stopping) return;
    if (!_isRecording && !_isPaused) return;
    _stopping = true;

    _timer?.cancel();
    _timer = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    try {
      if (_isPaused) {
        await _recorder.resume();
      }

      final recordedDuration = _elapsed;
      final path = await _recorder.stop();
      await RecordingForegroundService.stop();
      await WakelockPlus.disable();

      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isPaused = false;
        _elapsed = Duration.zero;
        _amplitudeLevel = 0;
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
      );

      await LocalDatabaseService.instance.saveNote(placeholder);
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

    _timer?.cancel();
    _timer = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

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
        _amplitudeLevel = 0;
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

    final processing = note.copyWith(
      analysisStatus: NoteAnalysisStatus.processing,
      analysisPhase: NoteAnalysisPhase.transcribing,
      analysisCurrent: 0,
      analysisTotal: 0,
    );
    await LocalDatabaseService.instance.saveNote(processing);
    if (!mounted) return;
    _updateNoteInList(processing);

    try {
      final jobId = await NoteReanalysisService.instance.requestReanalysis(
        noteId: note.id,
        prefs: prefs,
        availableTags: tagsConfig.tags,
      );

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
      if (result == null || !mounted) return;

      final updated = _noteFromResponse(
        result,
        placeholder: processing,
        audioPath: note.audioPath,
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
        ),
      ),
    );
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
              elapsedLabel: (_isRecording || _isPaused)
                  ? _formatDuration(_elapsed)
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 16, 4),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: DropMotion.medium,
            switchInCurve: DropMotion.enter,
            switchOutCurve: DropMotion.exit,
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
            child: _activeTab == DropNavTab.file
                ? Row(
                    key: const ValueKey('file-header'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const DropLogo(height: 26),
                      const SizedBox(width: 10),
                      Text(
                        'Drop',
                        style: Theme.of(context).textTheme.headlineMedium
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
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
          ),
          const Spacer(),
          if (_activeTab == DropNavTab.file)
            Text(
              '${_filteredNotes.length} note',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
                color: DropColors.muted(context),
              ),
            ),
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

    if (_notes.isEmpty) {
      return _buildEmptyState(
        context,
        title: 'Nessuna nota',
        subtitle:
            'Tocca il pulsante rosso in basso per registrare il tuo primo audio.',
      );
    }

    if (_filteredNotes.isEmpty) {
      return _buildEmptyState(
        context,
        title: 'Nessun risultato',
        subtitle: 'Prova a modificare i filtri o la ricerca.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      itemCount: _filteredNotes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final note = _filteredNotes[index];
        return StaggeredEntrance(
          index: index,
          child: NoteListCard(
            note: note,
            dateLabel: _formatNoteDate(note.dateTime),
            onTap: note.isProcessing ? null : () => _openNoteDetail(note),
            onDelete: () => _deleteNote(note),
            onRetry: note.isFailed ? () => _retryAnalysis(note) : null,
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

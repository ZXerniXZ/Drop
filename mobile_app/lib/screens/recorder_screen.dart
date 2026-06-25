import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/api_url_resolver.dart';
import '../models/audio_note.dart';
import '../models/note_structured_data.dart';
import '../models/note_tags_config.dart';
import '../services/app_preferences_service.dart';
import '../models/note_filters.dart';
import '../services/audio_recording_config.dart';
import '../services/cloud_sync_service.dart';
import '../services/local_database_service.dart';
import '../services/openrouter_client.dart';
import '../services/recording_foreground_service.dart';
import '../services/supabase_auth_service.dart';
import '../theme/drop_theme.dart';
import '../utils/note_filter_utils.dart';
import '../widgets/note_filter_bar.dart';
import '../widgets/drop_bottom_nav.dart';
import '../widgets/drop_logo.dart';
import '../widgets/note_list_card.dart';
import 'note_detail_screen.dart';
import 'my_data_screen.dart';

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

class _RecorderScreenState extends State<RecorderScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final TextEditingController _searchController = TextEditingController();

  List<AudioNote> _notes = [];
  NoteFilters _filters = const NoteFilters();
  DropNavTab _activeTab = DropNavTab.file;
  bool _isRecording = false;
  bool _isLoadingNotes = true;
  bool _filtersVisible = false;
  List<String> _availableTags = NoteTagsConfig.defaultTags;
  Duration _elapsed = Duration.zero;
  double _amplitudeLevel = 0;
  Timer? _timer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  String? _currentPath;

  List<AudioNote> get _filteredNotes => applyNoteFilters(_notes, _filters);

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onForegroundTaskData);
    _loadNotes();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final config = await AppPreferencesService.instance.loadNoteTags();
    if (!mounted) return;
    setState(() => _availableTags = config.tags);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onForegroundTaskData);
    _timer?.cancel();
    _amplitudeSub?.cancel();
    _searchController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _onForegroundTaskData(Object data) {
    if (data is Map && data['action'] == 'stop' && _isRecording) {
      _stopRecording();
    }
  }

  double _normalizeAmplitude(double db) {
    if (db <= -60) return 0;
    if (db >= 0) return 1;
    return (db + 60) / 60;
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
    final raw = data['raw_transcription'] as String? ??
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

    return placeholder.copyWith(
      title: (title != null && title.isNotEmpty) ? title : placeholder.title,
      audioPath: audioPath,
      transcription: formatted,
      summary: summary,
      rawTranscription: raw,
      analysisStatus: NoteAnalysisStatus.ready,
      structuredData: structured,
      tag: tag,
    );
  }

  Future<String?> _persistAudioFile(String tempPath, String noteId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${dir.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
      final dest = AudioRecordingConfig.buildPersistedPath(
        recordingsDir.path,
        noteId,
      );
      await File(tempPath).copy(dest);
      return dest;
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

  Future<Map<String, dynamic>?> _pollUploadJob(String jobId) async {
    const maxAttempts = 200;
    const pollInterval = Duration(seconds: 3);

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!mounted) return null;

      final url = await _resolveJobUrl(jobId);
      final accessToken = await _requireAccessToken();
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Sessione scaduta. Effettua di nuovo l\'accesso.');
      }

      if (response.statusCode == 404) {
        await Future<void>.delayed(pollInterval);
        continue;
      }

      if (response.statusCode != 200) {
        throw Exception('Polling fallito (${response.statusCode})');
      }

      final job = jsonDecode(response.body) as Map<String, dynamic>;
      final status = job['status'] as String?;

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

    throw Exception('Timeout elaborazione (oltre 10 minuti)');
  }

  Future<void> _processUpload({
    required String noteId,
    required String filePath,
    required int durationSeconds,
  }) async {
    try {
      final prefs = await AppPreferencesService.instance.loadAiPreferences();
      final tagsConfig = await AppPreferencesService.instance.loadNoteTags();
      final apiKey = await AppPreferencesService.instance.loadOpenRouterApiKey();

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
        final url = await _resolveUploadUrl();
        final accessToken = await _requireAccessToken();
        final request = http.MultipartRequest('POST', Uri.parse(url));
        request.headers['Authorization'] = 'Bearer $accessToken';
        request.files.add(await http.MultipartFile.fromPath('file', filePath));
        request.fields['ai_model'] = prefs.model.openRouterId;
        request.fields['language'] = prefs.transcriptionLanguage.name;
        request.fields['available_tags'] = jsonEncode(tagsConfig.tags);
        if (prefs.customPrompt.trim().isNotEmpty) {
          request.fields['custom_prompt'] = prefs.customPrompt.trim();
        }

        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (!mounted) return;

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final jobId = data['job_id'] as String?;
          if (jobId == null || jobId.isEmpty) {
            throw Exception('Risposta server senza job_id');
          }
          result = await _pollUploadJob(jobId);
        } else {
          var errorDetail = response.body;
          try {
            final errJson = jsonDecode(response.body) as Map<String, dynamic>;
            errorDetail = errJson['detail']?.toString() ?? errorDetail;
          } catch (_) {}
          if (response.statusCode == 401 || response.statusCode == 403) {
            errorDetail = 'Accesso richiesto. Effettua di nuovo l\'accesso.';
          }
          final failed = placeholder.copyWith(
            analysisStatus: NoteAnalysisStatus.failed,
            transcription: 'Upload fallito (${response.statusCode}): $errorDetail',
          );
          await LocalDatabaseService.instance.saveNote(failed);
          if (!mounted) return;
          _updateNoteInList(failed);
          return;
        }
      }

      if (!mounted) return;

      if (result == null) return;

      final persistedPath =
          await _persistAudioFile(filePath, noteId) ?? filePath;
      final note = _noteFromResponse(
        result,
        placeholder: placeholder,
        audioPath: persistedPath,
      );

      await LocalDatabaseService.instance.saveNote(note);
      if (!mounted) return;
      _updateNoteInList(note);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trascrizione completata'),
          backgroundColor: Colors.green,
        ),
      );
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

  Future<void> _deleteNote(AudioNote note) async {
    await LocalDatabaseService.instance.deleteNote(note.id);
    if (note.audioPath.isNotEmpty) {
      try {
        final file = File(note.audioPath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _notes.removeWhere((n) => n.id == note.id));
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
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

    final dir = await getTemporaryDirectory();
    final path = AudioRecordingConfig.buildTempPath(dir.path);

    await _recorder.start(AudioRecordingConfig.recordConfig, path: path);

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

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _timer = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    final recordedDuration = _elapsed;
    final path = await _recorder.stop();
    await RecordingForegroundService.stop();

    setState(() {
      _isRecording = false;
      _elapsed = Duration.zero;
      _amplitudeLevel = 0;
    });

    final savedPath = path ?? _currentPath;
    _currentPath = null;
    if (savedPath == null || !mounted) return;

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

    unawaited(_processUpload(
      noteId: noteId,
      filePath: savedPath,
      durationSeconds: recordedDuration.inSeconds,
    ));
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

    if (!await File(path).exists()) {
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

    unawaited(_processUpload(
      noteId: note.id,
      filePath: path,
      durationSeconds: note.durationSeconds,
    ));
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
      MaterialPageRoute<void>(
        builder: (_) => NoteDetailScreen(
          note: note,
          onDelete: () => _deleteNote(note),
          onRetry: note.isFailed ? () => _retryAnalysis(note) : null,
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
            Expanded(child: _buildBody(context)),
            DropBottomNav(
              activeTab: _activeTab,
              onTabChanged: (tab) {
                setState(() => _activeTab = tab);
                if (tab == DropNavTab.file) _loadTags();
              },
              onRecordTap: _toggleRecording,
              isRecording: _isRecording,
              amplitudeLevel: _amplitudeLevel,
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
          if (_activeTab == DropNavTab.file)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DropLogo(height: 26),
                const SizedBox(width: 10),
                Text(
                  'Drop',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                ),
              ],
            )
          else
            Text(
              'Impostazioni',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
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
      onToggleFilters: () =>
          setState(() => _filtersVisible = !_filtersVisible),
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
        return NoteListCard(
          note: note,
          dateLabel: _formatNoteDate(note.dateTime),
          onTap: note.isProcessing ? null : () => _openNoteDetail(note),
          onDelete: () => _deleteNote(note),
          onRetry: note.isFailed ? () => _retryAnalysis(note) : null,
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/audio_note.dart';
import '../services/local_database_service.dart';
import '../theme/drop_theme.dart';
import '../widgets/drop_bottom_nav.dart';
import '../widgets/note_list_card.dart';
import '../widgets/recording_banner.dart';
import 'note_detail_screen.dart';

/// URL produzione (Cloudflare Tunnel) — usato automaticamente nelle build release (APK CI).
const String productionBackendUrl = 'https://api.drop-prj.xyz/upload-audio';

/// IP del PC in rete locale — solo per sviluppo in debug (`flutter run`).
const String physicalDeviceBackendHost = 'http://192.168.1.100:8080';

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

  List<AudioNote> _notes = [];
  DropNavTab _activeTab = DropNavTab.file;
  bool _isRecording = false;
  bool _isUploading = false;
  bool _isLoadingNotes = true;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _currentPath;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    final notes = await LocalDatabaseService.instance.getAllNotes();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _isLoadingNotes = false;
    });
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
    required String id,
    required String audioPath,
    required DateTime createdAt,
  }) {
    final raw = data['raw_transcription'] as String? ??
        data['transcription'] as String? ??
        '';
    final formatted = data['formatted_transcription'] as String? ?? raw;
    final summary = data['summary'] as String? ?? '';

    return AudioNote(
      id: id,
      title: AudioNote.titleFromDateTime(createdAt),
      dateTime: createdAt,
      audioPath: audioPath,
      transcription: formatted,
      summary: summary,
      rawTranscription: raw,
    );
  }

  Future<String?> _persistAudioFile(String tempPath, String noteId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${dir.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
      final dest = '${recordingsDir.path}/$noteId.m4a';
      await File(tempPath).copy(dest);
      return dest;
    } catch (_) {
      return tempPath;
    }
  }

  Future<bool> _isAndroidEmulator() async {
    if (!Platform.isAndroid) return false;
    try {
      final cpuinfo = await File('/proc/cpuinfo').readAsString();
      return cpuinfo.contains('goldfish') ||
          cpuinfo.contains('ranchu') ||
          cpuinfo.contains('qemu');
    } catch (_) {
      return false;
    }
  }

  Future<String> _resolveUploadUrl() async {
    if (kReleaseMode) {
      return productionBackendUrl;
    }
    if (Platform.isAndroid) {
      if (await _isAndroidEmulator()) {
        return 'http://10.0.2.2:8080/upload-audio';
      }
      return '$physicalDeviceBackendHost/upload-audio';
    }
    if (Platform.isIOS) {
      return '$physicalDeviceBackendHost/upload-audio';
    }
    return 'http://localhost:8080/upload-audio';
  }

  Future<void> _uploadAudio(String filePath) async {
    setState(() => _isUploading = true);

    try {
      final url = await _resolveUploadUrl();
      final request = http.MultipartRequest('POST', Uri.parse(url));
      request.files.add(
        await http.MultipartFile.fromPath('file', filePath),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final createdAt = DateTime.now();
        final noteId = createdAt.millisecondsSinceEpoch.toString();
        final persistedPath =
            await _persistAudioFile(filePath, noteId) ?? filePath;
        final note = _noteFromResponse(
          data,
          id: noteId,
          audioPath: persistedPath,
          createdAt: createdAt,
        );

        await LocalDatabaseService.instance.saveNote(note);

        if (!mounted) return;
        setState(() {
          _notes.insert(0, note);
          _activeTab = DropNavTab.file;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trascrizione salvata'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Upload fallito (${response.statusCode}): ${response.body}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore upload: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
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
    if (_isUploading) return;

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
    final path =
        '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _elapsed = Duration.zero;
      _currentPath = path;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _timer = null;
    final path = await _recorder.stop();

    setState(() {
      _isRecording = false;
      _elapsed = Duration.zero;
    });

    final savedPath = path ?? _currentPath;
    _currentPath = null;

    if (savedPath == null || !mounted) return;
    await _uploadAudio(savedPath);
  }

  void _openNoteDetail(AudioNote note) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteDetailScreen(
          note: note,
          onDelete: () => _deleteNote(note),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(context),
                _buildSubHeader(context),
                if (_isRecording)
                  RecordingBanner(
                    elapsedLabel: _formatDuration(_elapsed),
                    onStop: _stopRecording,
                  ),
                Expanded(child: _buildBody(context)),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DropBottomNav(
                activeTab: _activeTab,
                onTabChanged: (tab) => setState(() => _activeTab = tab),
                onRecordTap: _toggleRecording,
                isRecording: _isRecording,
                isBusy: _isRecording || _isUploading,
              ),
            ),
            if (_isUploading) _buildUploadOverlay(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 16, 16),
      child: Row(
        children: [
          Text(
            'DROP',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onToggleTheme,
            style: IconButton.styleFrom(
              side: BorderSide(color: DropColors.border(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(
              widget.isDarkMode ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: DropColors.border(context))),
      ),
      child: Row(
        children: [
          if (_activeTab == DropNavTab.file) ...[
            Icon(Icons.tune, size: 18, color: DropColors.muted(context)),
            const SizedBox(width: 8),
            Text(
              'FILTRO ATTIVO',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const Spacer(),
            Text(
              'NOTE (${_notes.length})',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 12,
                    letterSpacing: 1.4,
                  ),
            ),
          ] else
            Text(
              'IMPOSTAZIONI',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 12,
                    letterSpacing: 1.4,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_activeTab == DropNavTab.settings) {
      return _buildSettingsPlaceholder(context);
    }

    if (_isLoadingNotes) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 120),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.mic_none_outlined,
                size: 48,
                color: DropColors.muted(context),
              ),
              const SizedBox(height: 16),
              Text(
                'Nessuna nota',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Tocca il pulsante rosso in basso per registrare il tuo primo audio.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 130),
      itemCount: _notes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final note = _notes[index];
        return NoteListCard(
          note: note,
          dateLabel: _formatNoteDate(note.dateTime),
          onTap: () => _openNoteDetail(note),
          onDelete: () => _deleteNote(note),
        );
      },
    );
  }

  Widget _buildSettingsPlaceholder(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 120),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction_outlined,
              size: 40,
              color: DropColors.muted(context),
            ),
            const SizedBox(height: 16),
            Text(
              'In arrivo',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Wallet, impostazioni AI, backup e stato server saranno disponibili in una prossima versione.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadOverlay(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: DropColors.border(context)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 20),
              Text(
                'TRASCRIZIONE IN CORSO',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Invio audio e elaborazione AI...',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

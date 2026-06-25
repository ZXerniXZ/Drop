import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'models/audio_note.dart';
import 'screens/note_detail_screen.dart';
import 'services/local_database_service.dart';

/// URL produzione (Cloudflare Tunnel) — usato automaticamente nelle build release (APK CI).
const String productionBackendUrl = 'https://api.drop-prj.xyz/upload-audio';

/// IP del PC in rete locale — solo per sviluppo in debug (`flutter run`).
const String physicalDeviceBackendHost = 'http://192.168.1.100:8080';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabaseService.instance.init();
  runApp(const DropApp());
}

class DropApp extends StatelessWidget {
  const DropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        useMaterial3: true,
      ),
      home: const RecorderScreen(),
    );
  }
}

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final LocalDatabaseService _db = LocalDatabaseService.instance;

  List<AudioNote> _notes = [];
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
    final notes = await _db.getAllNotes();
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

  String _formatTimestamp(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
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

        await _db.saveNote(note);

        if (!mounted) return;
        setState(() {
          _notes.insert(0, note);
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
    await _db.deleteNote(note.id);
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
        builder: (_) => NoteDetailScreen(note: note),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isRecording || _isUploading;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Column(
                    children: [
                      Text(
                        'Drop',
                        style:
                            Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isUploading
                            ? 'Trascrizione in corso...'
                            : _isRecording
                                ? 'Registrazione in corso'
                                : 'Tocca per registrare',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                      if (_isRecording) ...[
                        const SizedBox(height: 16),
                        Text(
                          _formatDuration(_elapsed),
                          style:
                              Theme.of(context).textTheme.displaySmall?.copyWith(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap:
                            isBusy && !_isRecording ? null : _toggleRecording,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isRecording
                                ? Colors.red.withValues(alpha: 0.2)
                                : Colors.grey.withValues(alpha: 0.15),
                            border: Border.all(
                              color: _isRecording
                                  ? Colors.red
                                  : Colors.grey.shade600,
                              width: 3,
                            ),
                            boxShadow: _isRecording
                                ? [
                                    BoxShadow(
                                      color:
                                          Colors.red.withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            _isRecording ? Icons.stop_rounded : Icons.mic,
                            size: 40,
                            color: _isUploading
                                ? Colors.grey.shade700
                                : _isRecording
                                    ? Colors.red
                                    : Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.article_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Trascrizioni',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const Spacer(),
                      Text(
                        '${_notes.length}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoadingNotes
                      ? const Center(child: CircularProgressIndicator())
                      : _notes.isEmpty
                          ? Center(
                              child: Text(
                                'Nessuna trascrizione.\nRegistra un audio per iniziare.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: Colors.grey),
                              ),
                            )
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: _notes.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                return _NoteCard(
                                  note: _notes[index],
                                  formatTimestamp: _formatTimestamp,
                                  onTap: () =>
                                      _openNoteDetail(_notes[index]),
                                  onDelete: () => _deleteNote(_notes[index]),
                                );
                              },
                            ),
                ),
              ],
            ),
            if (_isUploading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Invio audio e trascrizione...'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.formatTimestamp,
    required this.onTap,
    required this.onDelete,
  });

  final AudioNote note;
  final String Function(DateTime) formatTimestamp;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final displayText = note.transcription.isNotEmpty
        ? note.transcription
        : note.rawTranscription;

    return Card(
      color: const Color(0xFF1E1E1E),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: Colors.grey.shade600,
                    onPressed: onDelete,
                    tooltip: 'Elimina',
                  ),
                ],
              ),
              Text(
                formatTimestamp(note.dateTime),
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Text(
                displayText.isEmpty ? '(Trascrizione vuota)' : displayText,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

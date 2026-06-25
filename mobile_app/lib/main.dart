import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// URL produzione (Cloudflare Tunnel) — usato automaticamente nelle build release (APK CI).
const String productionBackendUrl = 'https://api.drop-prj.xyz/upload-audio';

/// IP del PC in rete locale — solo per sviluppo in debug (`flutter run`).
const String physicalDeviceBackendHost = 'http://192.168.1.100:8080';

void main() {
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

class TranscriptionEntry {
  const TranscriptionEntry({
    required this.createdAt,
    required this.filename,
    required this.formattedText,
    required this.rawText,
    required this.summary,
  });

  final DateTime createdAt;
  final String filename;
  final String formattedText;
  final String rawText;
  final String summary;
}

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final List<TranscriptionEntry> _transcriptions = [];

  bool _isRecording = false;
  bool _isUploading = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _currentPath;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
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

  TranscriptionEntry _entryFromResponse(Map<String, dynamic> data) {
    final raw = data['raw_transcription'] as String? ??
        data['transcription'] as String? ??
        '';
    final formatted = data['formatted_transcription'] as String? ?? raw;
    final summary = data['summary'] as String? ?? '';
    final filename = data['filename'] as String? ?? 'audio.m4a';

    return TranscriptionEntry(
      createdAt: DateTime.now(),
      filename: filename,
      formattedText: formatted,
      rawText: raw,
      summary: summary,
    );
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

        setState(() {
          _transcriptions.insert(0, _entryFromResponse(data));
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trascrizione completata'),
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
                        '${_transcriptions.length}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _transcriptions.isEmpty
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
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _transcriptions.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _TranscriptionCard(
                              entry: _transcriptions[index],
                              formatTimestamp: _formatTimestamp,
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

class _TranscriptionCard extends StatelessWidget {
  const _TranscriptionCard({
    required this.entry,
    required this.formatTimestamp,
  });

  final TranscriptionEntry entry;
  final String Function(DateTime) formatTimestamp;

  @override
  Widget build(BuildContext context) {
    final displayText = entry.formattedText.isNotEmpty
        ? entry.formattedText
        : entry.rawText;

    return Card(
      color: const Color(0xFF1E1E1E),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Row(
            children: [
              Text(
                formatTimestamp(entry.createdAt),
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Colors.grey),
              ),
              const Spacer(),
              Icon(
                Icons.audiotrack,
                size: 14,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  entry.filename,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: Colors.grey),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              displayText.isEmpty ? '(Trascrizione vuota)' : displayText,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          children: [
            if (entry.summary.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Riepilogo',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                entry.summary,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (entry.rawText.isNotEmpty &&
                entry.rawText != entry.formattedText) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Trascrizione grezza',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                entry.rawText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade400,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

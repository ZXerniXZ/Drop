import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// IP del PC in rete locale — modifica con l'indirizzo del tuo backend.
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

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  final AudioRecorder _recorder = AudioRecorder();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio caricato con successo sul backend'),
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
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Drop',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isUploading
                        ? 'Caricamento in corso...'
                        : _isRecording
                            ? 'Registrazione in corso'
                            : 'Tocca per registrare',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                  if (_isRecording) ...[
                    const SizedBox(height: 24),
                    Text(
                      _formatDuration(_elapsed),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                  const SizedBox(height: 48),
                  GestureDetector(
                    onTap: isBusy && !_isRecording ? null : _toggleRecording,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 120,
                      height: 120,
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
                                  color: Colors.red.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop_rounded : Icons.mic,
                        size: 48,
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
            if (_isUploading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Invio audio al backend...'),
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

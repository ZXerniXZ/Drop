import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

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

    if (!mounted) return;
    final savedPath = path ?? _currentPath;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Registrazione salvata in: $savedPath'),
        duration: const Duration(seconds: 5),
      ),
    );
    _currentPath = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
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
                _isRecording ? 'Registrazione in corso' : 'Tocca per registrare',
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
                onTap: _toggleRecording,
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
                      color: _isRecording ? Colors.red : Colors.grey.shade600,
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
                    color: _isRecording ? Colors.red : Colors.grey.shade400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

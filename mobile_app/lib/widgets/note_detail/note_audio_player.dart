import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../theme/drop_theme.dart';

class NoteAudioPlayer extends StatefulWidget {
  const NoteAudioPlayer({
    super.key,
    required this.audioPath,
    required this.fallbackDurationSeconds,
  });

  final String audioPath;
  final int fallbackDurationSeconds;

  @override
  State<NoteAudioPlayer> createState() => _NoteAudioPlayerState();
}

class _NoteAudioPlayerState extends State<NoteAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool _isReady = false;
  bool _fileMissing = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (widget.audioPath.isEmpty || !await File(widget.audioPath).exists()) {
      if (!mounted) return;
      setState(() {
        _fileMissing = true;
        _duration = Duration(seconds: widget.fallbackDurationSeconds);
      });
      return;
    }

    try {
      await _player.setFilePath(widget.audioPath);
      final duration = _player.duration;
      _positionSub = _player.positionStream.listen((position) {
        if (!mounted) return;
        setState(() => _position = position);
      });
      _stateSub = _player.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
          }
        });
      });

      if (!mounted) return;
      setState(() {
        _isReady = true;
        _duration = duration ??
            Duration(seconds: widget.fallbackDurationSeconds);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fileMissing = true;
        _duration = Duration(seconds: widget.fallbackDurationSeconds);
      });
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> _togglePlay() async {
    if (!_isReady || _fileMissing) return;
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  Future<void> _seek(double value) async {
    if (!_isReady || _fileMissing) return;
    final maxMs = _duration.inMilliseconds;
    if (maxMs <= 0) return;
    await _player.seek(Duration(milliseconds: (value * maxMs).round()));
  }

  Future<void> _skip(int seconds) async {
    if (!_isReady || _fileMissing) return;
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : target > _duration
            ? _duration
            : target;
    await _player.seek(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds;
    final sliderValue =
        maxMs > 0 ? (_position.inMilliseconds / maxMs).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
      child: Column(
        children: [
          const Spacer(),
          _WaveformPlaceholder(progress: sliderValue),
          const SizedBox(height: 32),
          if (_fileMissing)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'FILE AUDIO NON DISPONIBILE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: DropColors.recordRed,
                    ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _format(_position),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.4,
                    ),
              ),
              Text(
                _format(_duration),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.4,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: sliderValue,
              onChanged: _isReady && !_fileMissing ? _seek : null,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _isReady && !_fileMissing
                    ? () => _skip(-15)
                    : null,
                icon: const Icon(Icons.replay_10_outlined, size: 28),
                color: DropColors.muted(context),
              ),
              const SizedBox(width: 24),
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.onSurface,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              IconButton(
                onPressed:
                    _isReady && !_fileMissing ? () => _skip(15) : null,
                icon: const Icon(Icons.forward_10_outlined, size: 28),
                color: DropColors.muted(context),
              ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _WaveformPlaceholder extends StatelessWidget {
  const _WaveformPlaceholder({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DropColors.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(48, (i) {
          final distance = (i - 24).abs() / 24;
          final heightFactor = (1 - distance) * 0.7 + 0.15;
          final barHeight = 12.0 + (48 * heightFactor * (0.6 + (i % 5) * 0.08));
          final played = i / 48 <= progress;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: played
                        ? Theme.of(context).colorScheme.onSurface
                        : DropColors.muted(context).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/transcript_segment.dart';
import '../../services/audio_binary_store.dart';
import '../../services/note_audio_service.dart';
import '../../theme/drop_theme.dart';
import 'karaoke_transcript.dart';

class NoteAudioPlayer extends StatefulWidget {
  const NoteAudioPlayer({
    super.key,
    required this.noteId,
    required this.audioPath,
    required this.fallbackDurationSeconds,
    this.segments = const [],
  });

  final String noteId;
  final String audioPath;
  final int fallbackDurationSeconds;
  final List<TranscriptSegment> segments;

  @override
  State<NoteAudioPlayer> createState() => _NoteAudioPlayerState();
}

class _NoteAudioPlayerState extends State<NoteAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool _isReady = false;
  bool _fileMissing = false;
  bool _isDownloading = false;
  String? _downloadError;
  late String _audioPath;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _audioPath = widget.audioPath;
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final resolved = await NoteAudioService.instance.localPathIfExists(
      widget.noteId,
      currentPath: _audioPath,
    );

    if (resolved == null) {
      if (!mounted) return;
      setState(() {
        _fileMissing = true;
        _isReady = false;
        _duration = Duration(seconds: widget.fallbackDurationSeconds);
      });
      return;
    }
    _audioPath = resolved;

    try {
      // Init puo' ripetersi dopo un download: evita doppie sottoscrizioni.
      await _positionSub?.cancel();
      await _stateSub?.cancel();

      final playback = await AudioBinaryStore.instance.playbackUri(_audioPath);
      if (playback == null) {
        throw Exception('Audio non disponibile');
      }
      if (AudioBinaryStore.instance.playbackUsesUrl) {
        await _player.setUrl(playback);
      } else {
        await _player.setFilePath(playback);
      }
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
        _fileMissing = false;
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

  /// L'audio non viene scaricato da solo: un file da decine di MB su rete
  /// mobile deve restare una scelta dell'utente.
  Future<void> _downloadAudio() async {
    setState(() {
      _isDownloading = true;
      _downloadError = null;
    });

    try {
      final path = await NoteAudioService.instance.downloadAudio(widget.noteId);
      if (!mounted) return;
      if (path == null) {
        setState(() {
          _isDownloading = false;
          _downloadError = 'Il server non ha piu\' questo audio';
        });
        return;
      }
      _audioPath = path;
      setState(() => _isDownloading = false);
      await _initPlayer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadError = '$e';
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

  Future<void> _seekTo(Duration position) async {
    if (!_isReady || _fileMissing) return;
    await _player.seek(position);
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

  Widget _buildMissingAudio(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Text(
            'FILE AUDIO NON DISPONIBILE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: DropColors.recordRed,
            ),
          ),
          if (_downloadError != null) ...[
            const SizedBox(height: 4),
            Text(
              _downloadError!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: DropColors.recordRed.withValues(alpha: 0.85),
              ),
            ),
          ],
          const SizedBox(height: 4),
          if (_isDownloading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _downloadAudio,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Scarica dal server'),
              style: TextButton.styleFrom(
                foregroundColor: DropColors.recordRed,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds;
    final sliderValue =
        maxMs > 0 ? (_position.inMilliseconds / maxMs).clamp(0.0, 1.0) : 0.0;

    final hasKaraoke = widget.segments.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
      child: Column(
        children: [
          if (hasKaraoke)
            Expanded(
              child: KaraokeTranscript(
                segments: widget.segments,
                position: _position,
                onSeek: _seekTo,
              ),
            )
          else ...[
            const Spacer(),
            _WaveformPlaceholder(progress: sliderValue),
          ],
          const SizedBox(height: 24),
          if (_fileMissing) _buildMissingAudio(context),
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
          // Con il karaoke lo spazio verticale va alla trascrizione, non a un
          // vuoto sotto i comandi.
          if (!hasKaraoke) const Spacer(),
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

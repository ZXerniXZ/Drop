import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lottie/lottie.dart';

import '../theme/drop_gradients.dart';

/// Pallino idle stile classico record: cerchio esterno + punto centrale.
class RecordIdleDot extends StatelessWidget {
  const RecordIdleDot({
    super.key,
    required this.size,
    required this.breath,
  });

  final double size;
  final double breath;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    final outer = size * 0.88;
    final stroke = (size * 0.05).clamp(2.0, 3.2);
    final dot = size * (0.21 + breath * 0.03);

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: outer,
          height: outer,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.58 + breath * 0.18),
              width: stroke,
            ),
          ),
          child: Center(
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.72 + breath * 0.28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Livelli audio mutabili letti dai delegate Lottie senza rebuild del player.
class BlobAudioLevels {
  double display = 0;
  double blob1 = 0;
  double blob2 = 0;

  void reset() {
    display = 0;
    blob1 = 0;
    blob2 = 0;
  }
}

class SiriLottieOrb extends StatefulWidget {
  const SiriLottieOrb({
    super.key,
    required this.size,
    required this.isAnimating,
  });

  final double size;
  final bool isAnimating;

  @override
  State<SiriLottieOrb> createState() => SiriLottieOrbState();
}

class SiriLottieOrbState extends State<SiriLottieOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lottieController;
  final BlobAudioLevels _levels = BlobAudioLevels();
  Duration _baseDuration = const Duration(seconds: 5);
  bool _compositionLoaded = false;
  double _inputLevel = 0;

  static const _lottieFit = 0.74;

  /// Risposta rapida a metà volume, plateau prima del massimo (evita la “palla”).
  double _voiceLevel(double display) {
    final d = display.clamp(0.0, 1.0);
    return (1 - math.exp(-d * 2.0)) * 0.55;
  }

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _lottieController.addListener(_syncBlobLevels);
  }

  void setAudioLevel(double level) {
    _inputLevel = level.clamp(0.0, 1.0);
    _syncBlobLevels();
  }

  void _syncBlobLevels() {
    final input = _inputLevel;
    _levels.display += (input - _levels.display) * 0.4;
    final voice = widget.isAnimating ? _voiceLevel(_levels.display) : 0.0;
    final phase = _lottieController.value * math.pi * 2;
    final wobble1 = math.sin(phase * 2.7) * 0.5 + 0.5;
    final wobble2 = math.sin(phase * 3.9 + 1.4) * 0.5 + 0.5;
    final b1 = voice <= 0 ? 0.0 : voice * (0.22 + 0.78 * wobble1);
    final b2 = voice <= 0 ? 0.0 : voice * (0.22 + 0.78 * wobble2);
    _levels.blob1 += (b1 - _levels.blob1) * 0.58;
    _levels.blob2 += (b2 - _levels.blob2) * 0.42;
  }

  @override
  void didUpdateWidget(covariant SiriLottieOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_compositionLoaded) return;
    if (oldWidget.isAnimating != widget.isAnimating) {
      _schedulePlaybackSync();
    }
    if (!widget.isAnimating) {
      _inputLevel = 0;
      _levels.reset();
    }
  }

  void _schedulePlaybackSync() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPlayback();
    });
  }

  void _onLottieLoaded(LottieComposition composition) {
    if (!mounted || _compositionLoaded) return;
    _baseDuration = composition.duration.inMilliseconds > 0
        ? composition.duration
        : const Duration(seconds: 5);
    _compositionLoaded = true;
    _schedulePlaybackSync();
  }

  void _syncPlayback() {
    if (!mounted || !_compositionLoaded) return;

    const speed = 2.6;
    _lottieController.duration = Duration(
      milliseconds: (_baseDuration.inMilliseconds / speed).round(),
    );

    if (widget.isAnimating) {
      if (!_lottieController.isAnimating) {
        _lottieController.repeat();
      }
    } else {
      _lottieController.stop();
      _lottieController.value = 0;
      _levels.reset();
    }
  }

  @override
  void dispose() {
    _lottieController
      ..removeListener(_syncBlobLevels)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lottieSize = widget.size * _lottieFit;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: SizedBox(
          width: lottieSize,
          height: lottieSize,
          child: ClipOval(
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => RadialGradient(
                center: Alignment.center,
                radius: 0.62,
                colors: [
                  DropGradients.chat[2],
                  DropGradients.chat[1],
                  DropGradients.chat[3],
                  DropGradients.chat[0],
                ],
                stops: const [0.0, 0.35, 0.7, 1.0],
              ).createShader(bounds),
              child: _LottieBaseLayer(
                controller: _lottieController,
                levels: _levels,
                onLoaded: _onLottieLoaded,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LottieBaseLayer extends StatefulWidget {
  const _LottieBaseLayer({
    required this.controller,
    required this.levels,
    required this.onLoaded,
  });

  final AnimationController controller;
  final BlobAudioLevels levels;
  final void Function(LottieComposition) onLoaded;

  @override
  State<_LottieBaseLayer> createState() => _LottieBaseLayerState();
}

class _LottieBaseLayerState extends State<_LottieBaseLayer> {
  Widget? _lottieChild;

  static const _maxBoost = 0.14;

  double _audioBoost(double level, Offset base) {
    if (level <= 0.001) return 0;
    final headroom = ((1.12 - base.dx).clamp(0.0, 0.12)) / 0.12;
    return (level * 0.24 * headroom).clamp(0.0, _maxBoost);
  }

  @override
  Widget build(BuildContext context) {
    _lottieChild ??= Lottie.asset(
      'assets/animations/siri_blob.json',
      controller: widget.controller,
      fit: BoxFit.contain,
      delegates: LottieDelegates(
        values: [
          ValueDelegate.transformScale(
            const ['blob 1', 'Shape 1'],
            callback: (info) {
              final base = Offset.lerp(
                info.startValue,
                info.endValue,
                info.interpolatedKeyframeProgress,
              )!;
              final boost = _audioBoost(widget.levels.blob1, base);
              if (boost <= 0) return base;
              return Offset(base.dx + boost, base.dy + boost);
            },
          ),
          ValueDelegate.transformScale(
            const ['blob 2', 'Shape 1'],
            callback: (info) {
              final base = Offset.lerp(
                info.startValue,
                info.endValue,
                info.interpolatedKeyframeProgress,
              )!;
              final boost = _audioBoost(widget.levels.blob2, base);
              if (boost <= 0) return base;
              return Offset(base.dx + boost, base.dy + boost);
            },
          ),
        ],
      ),
      onLoaded: widget.onLoaded,
    );
    return _lottieChild!;
  }
}

class SiriOrbMorph extends StatelessWidget {
  const SiriOrbMorph({
    super.key,
    required this.orbKey,
    required this.expand,
    required this.isSessionActive,
    required this.breath,
    required this.size,
  });

  final GlobalKey<SiriLottieOrbState> orbKey;
  final double expand;
  final bool isSessionActive;
  final double breath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeInOutCubic.transform(expand.clamp(0.0, 1.0));
    final idleOpacity = (1 - Curves.easeIn.transform(t)).clamp(0.0, 1.0);
    final orbOpacity = Curves.easeOut.transform(t).clamp(0.0, 1.0);
    final idleScale = 1.0 - t * 0.12;
    final orbScale = 0.38 + t * 0.62;
    final mountOrb = isSessionActive || expand > 0.001;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (mountOrb)
            IgnorePointer(
              ignoring: orbOpacity < 0.05,
              child: Opacity(
                opacity: orbOpacity,
                child: Transform.scale(
                  scale: orbScale,
                  child: SiriLottieOrb(
                    key: orbKey,
                    size: size,
                    isAnimating: isSessionActive,
                  ),
                ),
              ),
            ),
          IgnorePointer(
            ignoring: idleOpacity < 0.05,
            child: Opacity(
              opacity: idleOpacity,
              child: Transform.scale(
                scale: idleScale,
                child: RecordIdleDot(
                  size: size,
                  breath: breath,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

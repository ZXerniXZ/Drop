import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/drop_gradients.dart';
import '../theme/drop_motion.dart';

/// Blob Lottie stile Siri con gradiente chat, ingresso/uscita e reattività al volume.
class SiriLottieOrb extends StatefulWidget {
  const SiriLottieOrb({
    super.key,
    required this.size,
    required this.audioLevel,
    required this.isAnimating,
    required this.isDark,
  });

  final double size;
  final double audioLevel;
  final bool isAnimating;
  final bool isDark;

  @override
  State<SiriLottieOrb> createState() => _SiriLottieOrbState();
}

class _SiriLottieOrbState extends State<SiriLottieOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lottieController;
  Duration _baseDuration = const Duration(seconds: 5);
  Duration? _appliedDuration;
  bool _compositionLoaded = false;
  double _displayLevel = 0;

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant SiriLottieOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_compositionLoaded) _syncPlayback();
  }

  void _onLottieLoaded(LottieComposition composition) {
    _baseDuration = composition.duration;
    _compositionLoaded = true;
    _syncPlayback(force: true);
  }

  void _syncPlayback({bool force = false}) {
    if (!mounted || !_compositionLoaded) return;

    final level = widget.audioLevel.clamp(0.0, 1.0);
    final speed = widget.isAnimating ? 0.55 + level * 1.65 : 0.35;
    final newDuration = Duration(
      milliseconds: (_baseDuration.inMilliseconds / speed).round(),
    );

    if (force || _appliedDuration != newDuration) {
      _appliedDuration = newDuration;
      _lottieController.duration = newDuration;
    }

    if (widget.isAnimating) {
      if (!_lottieController.isAnimating) _lottieController.repeat();
    } else if (_lottieController.isAnimating) {
      _lottieController
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _lottieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _displayLevel += (widget.audioLevel - _displayLevel) * 0.22;
    final level = _displayLevel.clamp(0.0, 1.0);
    if (_compositionLoaded) _syncPlayback();

    final pulseScale = widget.isAnimating ? 1.0 + level * 0.18 : 1.0;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Transform.scale(
        scale: pulseScale,
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => RadialGradient(
            center: Alignment.center,
            radius: 0.85,
            colors: [
              DropGradients.chat[2],
              DropGradients.chat[1],
              DropGradients.chat[3],
              DropGradients.chat[0],
            ],
            stops: const [0.0, 0.35, 0.7, 1.0],
          ).createShader(bounds),
          child: Lottie.asset(
            'assets/animations/siri_blob.json',
            controller: _lottieController,
            fit: BoxFit.contain,
            onLoaded: _onLottieLoaded,
          ),
        ),
      ),
    );
  }
}

/// Transizione scale/fade tra orb idle (CustomPaint) e blob Lottie attivo.
class SiriOrbSwitcher extends StatelessWidget {
  const SiriOrbSwitcher({
    super.key,
    required this.isActive,
    required this.isRecording,
    required this.audioLevel,
    required this.isDark,
    required this.size,
    required this.idleChild,
  });

  final bool isActive;
  final bool isRecording;
  final double audioLevel;
  final bool isDark;
  final double size;
  final Widget idleChild;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: DropMotion.medium,
      reverseDuration: DropMotion.fast,
      switchInCurve: DropMotion.spring,
      switchOutCurve: DropMotion.exit,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: DropMotion.spring,
          reverseCurve: DropMotion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.55, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      child: isActive
          ? SiriLottieOrb(
              key: const ValueKey('siri_lottie_orb'),
              size: size,
              audioLevel: audioLevel,
              isAnimating: isRecording,
              isDark: isDark,
            )
          : KeyedSubtree(
              key: const ValueKey('siri_idle_orb'),
              child: idleChild,
            ),
    );
  }
}

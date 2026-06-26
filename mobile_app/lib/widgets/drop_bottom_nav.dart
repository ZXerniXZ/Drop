import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/record_orb_style.dart';
import '../theme/drop_gradients.dart';
import '../theme/drop_motion.dart';
import '../theme/drop_theme.dart';
import 'siri_lottie_orb.dart';

enum DropNavTab { file, settings }

class DropBottomNav extends StatelessWidget {
  const DropBottomNav({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
    required this.onStartRecording,
    required this.onPauseResume,
    required this.onFinishRecording,
    required this.onCancelRecording,
    required this.isRecording,
    required this.isPaused,
    required this.amplitudeLevel,
    this.elapsedLabel,
    this.orbStyle = RecordOrbStyle.gradientFluid,
    this.onOrbPreview,
  });

  final DropNavTab activeTab;
  final ValueChanged<DropNavTab> onTabChanged;
  final VoidCallback onStartRecording;
  final VoidCallback onPauseResume;
  final VoidCallback onFinishRecording;
  final VoidCallback onCancelRecording;
  final bool isRecording;
  final bool isPaused;
  final double amplitudeLevel;
  final String? elapsedLabel;
  final RecordOrbStyle orbStyle;
  final VoidCallback? onOrbPreview;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final recordingActive = isRecording || isPaused;

    return Container(
      decoration: BoxDecoration(
        color: (isDark ? DropColors.darkBackground : DropColors.lightScaffold)
            .withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: DropColors.border(context))),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AnimatedOpacity(
            duration: DropMotion.medium,
            opacity: recordingActive ? 0.25 : 1,
            child: IgnorePointer(
              ignoring: recordingActive,
              child: _NavItem(
                icon: Icons.folder_outlined,
                label: 'File',
                isActive: activeTab == DropNavTab.file,
                onTap: () => onTabChanged(DropNavTab.file),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -20),
            child: _RecordingControlCluster(
              isRecording: isRecording,
              isPaused: isPaused,
              elapsedLabel: elapsedLabel,
              amplitudeLevel: amplitudeLevel,
              orbStyle: orbStyle,
              onStart: onStartRecording,
              onPauseResume: onPauseResume,
              onFinish: onFinishRecording,
              onCancel: onCancelRecording,
              onLongPress: onOrbPreview,
            ),
          ),
          AnimatedOpacity(
            duration: DropMotion.medium,
            opacity: recordingActive ? 0.25 : 1,
            child: IgnorePointer(
              ignoring: recordingActive,
              child: _NavItem(
                icon: Icons.person_outline,
                label: 'My data',
                isActive: activeTab == DropNavTab.settings,
                onTap: () => onTabChanged(DropNavTab.settings),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive
        ? Theme.of(context).colorScheme.onSurface
        : DropColors.muted(context);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: DropMotion.fast,
        curve: DropMotion.standard,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: widget.isActive ? 1.05 : 1.0,
                duration: DropMotion.medium,
                curve: DropMotion.spring,
                child: Icon(widget.icon, size: 20, color: color),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: DropMotion.medium,
                curve: DropMotion.standard,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: color,
                      fontSize: 10,
                      fontWeight:
                          widget.isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                child: Text(widget.label),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: DropMotion.medium,
                curve: DropMotion.standard,
                width: widget.isActive ? 20 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordingControlCluster extends StatefulWidget {
  const _RecordingControlCluster({
    required this.isRecording,
    required this.isPaused,
    required this.amplitudeLevel,
    this.elapsedLabel,
    required this.onPauseResume,
    required this.onFinish,
    required this.onCancel,
    required this.orbStyle,
    required this.onStart,
    this.onLongPress,
  });

  final bool isRecording;
  final bool isPaused;
  final double amplitudeLevel;
  final String? elapsedLabel;
  final RecordOrbStyle orbStyle;
  final VoidCallback onStart;
  final VoidCallback onPauseResume;
  final VoidCallback onFinish;
  final VoidCallback onCancel;
  final VoidCallback? onLongPress;

  @override
  State<_RecordingControlCluster> createState() =>
      _RecordingControlClusterState();
}

class _RecordingControlClusterState extends State<_RecordingControlCluster>
    with TickerProviderStateMixin {
  final GlobalKey<SiriLottieOrbState> _orbKey = GlobalKey<SiriLottieOrbState>();
  late final AnimationController _expandController;
  late final AnimationController _breathController;
  late final Animation<double> _expand;
  late final Animation<double> _breath;
  double _displayAmp = 0;
  bool _orbPressed = false;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _expand = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _breath = CurvedAnimation(
      parent: _breathController,
      curve: Curves.easeInOutSine,
    );
    if (widget.isRecording || widget.isPaused) {
      _expandController.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _RecordingControlCluster oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = widget.isRecording || widget.isPaused;
    final wasActive = oldWidget.isRecording || oldWidget.isPaused;

    if (active && !wasActive) {
      _expandController.forward();
      if (widget.isRecording) {
        _orbKey.currentState?.setAudioLevel(widget.amplitudeLevel);
      }
    } else if (!active && wasActive) {
      _expandController.reverse();
    }

    if (!widget.isRecording && oldWidget.isRecording) {
      _displayAmp = 0;
      _orbKey.currentState?.setAudioLevel(0);
    } else if (widget.isRecording &&
        widget.amplitudeLevel != oldWidget.amplitudeLevel) {
      _orbKey.currentState?.setAudioLevel(widget.amplitudeLevel);
      _displayAmp += (widget.amplitudeLevel - _displayAmp) * 0.22;
    }
  }

  @override
  void dispose() {
    _expandController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.isRecording || widget.isPaused;

    return AnimatedBuilder(
      animation: active
          ? _expandController
          : Listenable.merge([_expandController, _breathController]),
      builder: (context, child) {
        final expand = _expand.value.clamp(0.0, 1.0);
        final breath = active ? 0.0 : _breath.value;
        if (widget.isRecording) {
          _displayAmp += (widget.amplitudeLevel - _displayAmp) * 0.28;
          _orbKey.currentState?.setAudioLevel(widget.amplitudeLevel);
        }
        final amp = widget.isRecording ? _displayAmp : 0.0;
        final orbShell = lerpDouble(68, 92, expand)!;
        final orbContent = lerpDouble(52, 60, expand)!;
        final satelliteSpan = lerpDouble(62, 76, expand)!;
        final glow = active
            ? DropGradients.chatGlow(0.7 + amp.clamp(0.0, 0.7) * 0.3)
            : const <BoxShadow>[];

        return SizedBox(
          width: orbShell + expand * 120,
          height: widget.elapsedLabel != null
              ? lerpDouble(88, 102, expand)!
              : lerpDouble(76, 92, expand)!,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              _SatelliteButton(
                expand: expand,
                offset: -satelliteSpan,
                icon: widget.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onPauseResume();
                },
              ),
              _SatelliteButton(
                expand: expand,
                offset: satelliteSpan,
                icon: Icons.close_rounded,
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onCancel();
                },
              ),
              GestureDetector(
                onTapDown: (_) => setState(() => _orbPressed = true),
                onTapUp: (_) => setState(() => _orbPressed = false),
                onTapCancel: () => setState(() => _orbPressed = false),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  if (active) {
                    widget.onFinish();
                  } else {
                    widget.onStart();
                  }
                },
                onLongPress: active ? null : widget.onLongPress,
                child: AnimatedScale(
                  scale: _orbPressed ? 0.94 : 1.0,
                  duration: DropMotion.fast,
                  child: Container(
                    width: orbShell,
                    height: orbShell,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: glow,
                    ),
                    child: Center(
                      child: SiriOrbMorph(
                        orbKey: _orbKey,
                        expand: expand,
                        isSessionActive: active,
                        breath: breath,
                        size: orbContent,
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.elapsedLabel != null && active)
                Positioned(
                  bottom: 0,
                  child: Opacity(
                    opacity: expand.clamp(0.0, 1.0),
                    child: Text(
                      widget.elapsedLabel!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                            color: widget.isPaused
                                ? DropColors.muted(context)
                                : DropGradients.chat[1],
                          ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SatelliteButton extends StatelessWidget {
  const _SatelliteButton({
    required this.expand,
    required this.offset,
    required this.icon,
    required this.onTap,
  });

  final double expand;
  final double offset;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = expand.clamp(0.0, 1.0);
    final dx = offset * t;
    final scale = 0.5 + t * 0.5;
    final color = Theme.of(context).colorScheme.onSurface;

    return Positioned(
      child: Transform.translate(
        offset: Offset(dx, 0),
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: t,
            child: GestureDetector(
              onTap: t > 0.8 ? onTap : null,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(icon, size: 28, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

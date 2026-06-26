import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/record_orb_style.dart';
import '../theme/drop_gradients.dart';
import '../theme/drop_motion.dart';
import '../theme/drop_theme.dart';
import 'siri_record_orb.dart';

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
  late final AnimationController _expandController;
  late final AnimationController _breathController;
  late final AnimationController _waveController;
  late final Animation<double> _expand;
  late final Animation<double> _breath;
  double _displayAmp = 0;
  bool _orbPressed = false;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _expand = CurvedAnimation(
      parent: _expandController,
      curve: DropMotion.spring,
      reverseCurve: DropMotion.exit,
    );
    _breath = CurvedAnimation(
      parent: _breathController,
      curve: Curves.easeInOutSine,
    );
    if (widget.isRecording || widget.isPaused) {
      _expandController.value = 1;
      if (widget.isRecording) _waveController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RecordingControlCluster oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = widget.isRecording || widget.isPaused;
    final wasActive = oldWidget.isRecording || oldWidget.isPaused;

    if (active && !wasActive) {
      _expandController.forward();
    } else if (!active && wasActive) {
      _expandController.reverse();
    }

    if (widget.isRecording && !oldWidget.isRecording) {
      _waveController.repeat();
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _waveController.stop();
      _waveController.reset();
      _displayAmp = 0;
    }
  }

  @override
  void dispose() {
    _expandController.dispose();
    _breathController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = widget.isRecording || widget.isPaused;

    return AnimatedBuilder(
      animation: Listenable.merge([
        _expandController,
        _breathController,
        _waveController,
      ]),
      builder: (context, child) {
        _displayAmp += (widget.amplitudeLevel - _displayAmp) * 0.22;
        final expand = _expand.value;
        final breath = _breath.value;
        final phase = _waveController.value;
        final amp = widget.isRecording ? _displayAmp : 0.0;
        final glow = DropGradients.chatGlow(
          active ? 0.7 + amp * 0.3 : 0.35 + breath * 0.2,
          pulse: breath * 0.4,
        );

        return SizedBox(
          width: 64 + expand * 120,
          height: widget.elapsedLabel != null ? 84 : 72,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              _SatelliteButton(
                expand: expand,
                offset: -58,
                icon: widget.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                label: widget.isPaused ? 'Riprendi' : 'Pausa',
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onPauseResume();
                },
                isDark: isDark,
              ),
              _SatelliteButton(
                expand: expand,
                offset: 58,
                icon: Icons.close_rounded,
                label: 'Annulla',
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onCancel();
                },
                isDark: isDark,
                isDestructive: true,
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
                  child: Transform.scale(
                    scale: widget.isRecording ? 1.0 + amp * 0.06 : 1.0,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: glow,
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: DropGradients.chatSweep(
                            rotation: phase,
                            intensity: active ? 0.9 : 0.5 + breath * 0.2,
                            isDark: isDark,
                          ),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? DropColors.darkSurface
                                : DropColors.lightSurface,
                          ),
                          child: Center(
                            child: SiriRecordOrb(
                              size: 48,
                              style: widget.orbStyle,
                              isRecording: widget.isRecording,
                              amplitude: amp,
                              phase: phase,
                              breath: breath,
                              isDark: isDark,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.elapsedLabel != null && active)
                Positioned(
                  bottom: 0,
                  child: Opacity(
                    opacity: expand,
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
    required this.label,
    required this.onTap,
    required this.isDark,
    this.isDestructive = false,
  });

  final double expand;
  final double offset;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final t = expand.clamp(0.0, 1.0);
    final dx = offset * t;
    final scale = 0.4 + t * 0.6;
    final accent =
        isDestructive ? DropColors.recordRed : Theme.of(context).colorScheme.onSurface;

    return Positioned(
      child: Transform.translate(
        offset: Offset(dx, 0),
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: t,
            child: GestureDetector(
              onTap: t > 0.8 ? onTap : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
                      border: Border.all(
                        color: isDestructive
                            ? DropColors.recordRed.withValues(alpha: 0.45)
                            : DropColors.border(context),
                        width: isDestructive ? 1.5 : 1,
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/record_orb_style.dart';
import '../theme/drop_motion.dart';
import '../theme/drop_theme.dart';
import 'siri_record_orb.dart';

enum DropNavTab { file, settings }

class DropBottomNav extends StatelessWidget {
  const DropBottomNav({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
    required this.onRecordTap,
    required this.isRecording,
    required this.amplitudeLevel,
    this.orbStyle = RecordOrbStyle.radialBars,
    this.onOrbPreview,
  });

  final DropNavTab activeTab;
  final ValueChanged<DropNavTab> onTabChanged;
  final VoidCallback onRecordTap;
  final bool isRecording;
  final double amplitudeLevel;
  final RecordOrbStyle orbStyle;
  final VoidCallback? onOrbPreview;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          _NavItem(
            icon: Icons.folder_outlined,
            label: 'File',
            isActive: activeTab == DropNavTab.file,
            onTap: () => onTabChanged(DropNavTab.file),
          ),
          Transform.translate(
            offset: const Offset(0, -20),
            child: _RecordButton(
              isRecording: isRecording,
              amplitudeLevel: amplitudeLevel,
              orbStyle: orbStyle,
              onTap: onRecordTap,
              onLongPress: onOrbPreview,
            ),
          ),
          _NavItem(
            icon: Icons.person_outline,
            label: 'My data',
            isActive: activeTab == DropNavTab.settings,
            onTap: () => onTabChanged(DropNavTab.settings),
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

class _RecordButton extends StatefulWidget {
  const _RecordButton({
    required this.isRecording,
    required this.amplitudeLevel,
    required this.orbStyle,
    required this.onTap,
    this.onLongPress,
  });

  final bool isRecording;
  final double amplitudeLevel;
  final RecordOrbStyle orbStyle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with TickerProviderStateMixin {
  late final AnimationController _breathController;
  late final AnimationController _waveController;
  late final Animation<double> _breath;
  double _displayAmp = 0;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _breath = CurvedAnimation(
      parent: _breathController,
      curve: Curves.easeInOutSine,
    );
  }

  @override
  void didUpdateWidget(covariant _RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _breathController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.mediumImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: _handleTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: DropMotion.fast,
        curve: DropMotion.standard,
        child: AnimatedBuilder(
          animation: Listenable.merge([_breathController, _waveController]),
          builder: (context, child) {
            _displayAmp += (widget.amplitudeLevel - _displayAmp) * 0.22;

            final recordingScale =
                widget.isRecording ? 1.0 + _displayAmp * 0.06 : 1.0;
            final glowOpacity = widget.isRecording
                ? 0.12 + _displayAmp * 0.4
                : 0.06 + _breath.value * 0.08;

            return Transform.scale(
              scale: recordingScale,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
                  border: Border.all(
                    color: widget.isRecording
                        ? DropColors.recordRed
                            .withValues(alpha: 0.35 + _displayAmp * 0.5)
                        : DropColors.border(context),
                    width: widget.isRecording ? 1.5 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: DropColors.recordRed.withValues(alpha: glowOpacity),
                      blurRadius: widget.isRecording ? 22 + _displayAmp * 16 : 14,
                      spreadRadius: widget.isRecording ? _displayAmp * 3 : 0,
                    ),
                  ],
                ),
                child: Center(
                  child: SiriRecordOrb(
                    size: 52,
                    style: widget.orbStyle,
                    isRecording: widget.isRecording,
                    amplitude: _displayAmp,
                    phase: _waveController.value,
                    breath: _breath.value,
                    isDark: isDark,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/drop_theme.dart';

enum DropNavTab { file, settings }

class DropBottomNav extends StatelessWidget {
  const DropBottomNav({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
    required this.onRecordTap,
    required this.isRecording,
    required this.amplitudeLevel,
  });

  final DropNavTab activeTab;
  final ValueChanged<DropNavTab> onTabChanged;
  final VoidCallback onRecordTap;
  final bool isRecording;
  final double amplitudeLevel;

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
              onTap: onRecordTap,
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

class _NavItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final color = isActive
        ? Theme.of(context).colorScheme.onSurface
        : DropColors.muted(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isActive ? 20 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordButton extends StatefulWidget {
  const _RecordButton({
    required this.isRecording,
    required this.amplitudeLevel,
    required this.onTap,
  });

  final bool isRecording;
  final double amplitudeLevel;
  final VoidCallback onTap;

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idlePulse;

  @override
  void initState() {
    super.initState();
    _idlePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _idlePulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amp = widget.amplitudeLevel.clamp(0.0, 1.0);
    final outerScale = widget.isRecording ? 1.0 + amp * 0.35 : 1.0;
    final innerSize = widget.isRecording ? 16.0 + amp * 20 : 16.0;
    final glowOpacity = widget.isRecording ? 0.15 + amp * 0.45 : 0.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: Transform.scale(
        scale: outerScale,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
            border: Border.all(
              color: widget.isRecording
                  ? DropColors.recordRed.withValues(alpha: 0.4 + amp * 0.6)
                  : DropColors.border(context),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              if (widget.isRecording)
                BoxShadow(
                  color: DropColors.recordRed.withValues(alpha: glowOpacity),
                  blurRadius: 16 + amp * 12,
                  spreadRadius: amp * 4,
                ),
            ],
          ),
          child: Center(
            child: widget.isRecording
                ? AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: innerSize,
                    height: innerSize,
                    decoration: BoxDecoration(
                      color: DropColors.recordRed,
                      shape: BoxShape.circle,
                      borderRadius: BorderRadius.circular(4 + amp * 8),
                    ),
                  )
                : FadeTransition(
                    opacity: Tween(begin: 0.6, end: 1.0).animate(_idlePulse),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: DropColors.recordRed,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

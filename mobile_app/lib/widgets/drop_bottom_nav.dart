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
    required this.isBusy,
  });

  final DropNavTab activeTab;
  final ValueChanged<DropNavTab> onTabChanged;
  final VoidCallback onRecordTap;
  final bool isRecording;
  final bool isBusy;

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
              isBusy: isBusy,
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
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
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
    required this.isBusy,
    required this.onTap,
  });

  final bool isRecording;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabled = widget.isBusy && !widget.isRecording;

    return GestureDetector(
      onTap: disabled ? null : widget.onTap,
      child: AnimatedOpacity(
        opacity: disabled ? 0.4 : 1,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
            border: Border.all(
              color: DropColors.border(context),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: widget.isRecording
                ? const Icon(
                    Icons.stop_rounded,
                    color: DropColors.recordRed,
                    size: 28,
                  )
                : FadeTransition(
                    opacity: Tween(begin: 0.6, end: 1.0).animate(_pulse),
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

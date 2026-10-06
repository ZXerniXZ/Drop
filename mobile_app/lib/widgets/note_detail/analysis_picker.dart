import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/note_structured_data.dart';
import '../../theme/drop_theme.dart';

class AnalysisPicker extends StatefulWidget {
  const AnalysisPicker({
    super.key,
    required this.data,
    required this.running,
    required this.onSelect,
    required this.onRegenerate,
    required this.onDelete,
  });

  final NoteStructuredData data;
  final Set<String> running;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRegenerate;
  final ValueChanged<String> onDelete;

  @override
  State<AnalysisPicker> createState() => _AnalysisPickerState();
}

class _Mark {
  const _Mark({
    required this.kind,
    required this.label,
    required this.size,
    required this.ax,
    required this.ay,
    required this.phase,
  });

  final String kind;
  final String label;
  final double size;
  final double ax;
  final double ay;
  final double phase;
}

const _marks = <_Mark>[
  _Mark(
    kind: NoteStructuredData.mindMapKind,
    label: 'Mind map',
    size: 128,
    ax: 0.26,
    ay: 0.20,
    phase: 0.2,
  ),
  _Mark(
    kind: NoteStructuredData.highlightsKind,
    label: 'Highlights',
    size: 136,
    ax: 0.74,
    ay: 0.26,
    phase: 1.1,
  ),
  _Mark(
    kind: NoteStructuredData.speakersKind,
    label: 'Speakers',
    size: 148,
    ax: 0.28,
    ay: 0.72,
    phase: 2.2,
  ),
  _Mark(
    kind: NoteStructuredData.keyDataKind,
    label: 'Key data',
    size: 124,
    ax: 0.76,
    ay: 0.74,
    phase: 3.1,
  ),
];

class _AnalysisPickerState extends State<AnalysisPicker>
    with TickerProviderStateMixin {
  late final AnimationController _drift;
  late final AnimationController _drop;
  String? _menuKind;
  bool _closingMenu = false;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();
    _drop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _drop.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _closingMenu && mounted) {
        setState(() {
          _closingMenu = false;
          _menuKind = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _drift.dispose();
    _drop.dispose();
    super.dispose();
  }

  void _openMenu(String kind) {
    HapticFeedback.mediumImpact();
    _closingMenu = false;
    setState(() => _menuKind = kind);
    _drop.forward(from: 0);
  }

  void _closeMenu() {
    if (_menuKind == null || _closingMenu) return;
    _closingMenu = true;
    _drop.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return AnimatedBuilder(
          animation: Listenable.merge([_drift, _drop]),
          builder: (context, _) {
            final t = _drift.value * math.pi * 2;
            final marks = [
              for (final mark in _marks)
                if (mark.kind != _menuKind) mark,
              if (_menuKind != null)
                for (final mark in _marks)
                  if (mark.kind == _menuKind) mark,
            ];
            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (_menuKind != null)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _closeMenu,
                      behavior: HitTestBehavior.translucent,
                    ),
                  ),
                for (final mark in marks)
                  _placed(
                    mark: mark,
                    t: t,
                    width: width,
                    height: height,
                    isDark: isDark,
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _placed({
    required _Mark mark,
    required double t,
    required double width,
    required double height,
    required bool isDark,
  }) {
    final dx = math.sin(t + mark.phase) * 16;
    final dy = math.cos(t * 0.82 + mark.phase) * 18;
    final menuOpen = _menuKind == mark.kind;
    final dropHeight = _dropExtent(menuOpen);
    final columnHeight = mark.size + 36 + dropHeight;
    final left = (mark.ax * width - mark.size / 2 + dx)
        .clamp(16.0, math.max(16.0, width - mark.size - 16))
        .toDouble();
    final top = (mark.ay * height - (mark.size + 36) / 2 + dy)
        .clamp(8.0, math.max(8.0, height - columnHeight - 8))
        .toDouble();
    final ready = widget.data.isReady(mark.kind);
    final running = widget.running.contains(mark.kind);

    return Positioned(
      left: left,
      top: top,
      width: mark.size,
      child: GestureDetector(
        onTap: () {
          if (_menuKind != null) {
            final same = _menuKind == mark.kind;
            _closeMenu();
            if (same) return;
          }
          HapticFeedback.selectionClick();
          widget.onSelect(mark.kind);
        },
        onLongPress: ready && !running ? () => _openMenu(mark.kind) : null,
        child: Column(
          children: [
            SizedBox(
              width: mark.size,
              height: mark.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: mark.size,
                    height: mark.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ready
                          ? (isDark
                              ? DropColors.darkSurface
                              : DropColors.lightSurface)
                          : Colors.transparent,
                      border: Border.all(
                        color: ready
                            ? DropColors.border(context)
                            : DropColors.muted(context).withValues(alpha: 0.35),
                      ),
                      boxShadow: ready
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.28 : 0.05,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : null,
                    ),
                      child: ClipOval(
                        child: Opacity(
                          opacity: ready ? 1 : 0.55,
                          child: Image.asset(
                            'assets/analyses/${mark.kind}_${isDark ? 'dark' : 'light'}.jpg',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              _fallbackIcon(mark.kind),
                              size: mark.size * 0.34,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                  ),
                  if (running)
                    SizedBox(
                      width: mark.size,
                      height: mark.size,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                ],
              ),
            ),
            if (menuOpen)
              _DropletMenu(
                animation: _drop,
                width: mark.size,
                isDark: isDark,
                onRegenerate: () {
                  _closeMenu();
                  widget.onRegenerate(mark.kind);
                },
                onDelete: () {
                  _closeMenu();
                  widget.onDelete(mark.kind);
                },
              )
            else
              const SizedBox(height: 10),
            Text(
              mark.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: ready
                        ? Theme.of(context).colorScheme.onSurface
                        : DropColors.muted(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _fallbackIcon(String kind) {
    return switch (kind) {
      NoteStructuredData.mindMapKind => Icons.account_tree_outlined,
      NoteStructuredData.speakersKind => Icons.record_voice_over_outlined,
      NoteStructuredData.keyDataKind => Icons.grid_view_rounded,
      _ => Icons.checklist_rounded,
    };
  }

  double _dropExtent(bool open) {
    if (!open) return 0;
    final t = Curves.easeOutBack.transform(_drop.value).clamp(0.0, 1.0);
    return t * _dropSlot;
  }
}

const _dropSlot = 102.0;

class _DropletMenu extends StatelessWidget {
  const _DropletMenu({
    required this.animation,
    required this.width,
    required this.isDark,
    required this.onRegenerate,
    required this.onDelete,
  });

  final Animation<double> animation;
  final double width;
  final bool isDark;
  final VoidCallback onRegenerate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeOutBack.transform(animation.value).clamp(0.0, 1.0);
    final height = t * _dropSlot;
    final bead = lerpDouble(16, width - 6, t)!;
    final surface = isDark ? DropColors.darkSurface : DropColors.lightSurface;
    final inner = math.max(0.0, height - 8);
    final showLabels = inner >= 80;

    return SizedBox(
      height: height,
      width: width,
      child: Align(
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: lerpDouble(6, 12, t),
              height: lerpDouble(0, 8, t),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(6),
                ),
              ),
            ),
            Container(
              width: bead,
              height: math.max(0, height - 8),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(lerpDouble(20, 18, t)!),
                border: Border.all(color: DropColors.border(context)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: showLabels
                  ? Column(
                      children: [
                        _DropAction(label: 'Rigenera', onTap: onRegenerate),
                        Container(
                          height: 1,
                          color: DropColors.border(context),
                        ),
                        _DropAction(
                          label: 'Elimina',
                          onTap: onDelete,
                          danger: true,
                        ),
                      ],
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _DropAction extends StatelessWidget {
  const _DropAction({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 36,
        width: double.infinity,
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                  color: danger
                      ? DropColors.recordRed
                      : Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ),
      ),
    );
  }
}

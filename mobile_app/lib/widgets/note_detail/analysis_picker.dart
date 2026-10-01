import 'dart:math' as math;

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
  });

  final NoteStructuredData data;
  final Set<String> running;
  final ValueChanged<String> onSelect;

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
    kind: NoteStructuredData.highlightsKind,
    label: 'Highlights',
    size: 156,
    ax: 0.30,
    ay: 0.24,
    phase: 0.4,
  ),
  _Mark(
    kind: NoteStructuredData.speakersKind,
    label: 'Speakers',
    size: 176,
    ax: 0.70,
    ay: 0.46,
    phase: 1.7,
  ),
  _Mark(
    kind: NoteStructuredData.keyDataKind,
    label: 'Key data',
    size: 140,
    ax: 0.36,
    ay: 0.74,
    phase: 2.8,
  ),
];

class _AnalysisPickerState extends State<AnalysisPicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return AnimatedBuilder(
          animation: _drift,
          builder: (context, _) {
            final t = _drift.value * math.pi * 2;
            return Stack(
              children: [
                for (final mark in _marks)
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
    final columnHeight = mark.size + 36;
    final left = (mark.ax * width - mark.size / 2 + dx)
        .clamp(16.0, math.max(16.0, width - mark.size - 16))
        .toDouble();
    final top = (mark.ay * height - columnHeight / 2 + dy)
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
          HapticFeedback.selectionClick();
          widget.onSelect(mark.kind);
        },
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
      NoteStructuredData.speakersKind => Icons.record_voice_over_outlined,
      NoteStructuredData.keyDataKind => Icons.grid_view_rounded,
      _ => Icons.checklist_rounded,
    };
  }
}

import 'package:flutter/material.dart';

import '../theme/drop_motion.dart';
import '../theme/drop_theme.dart';

class RecordingBanner extends StatefulWidget {
  const RecordingBanner({
    super.key,
    required this.elapsedLabel,
    required this.onStop,
  });

  final String elapsedLabel;
  final VoidCallback onStop;

  @override
  State<RecordingBanner> createState() => _RecordingBannerState();
}

class _RecordingBannerState extends State<RecordingBanner>
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
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: DropMotion.medium,
      curve: DropMotion.enter,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * -8),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: DropColors.recordRed.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: DropColors.recordRed.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                return Container(
                  width: 8 + _pulse.value * 2,
                  height: 8 + _pulse.value * 2,
                  decoration: BoxDecoration(
                    color: DropColors.recordRed
                        .withValues(alpha: 0.7 + _pulse.value * 0.3),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: DropColors.recordRed
                            .withValues(alpha: 0.25 + _pulse.value * 0.2),
                        blurRadius: 6 + _pulse.value * 4,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REGISTRAZIONE IN CORSO',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: DropColors.recordRed,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedSwitcher(
                    duration: DropMotion.fast,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                    child: Text(
                      widget.elapsedLabel,
                      key: ValueKey(widget.elapsedLabel),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: widget.onStop,
              child: const Text(
                'STOP',
                style: TextStyle(
                  color: DropColors.recordRed,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

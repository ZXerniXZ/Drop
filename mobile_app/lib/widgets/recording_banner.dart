import 'package:flutter/material.dart';

import '../theme/drop_theme.dart';

class RecordingBanner extends StatelessWidget {
  const RecordingBanner({
    super.key,
    required this.elapsedLabel,
    required this.onStop,
  });

  final String elapsedLabel;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: DropColors.recordRed,
              shape: BoxShape.circle,
            ),
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
                Text(
                  elapsedLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onStop,
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
    );
  }
}

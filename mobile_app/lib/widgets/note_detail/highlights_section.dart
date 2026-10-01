import 'package:flutter/material.dart';

import '../../theme/drop_theme.dart';

class HighlightsSection extends StatelessWidget {
  const HighlightsSection({
    super.key,
    required this.highlights,
    required this.checked,
    required this.onToggle,
  });

  final List<String> highlights;
  final List<String> checked;
  final void Function(String text, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    if (highlights.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final text in highlights)
          _HighlightRow(
            text: text,
            checked: checked.contains(text),
            onToggle: (value) => onToggle(text, value),
          ),
      ],
    );
  }
}

class _HighlightRow extends StatelessWidget {
  const _HighlightRow({
    required this.text,
    required this.checked,
    required this.onToggle,
  });

  final String text;
  final bool checked;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => onToggle(!checked),
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: checked ? ink : DropColors.border(context),
                ),
                color: checked ? ink : Colors.transparent,
              ),
              child: checked
                  ? Icon(
                      Icons.check,
                      size: 14,
                      color: Theme.of(context).colorScheme.surface,
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                      decoration: checked ? TextDecoration.lineThrough : null,
                      decorationColor: DropColors.muted(context),
                      color: checked
                          ? DropColors.muted(context)
                          : ink.withValues(alpha: 0.92),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

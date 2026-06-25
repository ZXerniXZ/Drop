import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/drop_theme.dart';

class DropMarkdown extends StatelessWidget {
  const DropMarkdown({
    super.key,
    required this.data,
    this.fontSize = 14,
    this.textColor,
  });

  final String data;
  final double fontSize;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    if (data.trim().isEmpty) return const SizedBox.shrink();

    final color = textColor ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9);
    final muted = DropColors.muted(context);

    return MarkdownBody(
      data: data,
      shrinkWrap: true,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: fontSize, height: 1.45, color: color),
        h1: TextStyle(
          fontSize: fontSize + 4,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        h2: TextStyle(
          fontSize: fontSize + 2,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        h3: TextStyle(
          fontSize: fontSize + 1,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        listBullet: TextStyle(fontSize: fontSize, color: color),
        strong: TextStyle(fontWeight: FontWeight.w600, color: color),
        em: TextStyle(fontStyle: FontStyle.italic, color: color),
        blockquote: TextStyle(
          fontSize: fontSize,
          color: muted,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: muted.withValues(alpha: 0.4), width: 2),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeFill = isDark ? const Color(0xFF141416) : const Color(0xFFF3F3F4);

    return MarkdownBody(
      data: data,
      shrinkWrap: true,
      selectable: true,
      builders: {
        'pre': _FencedCodeBuilder(
          color: color,
          muted: muted,
          fill: codeFill,
          border: DropColors.border(context),
          fontSize: fontSize,
        ),
      },
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
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize - 1,
          height: 1.45,
          color: color,
          backgroundColor: codeFill,
        ),
      ),
    );
  }
}

class _FencedCodeBuilder extends MarkdownElementBuilder {
  _FencedCodeBuilder({
    required this.color,
    required this.muted,
    required this.fill,
    required this.border,
    required this.fontSize,
  });

  final Color color;
  final Color muted;
  final Color fill;
  final Color border;
  final double fontSize;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent.replaceAll(RegExp(r'\n$'), '');
    final language = _language(element);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (language != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                language,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  color: muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Text(
              code,
              softWrap: false,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: fontSize - 1,
                height: 1.45,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _language(md.Element element) {
    final fromSelf = _langFromClass(element.attributes['class']);
    if (fromSelf != null) return fromSelf;
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        final fromCode = _langFromClass(child.attributes['class']);
        if (fromCode != null) return fromCode;
      }
    }
    return null;
  }

  String? _langFromClass(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final part in value.split(' ')) {
      if (part.startsWith('language-') && part.length > 9) {
        return part.substring(9);
      }
    }
    return null;
  }
}

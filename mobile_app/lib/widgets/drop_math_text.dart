import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../theme/drop_theme.dart';

/// Prose with inline `$...$` and display `$$...$$` math.
class DropMathText extends StatelessWidget {
  const DropMathText({
    super.key,
    required this.data,
    this.fontSize = 15,
  });

  final String data;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final trimmed = data.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9);
    final style = TextStyle(fontSize: fontSize, height: 1.45, color: color);
    final blocks = _blocks(trimmed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          if (blocks[i].display)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _Formula(expression: blocks[i].text, style: style),
            )
          else
            Text.rich(_inlineSpan(blocks[i].text, style)),
        ],
      ],
    );
  }

  TextSpan _inlineSpan(String text, TextStyle style) {
    final pattern = RegExp(
      r'\\\((.+?)\\\)|(?<!\$)\$(?!\$)([^\$\n]+?)\$(?!\$)',
    );
    final children = <InlineSpan>[];
    var start = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > start) {
        children.add(TextSpan(text: text.substring(start, match.start)));
      }
      final expression = (match.group(1) ?? match.group(2) ?? '').trim();
      children.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _Formula(
            expression: expression,
            style: style,
            inline: true,
          ),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      children.add(TextSpan(text: text.substring(start)));
    }
    return TextSpan(style: style, children: children);
  }

  List<_Block> _blocks(String text) {
    final pattern = RegExp(r'\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]');
    final blocks = <_Block>[];
    var start = 0;
    for (final match in pattern.allMatches(text)) {
      final before = text.substring(start, match.start).trim();
      if (before.isNotEmpty) blocks.add(_Block(before));
      final expression = (match.group(1) ?? match.group(2) ?? '').trim();
      if (expression.isNotEmpty) {
        blocks.add(_Block(expression, display: true));
      }
      start = match.end;
    }
    final tail = text.substring(start).trim();
    if (tail.isNotEmpty) blocks.add(_Block(tail));
    return blocks;
  }
}

class _Block {
  const _Block(this.text, {this.display = false});

  final String text;
  final bool display;
}

class _Formula extends StatelessWidget {
  const _Formula({
    required this.expression,
    required this.style,
    this.inline = false,
  });

  final String expression;
  final TextStyle style;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    return Math.tex(
      expression,
      mathStyle: inline ? MathStyle.text : MathStyle.display,
      textStyle: style,
      onErrorFallback: (error) => Text(
        expression,
        style: style.copyWith(
          fontFamily: 'monospace',
          color: DropColors.muted(context),
        ),
      ),
    );
  }
}

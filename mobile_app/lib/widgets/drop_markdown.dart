import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/drop_theme.dart';
import 'chat_plot.dart';

/// Turns `$...$`, `$$...$$`, `\(...\)` and `\[...\]` into markers the markdown
/// parser will not treat as emphasis, and leaves fenced code untouched.
String prepareDropMarkdown(String input) {
  if (input.isEmpty) return input;
  final out = StringBuffer();
  var index = 0;
  final fence = RegExp(r'```[^\n]*\n[\s\S]*?(?:```|$)');
  for (final match in fence.allMatches(input)) {
    if (match.start > index) {
      out.write(_shieldPlain(input.substring(index, match.start)));
    }
    out.write(match.group(0));
    index = match.end;
  }
  if (index < input.length) {
    out.write(_shieldPlain(input.substring(index)));
  }
  return out.toString();
}

String _shieldPlain(String input) {
  final out = StringBuffer();
  var index = 0;
  final code = RegExp(r'`+[^`]*`+');
  for (final match in code.allMatches(input)) {
    if (match.start > index) {
      out.write(_shieldMath(input.substring(index, match.start)));
    }
    out.write(match.group(0));
    index = match.end;
  }
  if (index < input.length) {
    out.write(_shieldMath(input.substring(index)));
  }
  return out.toString();
}

String _shieldMath(String input) {
  final out = StringBuffer();
  var i = 0;
  while (i < input.length) {
    if (input.startsWith(r'$$', i)) {
      final end = input.indexOf(r'$$', i + 2);
      if (end == -1) {
        out.write(input.substring(i));
        break;
      }
      out.write(_displayFence(input.substring(i + 2, end)));
      i = end + 2;
      continue;
    }
    if (input.startsWith(r'\[', i)) {
      final end = input.indexOf(r'\]', i + 2);
      if (end == -1) {
        out.write(input.substring(i));
        break;
      }
      out.write(_displayFence(input.substring(i + 2, end)));
      i = end + 2;
      continue;
    }
    if (input.startsWith(r'\(', i)) {
      final end = input.indexOf(r'\)', i + 2);
      if (end != -1 && !input.substring(i + 2, end).contains('\n')) {
        out.write(_inlineMath(input.substring(i + 2, end)));
        i = end + 2;
        continue;
      }
    }
    if (input.codeUnitAt(i) == 0x24 && !_isEscaped(input, i)) {
      final close = _closingDollar(input, i + 1);
      if (close != -1) {
        out.write(_inlineMath(input.substring(i + 1, close)));
        i = close + 1;
        continue;
      }
    }
    out.write(input[i]);
    i++;
  }
  return out.toString();
}

bool _isEscaped(String input, int index) {
  return index > 0 && input[index - 1] == r'\';
}

bool _isSpace(String char) {
  return char == ' ' || char == '\t';
}

int _closingDollar(String input, int start) {
  if (start >= input.length) return -1;
  final first = input[start];
  if (first == r'$' || _isSpace(first)) return -1;
  for (var j = start + 1; j < input.length; j++) {
    final char = input[j];
    if (char == '\n') return -1;
    if (char == r'$' && !_isEscaped(input, j)) {
      if (j + 1 < input.length && input[j + 1] == r'$') return -1;
      if (_isSpace(input[j - 1])) return -1;
      return j;
    }
  }
  return -1;
}

String _displayFence(String tex) {
  final body = tex.trim();
  if (body.isEmpty) return '';
  return '\n```drop-math\n$body\n```\n';
}

String _inlineMath(String tex) {
  final body = tex.trim();
  if (body.isEmpty) return '';
  final encoded = base64Url.encode(utf8.encode(body));
  return '`dropmath:$encoded`';
}

String? _decodeDropMath(String code) {
  const prefix = 'dropmath:';
  if (!code.startsWith(prefix)) return null;
  try {
    return utf8.decode(base64Url.decode(code.substring(prefix.length)));
  } catch (_) {
    return null;
  }
}

class DropMarkdown extends StatelessWidget {
  const DropMarkdown({
    super.key,
    required this.data,
    this.fontSize = 14,
    this.textColor,
    this.renderVisuals = true,
  });

  final String data;
  final double fontSize;
  final Color? textColor;
  final bool renderVisuals;

  @override
  Widget build(BuildContext context) {
    if (data.trim().isEmpty) return const SizedBox.shrink();

    final color =
        textColor ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9);
    final muted = DropColors.muted(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeFill = isDark ? const Color(0xFF141416) : const Color(0xFFF3F3F4);
    final border = DropColors.border(context);

    return MarkdownBody(
      data: prepareDropMarkdown(data),
      shrinkWrap: true,
      selectable: true,
      builders: {
        'pre': _FencedCodeBuilder(
          color: color,
          muted: muted,
          fill: codeFill,
          border: border,
          fontSize: fontSize,
          renderVisuals: renderVisuals,
        ),
        'code': _InlineMathBuilder(color: color, fontSize: fontSize),
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

class _InlineMathBuilder extends MarkdownElementBuilder {
  _InlineMathBuilder({required this.color, required this.fontSize});

  final Color color;
  final double fontSize;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final tex = _decodeDropMath(element.textContent);
    if (tex == null || tex.isEmpty) return null;
    return _TeX(tex: tex, color: color, fontSize: fontSize, display: false);
  }
}

class _FencedCodeBuilder extends MarkdownElementBuilder {
  _FencedCodeBuilder({
    required this.color,
    required this.muted,
    required this.fill,
    required this.border,
    required this.fontSize,
    required this.renderVisuals,
  });

  final Color color;
  final Color muted;
  final Color fill;
  final Color border;
  final double fontSize;
  final bool renderVisuals;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent.replaceAll(RegExp(r'\n$'), '');
    final language = _language(element);
    if (language == 'drop-math') {
      final tex = code.trim();
      if (tex.isEmpty) return const SizedBox.shrink();
      return _TeX(
        tex: tex,
        color: color,
        fontSize: fontSize + 2,
        display: true,
      );
    }
    if (language == 'drop-visual') {
      final visual = _parseVisual(code);
      if (visual == null) {
        return _codeBlock(code, language);
      }
      if (!renderVisuals) {
        final title = visual['title'];
        final label = title is String && title.trim().isNotEmpty
            ? title.trim()
            : 'Grafico';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            label,
            style: TextStyle(fontSize: fontSize - 1, color: muted),
          ),
        );
      }
      return ChatPlot(visual: visual, fill: fill, border: border);
    }
    return _codeBlock(code, language);
  }

  Widget _codeBlock(String code, String? language) {
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
          if (language != null && language != 'drop-math')
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

  Map<String, dynamic>? _parseVisual(String code) {
    try {
      final decoded = jsonDecode(code.trim());
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
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

class _TeX extends StatelessWidget {
  const _TeX({
    required this.tex,
    required this.color,
    required this.fontSize,
    required this.display,
  });

  final String tex;
  final Color color;
  final double fontSize;
  final bool display;

  @override
  Widget build(BuildContext context) {
    final math = Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: TextStyle(fontSize: fontSize, color: color),
      onErrorFallback: (error) => Text(
        tex,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize - 1,
          color: color,
        ),
      ),
    );
    if (!display) return math;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: math,
    );
  }
}

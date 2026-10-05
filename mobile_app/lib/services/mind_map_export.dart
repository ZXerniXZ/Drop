import 'dart:convert';

import '../models/note_structured_data.dart';

String mindMapFileName(String title) {
  final cleaned = title.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '-');
  final name = cleaned.replaceAll(RegExp(r'^-+|-+$'), '');
  return '${name.isEmpty ? 'mappa' : name}.md';
}

/// Markdown ad albero: titoli per Markmap e Obsidian, elenchi per i livelli sotto.
String mindMapToMarkdown(String title, List<MindMapNode> nodes) {
  final buffer = StringBuffer('# ${_oneLine(title.isEmpty ? 'Mappa' : title)}\n\n');
  for (final node in nodes) {
    _writeHeading(buffer, node, 0);
  }
  return buffer.toString().trimRight();
}

void _writeHeading(StringBuffer buffer, MindMapNode node, int depth) {
  if (depth >= 2) {
    _writeList(buffer, node, 0);
    return;
  }
  buffer.writeln('${'#' * (depth + 2)} ${_oneLine(node.title)}');
  buffer.writeln();
  _writeBody(buffer, node, '');
  for (final child in node.children) {
    _writeHeading(buffer, child, depth + 1);
  }
}

void _writeList(StringBuffer buffer, MindMapNode node, int indent) {
  final pad = ' ' * indent;
  buffer.writeln('$pad- ${_oneLine(node.title)}');
  _writeBody(buffer, node, '$pad  ');
  for (final child in node.children) {
    _writeList(buffer, child, indent + 2);
  }
}

void _writeBody(StringBuffer buffer, MindMapNode node, String pad) {
  final body = node.body.trim();
  if (body.isNotEmpty) {
    for (final line in body.split('\n')) {
      buffer.writeln('$pad$line');
    }
    buffer.writeln();
  }
  for (final visual in node.visuals) {
    buffer.writeln('$pad```drop-visual');
    for (final line in const JsonEncoder.withIndent('  ').convert(visual).split('\n')) {
      buffer.writeln('$pad$line');
    }
    buffer.writeln('$pad```');
    buffer.writeln();
  }
}

String _oneLine(String text) {
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

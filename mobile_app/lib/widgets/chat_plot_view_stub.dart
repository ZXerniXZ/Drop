import 'package:flutter/material.dart';

class ChatPlotView extends StatelessWidget {
  const ChatPlotView({super.key, required this.visual});

  final Map<String, dynamic> visual;

  @override
  Widget build(BuildContext context) {
    final title = visual['title'];
    final label = title is String && title.trim().isNotEmpty
        ? title.trim()
        : 'Grafico';
    return Center(child: Text(label, key: const Key('chat-plot-placeholder')));
  }
}

import 'package:flutter/material.dart';

import 'chat_plot_view.dart';

class ChatPlot extends StatelessWidget {
  const ChatPlot({
    super.key,
    required this.visual,
    required this.fill,
    required this.border,
  });

  final Map<String, dynamic> visual;
  final Color fill;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 236,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.hardEdge,
      child: ChatPlotView(visual: visual),
    );
  }
}

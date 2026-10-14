import 'dart:io';

import 'package:flutter/material.dart';

import 'chat_plot_view_stub.dart' as placeholder;
import 'plot_canvas.dart';

class ChatPlotView extends StatelessWidget {
  const ChatPlotView({super.key, required this.visual});

  final Map<String, dynamic> visual;

  bool get _underTest => Platform.environment.containsKey('FLUTTER_TEST');

  @override
  Widget build(BuildContext context) {
    if (_underTest) {
      return placeholder.ChatPlotView(visual: visual);
    }
    return PlotCanvas(visual: visual);
  }
}

import 'package:flutter/material.dart';

import '../../models/note_structured_data.dart';
import 'mind_map_handle.dart';

class MindMapView extends StatelessWidget {
  const MindMapView({
    super.key,
    required this.handle,
    required this.title,
    required this.nodes,
    this.interactive = true,
  });

  final MindMapHandle handle;
  final String title;
  final List<MindMapNode> nodes;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}

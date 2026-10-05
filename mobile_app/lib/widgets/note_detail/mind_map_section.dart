import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/note_structured_data.dart';
import '../../theme/drop_theme.dart';
import '../drop_math_text.dart';

class MindMapSection extends StatefulWidget {
  const MindMapSection({super.key, required this.nodes});

  final List<MindMapNode> nodes;

  @override
  State<MindMapSection> createState() => _MindMapSectionState();
}

class _MindMapSectionState extends State<MindMapSection> {
  final List<int> _path = [];

  MindMapNode? get _current {
    MindMapNode? node;
    var level = widget.nodes;
    for (final index in _path) {
      if (index < 0 || index >= level.length) return node;
      node = level[index];
      level = node.children;
    }
    return node;
  }

  List<MindMapNode> get _children {
    final current = _current;
    if (current == null) return widget.nodes;
    return current.children;
  }

  String get _backLabel {
    if (_path.length <= 1) return 'Mappa';
    final parentPath = _path.sublist(0, _path.length - 1);
    MindMapNode? node;
    var level = widget.nodes;
    for (final index in parentPath) {
      if (index < 0 || index >= level.length) break;
      node = level[index];
      level = node.children;
    }
    final title = node?.title.trim() ?? '';
    return title.isEmpty ? 'Mappa' : title;
  }

  void _open(int index) {
    final nodes = _children;
    if (index < 0 || index >= nodes.length || !nodes[index].opens) return;
    HapticFeedback.selectionClick();
    setState(() => _path.add(index));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nodes.isEmpty) {
      return Text(
        'Nessun punto in questa mappa.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: DropColors.muted(context),
            ),
      );
    }

    final current = _current;
    final children = _children;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_path.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _path.removeLast());
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chevron_left,
                      size: 18,
                      color: DropColors.muted(context),
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        _backLabel,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: DropColors.muted(context),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            current?.title ?? '',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w400,
                  height: 1.25,
                ),
          ),
          if ((current?.body ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            DropMathText(data: current!.body),
          ],
          if (children.isNotEmpty) const SizedBox(height: 22),
        ],
        for (var i = 0; i < children.length; i++)
          _MindMapRow(
            title: children[i].title,
            opens: children[i].opens,
            onTap: () => _open(i),
          ),
      ],
    );
  }
}

class _MindMapRow extends StatelessWidget {
  const _MindMapRow({
    required this.title,
    required this.opens,
    required this.onTap,
  });

  final String title;
  final bool opens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: opens ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ink.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            if (opens)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: DropColors.muted(context),
              ),
          ],
        ),
      ),
    );
  }
}

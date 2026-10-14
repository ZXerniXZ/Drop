import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/note_structured_data.dart';
import '../../theme/drop_theme.dart';
import '../drop_markdown.dart';
import '../plot_canvas.dart';
import 'mind_map_handle.dart';
import 'mind_map_view_stub.dart' as placeholder;

class MindMapView extends StatefulWidget {
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
  State<MindMapView> createState() => _MindMapViewState();
}

class _MindMapViewState extends State<MindMapView> {
  final _transform = TransformationController();

  bool get _underTest => Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    widget.handle.attach(_fit);
  }

  @override
  void didUpdateWidget(MindMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.handle != widget.handle) {
      oldWidget.handle.detach(_fit);
      widget.handle.attach(_fit);
    }
  }

  @override
  void dispose() {
    widget.handle.detach(_fit);
    _transform.dispose();
    super.dispose();
  }

  Future<void> _fit() async {
    _transform.value = Matrix4.identity();
  }

  void _open(MindMapNode node) {
    if (node.body.trim().isEmpty && node.visuals.isEmpty) return;
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            children: [
              Text(node.title, style: Theme.of(context).textTheme.titleMedium),
              if (node.body.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                DropMarkdown(data: node.body),
              ],
              for (final visual in node.visuals) ...[
                const SizedBox(height: 16),
                SizedBox(height: 220, child: PlotCanvas(visual: visual)),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_underTest || !widget.interactive) {
      return placeholder.MindMapView(
        handle: widget.handle,
        title: widget.title,
        nodes: widget.nodes,
        interactive: widget.interactive,
      );
    }
    final ink = Theme.of(context).colorScheme.onSurface;
    final line = DropColors.muted(context).withValues(alpha: 0.45);
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: InteractiveViewer(
        transformationController: _transform,
        constrained: false,
        alignment: Alignment.topLeft,
        minScale: 0.35,
        maxScale: 2.4,
        boundaryMargin: const EdgeInsets.all(280),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 48, 48),
          child: _Branch(
            title: widget.title.trim().isEmpty ? 'Mappa' : widget.title.trim(),
            body: '',
            visuals: const [],
            children: widget.nodes,
            ink: ink,
            line: line,
            onOpen: _open,
          ),
        ),
      ),
    );
  }
}

class _Branch extends StatelessWidget {
  const _Branch({
    required this.title,
    required this.body,
    required this.visuals,
    required this.children,
    required this.ink,
    required this.line,
    required this.onOpen,
  });

  final String title;
  final String body;
  final List<Map<String, dynamic>> visuals;
  final List<MindMapNode> children;
  final Color ink;
  final Color line;
  final void Function(MindMapNode node) onOpen;

  @override
  Widget build(BuildContext context) {
    final node = MindMapNode(
      title: title,
      body: body,
      visuals: visuals,
      children: children,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _NodeCard(node: node, ink: ink, onOpen: onOpen),
        if (children.isNotEmpty) ...[
          Container(width: 22, height: 1, color: line),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                _Branch(
                  title: children[i].title,
                  body: children[i].body,
                  visuals: children[i].visuals,
                  children: children[i].children,
                  ink: ink,
                  line: line,
                  onOpen: onOpen,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.ink,
    required this.onOpen,
  });

  final MindMapNode node;
  final Color ink;
  final void Function(MindMapNode node) onOpen;

  @override
  Widget build(BuildContext context) {
    final opens = node.body.trim().isNotEmpty || node.visuals.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: opens ? () => onOpen(node) : null,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DropColors.border(context)),
              ),
              child: Text(
                node.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, height: 1.3, color: ink),
              ),
            ),
          ),
        ),
        if (node.visuals.isNotEmpty)
          Container(
            width: 220,
            height: 132,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: DropColors.border(context)),
            ),
            child: PlotCanvas(visual: node.visuals.first),
          ),
      ],
    );
  }
}

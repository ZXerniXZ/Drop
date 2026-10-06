import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../models/note_structured_data.dart';
import 'mind_map_handle.dart';

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
  late final String _viewType = 'drop-mind-map-${identityHashCode(this)}';
  late final web.HTMLIFrameElement _iframe;
  late final JSFunction _onWindowMessage;
  var _ready = false;
  Brightness? _brightness;

  @override
  void initState() {
    super.initState();
    widget.handle.attach(_fit);
    _onWindowMessage = _onMessage.toJS;
    _iframe = web.HTMLIFrameElement()
      ..src = 'assets/assets/mind_map/index.html'
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%';
    web.window.addEventListener('message', _onWindowMessage);
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => _iframe,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    final changed = _brightness != null && _brightness != brightness;
    _brightness = brightness;
    if (changed) _render();
  }

  @override
  void didUpdateWidget(MindMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.handle != widget.handle) {
      oldWidget.handle.detach(_fit);
      widget.handle.attach(_fit);
    }
    if (oldWidget.title != widget.title || oldWidget.nodes != widget.nodes) {
      _render();
    }
    _setHitTesting(widget.interactive);
  }

  @override
  void dispose() {
    widget.handle.detach(_fit);
    web.window.removeEventListener('message', _onWindowMessage);
    super.dispose();
  }

  void _onMessage(web.Event event) {
    if (event.isA<web.MessageEvent>() == false) return;
    final message = event as web.MessageEvent;
    if (message.source != _iframe.contentWindow) return;
    final data = message.data?.dartify();
    Object? decoded = data;
    if (data is String) {
      try {
        decoded = jsonDecode(data);
      } catch (_) {
        return;
      }
    }
    if (decoded is Map && decoded['type'] == 'ready' && !_ready) {
      _ready = true;
      _render();
    }
  }

  Future<void> _fit() async {
    _post({'type': 'fit'});
  }

  void _render() {
    if (!_ready || !mounted) return;
    _post({
      'type': 'render',
      'dark': Theme.of(context).brightness == Brightness.dark,
      'payload': {
        'title': widget.title,
        'nodes': widget.nodes.map((node) => node.toMap()).toList(),
      },
    });
  }

  void _post(Map<String, Object?> message) {
    _iframe.contentWindow?.postMessage(message.jsify(), '*'.toJS);
  }

  void _setHitTesting(bool interactive) {
    final value = interactive ? 'auto' : 'none';
    _iframe.style.pointerEvents = value;
    var parent = _iframe.parentElement;
    for (var depth = 0; depth < 4 && parent != null; depth += 1) {
      final tag = parent.tagName.toLowerCase();
      if (tag == 'body' || tag == 'html') break;
      if (parent.isA<web.HTMLElement>()) {
        (parent as web.HTMLElement).style.pointerEvents = value;
      }
      parent = parent.parentElement;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.interactive) {
      _setHitTesting(false);
      return const SizedBox.expand();
    }
    _setHitTesting(true);
    return HtmlElementView(viewType: _viewType);
  }
}

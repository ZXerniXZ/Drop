import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/note_structured_data.dart';
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
  WebViewController? _controller;
  var _ready = false;
  Brightness? _brightness;

  bool get _underTest => Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    widget.handle.attach(_fit);
    if (_underTest) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Uno sfondo trasparente su Android lascia il WebView vuoto: la pagina
      // della mappa si apre ma l'albero non viene disegnato.
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _ready = true;
            _render();
          },
        ),
      )
      ..addJavaScriptChannel(
        'DropBridge',
        onMessageReceived: (message) {
          Object? decoded;
          try {
            decoded = jsonDecode(message.message);
          } catch (_) {
            return;
          }
          if (decoded is Map && decoded['type'] == 'ready') {
            _ready = true;
            _render();
          }
        },
      )
      ..loadFlutterAsset('assets/mind_map/index.html');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    final changed = _brightness != null && _brightness != brightness;
    _brightness = brightness;
    _controller?.setBackgroundColor(
      brightness == Brightness.dark
          ? const Color(0xFF000000)
          : const Color(0xFFFAFAFA),
    );
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
    } else if (oldWidget.handle != widget.handle) {
      _render();
    }
  }

  @override
  void dispose() {
    widget.handle.detach(_fit);
    super.dispose();
  }

  Future<void> _fit() async {
    if (!_ready || _controller == null) return;
    await _controller!.runJavaScript('DropMap.fit()');
  }

  Future<void> _render() async {
    final controller = _controller;
    if (!_ready || controller == null || !mounted) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final payload = jsonEncode({
      'title': widget.title,
      'nodes': widget.nodes.map((node) => node.toMap()).toList(),
    });
    final script = 'DropMap.render($payload, $dark)';
    await controller.runJavaScript(script);
    await controller.runJavaScript('DropMap.fit()');
  }

  @override
  Widget build(BuildContext context) {
    if (_underTest || _controller == null || !widget.interactive) {
      return placeholder.MindMapView(
        handle: widget.handle,
        title: widget.title,
        nodes: widget.nodes,
        interactive: widget.interactive,
      );
    }
    return WebViewWidget(controller: _controller!);
  }
}

import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class ChatPlotView extends StatefulWidget {
  const ChatPlotView({super.key, required this.visual});

  final Map<String, dynamic> visual;

  @override
  State<ChatPlotView> createState() => _ChatPlotViewState();
}

class _ChatPlotViewState extends State<ChatPlotView> {
  late final String _viewType = 'drop-chat-plot-${identityHashCode(this)}';
  late final web.HTMLIFrameElement _iframe;
  late final JSFunction _onWindowMessage;
  var _ready = false;
  String? _rendered;
  Brightness? _brightness;

  @override
  void initState() {
    super.initState();
    _onWindowMessage = _onMessage.toJS;
    _iframe = web.HTMLIFrameElement()
      ..src = 'assets/assets/mind_map/plot_host.html'
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
    if (_brightness == brightness) return;
    _brightness = brightness;
    _render();
  }

  @override
  void didUpdateWidget(ChatPlotView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (jsonEncode(oldWidget.visual) != jsonEncode(widget.visual)) {
      _render();
    }
  }

  @override
  void dispose() {
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
    if (decoded is Map && decoded['type'] == 'ready') {
      _ready = true;
      _render();
    }
  }

  void _render() {
    if (!_ready || !mounted) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final signature = '${dark ? 1 : 0}:${jsonEncode(widget.visual)}';
    if (_rendered == signature) return;
    _rendered = signature;
    _iframe.contentWindow?.postMessage(
      {'type': 'render', 'dark': dark, 'visual': widget.visual}.jsify(),
      '*'.toJS,
    );
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}

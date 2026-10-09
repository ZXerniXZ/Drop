import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'chat_plot_view_stub.dart' as placeholder;

class ChatPlotView extends StatefulWidget {
  const ChatPlotView({super.key, required this.visual});

  final Map<String, dynamic> visual;

  @override
  State<ChatPlotView> createState() => _ChatPlotViewState();
}

class _ChatPlotViewState extends State<ChatPlotView> {
  WebViewController? _controller;
  var _ready = false;
  String? _rendered;
  Brightness? _brightness;

  bool get _underTest => Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    if (_underTest) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'DropBridge',
        onMessageReceived: (message) {
          try {
            final decoded = jsonDecode(message.message);
            if (decoded is Map && decoded['type'] == 'ready') {
              _ready = true;
              _render();
            }
          } catch (_) {}
        },
      )
      ..loadFlutterAsset('assets/mind_map/plot_host.html');
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

  Future<void> _render() async {
    final controller = _controller;
    if (!_ready || controller == null || !mounted) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final signature = '${dark ? 1 : 0}:${jsonEncode(widget.visual)}';
    if (_rendered == signature) return;
    _rendered = signature;
    await controller.runJavaScript(
      'DropPlotHost.render(${jsonEncode(widget.visual)}, $dark)',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_underTest || _controller == null) {
      return placeholder.ChatPlotView(visual: widget.visual);
    }
    return WebViewWidget(controller: _controller!);
  }
}

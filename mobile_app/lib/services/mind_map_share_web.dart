import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../models/note_structured_data.dart';
import 'mind_map_export.dart';

Future<void> shareMindMapMarkdown({
  required String title,
  required List<MindMapNode> nodes,
}) async {
  final filename = mindMapFileName(title);
  final bytes = Uint8List.fromList(utf8.encode(mindMapToMarkdown(title, nodes)));
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/markdown'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/note_structured_data.dart';
import 'mind_map_export.dart';

Future<void> shareMindMapMarkdown({
  required String title,
  required List<MindMapNode> nodes,
}) async {
  final filename = mindMapFileName(title);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(mindMapToMarkdown(title, nodes), flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile(file.path, mimeType: 'text/markdown', name: filename),
      ],
      subject: title,
    ),
  );
}

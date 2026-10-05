import 'package:drop/models/note_structured_data.dart';
import 'package:drop/services/mind_map_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('markdown keeps headings, math, and visual blocks', () {
    final markdown = mindMapToMarkdown('Lezione', [
      MindMapNode(
        title: 'Energia',
        body: r'La relazione è $E=mc^2$.',
        visuals: const [
          {
            'kind': 'plot2d',
            'expressions': ['x^2'],
            'x': [-2, 2],
          },
        ],
        children: const [
          MindMapNode(
            title: 'Massa',
            children: [MindMapNode(title: 'Dettaglio')],
          ),
        ],
      ),
    ]);

    expect(markdown, startsWith('# Lezione'));
    expect(markdown, contains('## Energia'));
    expect(markdown, contains(r'$E=mc^2$'));
    expect(markdown, contains('```drop-visual'));
    expect(markdown, contains('"kind": "plot2d"'));
    expect(markdown, contains('### Massa'));
    expect(markdown, contains('- Dettaglio'));
  });

  test('visuals survive a map round trip', () {
    const node = MindMapNode(
      title: 'Curva',
      visuals: [
        {
          'kind': 'curve3d',
          'x': 'cos(t)',
          'y': 'sin(t)',
          'z': 't/5',
          't': [0, 1],
        },
      ],
    );

    final restored = MindMapNode.fromMap(node.toMap());
    expect(restored.visuals, node.visuals);
    expect(restored.title, 'Curva');
  });
}

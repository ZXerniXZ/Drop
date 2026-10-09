import 'package:drop/services/openrouter_prompts.dart';
import 'package:drop/widgets/drop_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('math delimiters are shielded and code fences stay literal', () {
    final prepared = prepareDropMarkdown(
      r'energia $E=mc^2$ e $$a_i$$ poi \(x_1\) e \[y_2\]',
    );
    expect(prepared.contains(r'$E=mc^2$'), isFalse);
    expect(prepared.contains('dropmath:'), isTrue);
    expect(prepared.contains('```drop-math'), isTrue);
    expect(prepared.contains('a_i'), isTrue);
    expect(prepared.contains('y_2'), isTrue);
    expect(prepared.contains(r'\(x_1\)'), isFalse);

    final code = prepareDropMarkdown(
      'Prima\n```python\nprint("\$x\$")\n```\nDopo \$y\$',
    );
    expect(code, contains(r'print("$x$")'));
    expect(code.contains('dropmath:'), isTrue);
    expect(code.indexOf('dropmath:'), greaterThan(code.indexOf('print')));

    expect(prepareDropMarkdown(r'Costa $5 e poi $10.'), r'Costa $5 e poi $10.');
  });

  test('chat prompt asks for math and plots', () {
    final prompt = buildNoteChatSystemPrompt(outputLanguage: 'it');
    expect(prompt, contains('Italiano'));
    expect(prompt, contains(r'$...$'));
    expect(prompt, contains('drop-visual'));
    expect(prompt, contains('plot2d'));
    expect(prompt.contains('{output_language}'), isFalse);
  });

  testWidgets('renders inline math, display math, code, and a plot', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DropMarkdown(
              data: r'''
Inline $E=mc^2$ e display

$$a_i$$

```python
print("ok")
```

```drop-visual
{"kind":"plot2d","title":"Sezione","expressions":["x^2"],"x":[-2,2]}
```

Costa $5 e poi $10.
''',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining('print("ok")'), findsOneWidget);
    expect(find.text('Sezione'), findsOneWidget);
    expect(find.textContaining(r'$5'), findsOneWidget);
    expect(find.textContaining('dropmath:'), findsNothing);
  });
}

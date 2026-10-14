import 'package:drop/widgets/plot_canvas.dart';
import 'package:drop/widgets/plot_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('evaluates the expressions used by note graphs', () {
    expect(PlotFunction.tryParse('x^2')!.eval({'x': 3}), 9);
    expect(PlotFunction.tryParse('y = 2*x + 1')!.eval({'x': 4}), 9);
    expect(PlotFunction.tryParse(r'√(4)')!.eval({}), 2);
    expect(PlotFunction.tryParse('sin(pi/2)')!.eval({}), closeTo(1, 1e-9));
    expect(PlotFunction.tryParse('import("x")'), isNull);
  });

  test('compiles a parabola and a bar chart', () {
    final curve = compilePlot({
      'kind': 'plot2d',
      'title': 'Sezione',
      'expressions': ['x^2'],
      'x': [-2, 2],
    });
    expect(curve.isEmpty, isFalse);
    expect(curve.title, 'Sezione');

    final bars = compilePlot({
      'kind': 'chart',
      'type': 'bar',
      'labels': ['A', 'B'],
      'series': [
        {
          'name': 'valori',
          'values': [1, 2],
        },
      ],
    });
    expect(bars.isEmpty, isFalse);

    final surface = compilePlot({
      'kind': 'surface3d',
      'expression': 'x^2+y^2',
      'x': [-1, 1],
      'y': [-1, 1],
    });
    expect(surface.isEmpty, isFalse);
  });
}

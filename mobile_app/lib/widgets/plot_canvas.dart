import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'plot_math.dart';

class PlotCanvas extends StatelessWidget {
  const PlotCanvas({super.key, required this.visual});

  final Map<String, dynamic> visual;

  @override
  Widget build(BuildContext context) {
    final figure = compilePlot(visual);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF4F4F5) : const Color(0xFF111111);
    final muted = dark ? const Color(0x73FFFFFF) : const Color(0x73000000);
    final grid = dark ? const Color(0x14FFFFFF) : const Color(0x14000000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (figure.title != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
            child: Text(
              figure.title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.2, color: muted),
            ),
          ),
        Expanded(
          child: figure.isEmpty
              ? Center(
                  child: Text(
                    'Grafico non disponibile',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                )
              : CustomPaint(
                  painter: _PlotPainter(
                    figure: figure,
                    ink: ink,
                    muted: muted,
                    grid: grid,
                  ),
                  child: const SizedBox.expand(),
                ),
        ),
      ],
    );
  }
}

enum _PlotMode { lines, bars, field }

class PlotFigure {
  const PlotFigure._({
    this.title,
    this._mode = _PlotMode.lines,
    this._series = const [],
    this._labels = const [],
    this._field,
  });

  final String? title;
  final _PlotMode _mode;
  final List<_Series> _series;
  final List<String> _labels;
  final _Field? _field;

  bool get isEmpty =>
      _mode == _PlotMode.field ? _field == null : _series.isEmpty;
}

class _Series {
  const _Series(this.name, this.xs, this.ys);

  final String name;
  final List<double?> xs;
  final List<double?> ys;
}

class _Field {
  const _Field(this.xs, this.ys, this.z);

  final List<double> xs;
  final List<double> ys;
  final List<List<double?>> z;
}

PlotFigure compilePlot(Map<String, dynamic> visual) {
  final title = _title(visual['title']);
  final kind = visual['kind']?.toString();
  return switch (kind) {
    'plot2d' => _lines(title, visual),
    'chart' => _chart(title, visual),
    'surface3d' => _field(title, visual),
    'curve3d' => _curve(title, visual),
    _ => PlotFigure._(title: title),
  };
}

String? _title(Object? raw) {
  if (raw is! String) return null;
  final text = raw.trim();
  return text.isEmpty ? null : text;
}

({double low, double high}) _span(Object? raw, double low, double high) {
  if (raw is! List || raw.length < 2) return (low: low, high: high);
  final a = _num(raw[0]);
  final b = _num(raw[1]);
  if (a == null || b == null || a == b) return (low: low, high: high);
  return a < b ? (low: a, high: b) : (low: b, high: a);
}

double? _num(Object? raw) {
  if (raw is num) {
    final value = raw.toDouble();
    return value.isFinite ? value : null;
  }
  if (raw is! String) return null;
  final cleaned = raw
      .replaceAll(RegExp(r'[^0-9,.\-eE]'), '')
      .replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || !value.isFinite) return null;
  return value;
}

List<double> _linspace(({double low, double high}) range, int steps) {
  if (steps <= 1) return [range.low];
  return [
    for (var i = 0; i < steps; i++)
      range.low + (range.high - range.low) * i / (steps - 1),
  ];
}

List<String> _expressions(Map<String, dynamic> visual) {
  final raw = visual['expressions'];
  if (raw is List) {
    return raw
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  final single = visual['expression'];
  if (single is String && single.trim().isNotEmpty) return [single.trim()];
  return const [];
}

PlotFigure _lines(String? title, Map<String, dynamic> visual) {
  final range = _span(visual['x'], -5, 5);
  final xs = _linspace(range, 96);
  final series = <_Series>[];
  for (final expression in _expressions(visual).take(4)) {
    final fn = PlotFunction.tryParse(expression);
    if (fn == null) continue;
    final ys = [
      for (final x in xs) fn.eval({'x': x}),
    ];
    if (!ys.any((value) => value != null)) continue;
    series.add(_Series(expression, xs, ys));
  }
  return PlotFigure._(title: title, series: series);
}

PlotFigure _chart(String? title, Map<String, dynamic> visual) {
  final labels = visual['labels'] is List
      ? (visual['labels'] as List).map((item) => item.toString()).toList()
      : <String>[];
  final rawSeries = visual['series'];
  final series = <_Series>[];
  if (rawSeries is List) {
    for (var index = 0; index < rawSeries.length && index < 4; index++) {
      final item = rawSeries[index];
      if (item is! Map) continue;
      final values = item['values'];
      if (values is! List) continue;
      final ys = [for (final value in values.take(50)) _num(value)];
      if (!ys.any((value) => value != null)) continue;
      final name = item['name']?.toString().trim();
      series.add(
        _Series(name == null || name.isEmpty ? 'Serie ${index + 1}' : name, [
          for (var i = 0; i < ys.length; i++) i.toDouble(),
        ], ys),
      );
    }
  }
  final count = series.fold<int>(
    0,
    (max, item) => math.max(max, item.ys.length),
  );
  final axis = [
    for (var i = 0; i < count; i++)
      i < labels.length && labels[i].isNotEmpty ? labels[i] : '${i + 1}',
  ];
  return PlotFigure._(
    title: title,
    mode: visual['type'] == 'line' ? _PlotMode.lines : _PlotMode.bars,
    series: series,
    labels: axis,
  );
}

PlotFigure _field(String? title, Map<String, dynamic> visual) {
  final expression = visual['expression'];
  if (expression is! String) return PlotFigure._(title: title);
  final fn = PlotFunction.tryParse(expression);
  if (fn == null) return PlotFigure._(title: title);
  final xs = _linspace(_span(visual['x'], -2, 2), 22);
  final ys = _linspace(_span(visual['y'], -2, 2), 22);
  final z = [
    for (final y in ys)
      [
        for (final x in xs) fn.eval({'x': x, 'y': y}),
      ],
  ];
  if (!z.any((row) => row.any((value) => value != null))) {
    return PlotFigure._(title: title);
  }
  return PlotFigure._(
    title: title,
    mode: _PlotMode.field,
    field: _Field(xs, ys, z),
  );
}

PlotFigure _curve(String? title, Map<String, dynamic> visual) {
  final xExpr = visual['x'];
  final yExpr = visual['y'];
  if (xExpr is! String || yExpr is! String) return PlotFigure._(title: title);
  final xFn = PlotFunction.tryParse(xExpr);
  final yFn = PlotFunction.tryParse(yExpr);
  if (xFn == null || yFn == null) return PlotFigure._(title: title);
  final ts = _linspace(_span(visual['t'], 0, 2 * math.pi), 120);
  final xs = [
    for (final t in ts) xFn.eval({'t': t}),
  ];
  final ys = [
    for (final t in ts) yFn.eval({'t': t}),
  ];
  if (!xs.any((value) => value != null) || !ys.any((value) => value != null)) {
    return PlotFigure._(title: title);
  }
  return PlotFigure._(title: title, series: [_Series('', xs, ys)]);
}

class _PlotPainter extends CustomPainter {
  _PlotPainter({
    required this.figure,
    required this.ink,
    required this.muted,
    required this.grid,
  });

  final PlotFigure figure;
  final Color ink;
  final Color muted;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 8 || size.height < 8) return;
    if (figure._mode == _PlotMode.field && figure._field != null) {
      _paintField(canvas, size, figure._field!);
      return;
    }
    if (figure._mode == _PlotMode.bars) {
      _paintBars(canvas, size);
      return;
    }
    _paintLines(canvas, size);
  }

  Rect _plotRect(Size size, {required bool category}) {
    return Rect.fromLTWH(
      category ? 8 : 36,
      8,
      math.max(1, size.width - (category ? 16 : 46)),
      math.max(1, size.height - 32),
    );
  }

  void _paintLines(Canvas canvas, Size size) {
    final plot = _plotRect(size, category: figure._labels.isNotEmpty);
    var xMin = double.infinity;
    var xMax = -double.infinity;
    var yMin = double.infinity;
    var yMax = -double.infinity;
    for (final series in figure._series) {
      for (var i = 0; i < series.xs.length && i < series.ys.length; i++) {
        final x = series.xs[i];
        final y = series.ys[i];
        if (x == null || y == null) continue;
        xMin = math.min(xMin, x);
        xMax = math.max(xMax, x);
        yMin = math.min(yMin, y);
        yMax = math.max(yMax, y);
      }
    }
    if (!xMin.isFinite || !yMin.isFinite) return;
    if (xMin == xMax) {
      xMin -= 1;
      xMax += 1;
    }
    if (yMin == yMax) {
      yMin -= 1;
      yMax += 1;
    }
    final yPad = (yMax - yMin) * 0.08;
    yMin -= yPad;
    yMax += yPad;
    _axes(canvas, plot, xMin, xMax, yMin, yMax, category: figure._labels);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (var s = 0; s < figure._series.length; s++) {
      line.color = s == 0 ? ink : muted;
      final series = figure._series[s];
      final path = ui.Path();
      var drawing = false;
      for (var i = 0; i < series.xs.length && i < series.ys.length; i++) {
        final x = series.xs[i];
        final y = series.ys[i];
        if (x == null || y == null) {
          drawing = false;
          continue;
        }
        final point = Offset(
          plot.left + (x - xMin) / (xMax - xMin) * plot.width,
          plot.bottom - (y - yMin) / (yMax - yMin) * plot.height,
        );
        if (!drawing) {
          path.moveTo(point.dx, point.dy);
          drawing = true;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, line);
    }
  }

  void _paintBars(Canvas canvas, Size size) {
    final plot = _plotRect(size, category: true);
    var yMin = 0.0;
    var yMax = 1.0;
    var count = 0;
    for (final series in figure._series) {
      count = math.max(count, series.ys.length);
      for (final value in series.ys) {
        if (value == null) continue;
        yMin = math.min(yMin, value);
        yMax = math.max(yMax, value);
      }
    }
    if (yMin == yMax) yMax = yMin + 1;
    final pad = (yMax - yMin) * 0.08;
    if (yMin < 0) yMin -= pad;
    yMax += pad;
    _axes(
      canvas,
      plot,
      0,
      math.max(1, count).toDouble(),
      yMin,
      yMax,
      category: figure._labels,
    );
    final groups = math.max(1, count);
    final slot = plot.width / groups;
    final bars = math.max(1, figure._series.length);
    final gap = slot * 0.22;
    final barWidth = math.max(1.0, (slot - gap) / bars);
    for (var s = 0; s < figure._series.length; s++) {
      final paint = Paint()..color = s == 0 ? ink : muted;
      final series = figure._series[s];
      for (var i = 0; i < series.ys.length; i++) {
        final value = series.ys[i];
        if (value == null) continue;
        final zero = plot.bottom - (0 - yMin) / (yMax - yMin) * plot.height;
        final top = plot.bottom - (value - yMin) / (yMax - yMin) * plot.height;
        final left = plot.left + i * slot + gap / 2 + s * barWidth;
        final rect = Rect.fromLTRB(
          left,
          math.min(zero, top),
          left + barWidth * 0.92,
          math.max(zero, top),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          paint,
        );
      }
    }
  }

  void _paintField(Canvas canvas, Size size, _Field field) {
    final plot = _plotRect(size, category: false);
    var zMin = double.infinity;
    var zMax = -double.infinity;
    for (final row in field.z) {
      for (final value in row) {
        if (value == null) continue;
        zMin = math.min(zMin, value);
        zMax = math.max(zMax, value);
      }
    }
    if (!zMin.isFinite) return;
    if (zMin == zMax) zMax = zMin + 1;
    final rows = field.z.length;
    final cols = rows == 0 ? 0 : field.z.first.length;
    if (rows == 0 || cols == 0) return;
    final cellW = plot.width / cols;
    final cellH = plot.height / rows;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < field.z[row].length; col++) {
        final value = field.z[row][col];
        final t = value == null
            ? 0.0
            : ((value - zMin) / (zMax - zMin)).clamp(0.0, 1.0);
        final paint = Paint()
          ..color = Color.lerp(grid, ink, value == null ? 0 : 0.18 + t * 0.82)!;
        canvas.drawRect(
          Rect.fromLTWH(
            plot.left + col * cellW,
            plot.bottom - (row + 1) * cellH,
            cellW + 0.4,
            cellH + 0.4,
          ),
          paint,
        );
      }
    }
    _frame(canvas, plot);
  }

  void _axes(
    Canvas canvas,
    Rect plot,
    double xMin,
    double xMax,
    double yMin,
    double yMax, {
    required List<String> category,
  }) {
    final paint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var step = 0; step <= 4; step++) {
      final y = plot.top + plot.height * step / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), paint);
      if (category.isEmpty) {
        final value = yMax - (yMax - yMin) * step / 4;
        _label(
          canvas,
          _tick(value),
          Offset(2, y - 6),
          muted,
          alignRight: false,
        );
      }
    }
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      Paint()..color = muted.withValues(alpha: 0.7),
    );
    if (category.isEmpty) {
      _label(
        canvas,
        _tick(xMin),
        Offset(plot.left, plot.bottom + 4),
        muted,
        alignRight: false,
      );
      _label(
        canvas,
        _tick(xMax),
        Offset(plot.right - 28, plot.bottom + 4),
        muted,
        alignRight: false,
      );
      return;
    }
    final limit = math.min(category.length, 6);
    if (limit == 0) return;
    for (var i = 0; i < limit; i++) {
      final index = limit == 1
          ? 0
          : (i * (category.length - 1) / (limit - 1)).round();
      final x = plot.left + (index + 0.5) / category.length * plot.width;
      _label(
        canvas,
        category[index],
        Offset(x - 16, plot.bottom + 4),
        muted,
        alignRight: false,
      );
    }
  }

  void _frame(Canvas canvas, Rect plot) {
    canvas.drawRect(
      plot,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = muted.withValues(alpha: 0.45),
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset offset,
    Color color, {
    required bool alignRight,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 10, height: 1),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 48);
    painter.paint(
      canvas,
      alignRight ? offset - Offset(painter.width, 0) : offset,
    );
  }

  String _tick(double value) {
    if (value.abs() >= 1000 || (value.abs() < 0.01 && value != 0)) {
      return value.toStringAsExponential(0);
    }
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.05) return rounded.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(covariant _PlotPainter oldDelegate) {
    return oldDelegate.figure != figure ||
        oldDelegate.ink != ink ||
        oldDelegate.muted != muted ||
        oldDelegate.grid != grid;
  }
}

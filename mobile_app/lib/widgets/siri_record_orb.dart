import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../models/record_orb_style.dart';
import '../theme/drop_theme.dart';

class SiriRecordOrb extends StatelessWidget {
  const SiriRecordOrb({
    super.key,
    required this.size,
    required this.style,
    required this.isRecording,
    required this.amplitude,
    required this.phase,
    required this.breath,
    required this.isDark,
  });

  final double size;
  final RecordOrbStyle style;
  final bool isRecording;
  final double amplitude;
  final double phase;
  final double breath;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _RecordOrbPainter(
        style: style,
        isRecording: isRecording,
        amplitude: amplitude,
        phase: phase,
        breath: breath,
        isDark: isDark,
      ),
    );
  }
}

class _RecordOrbPainter extends CustomPainter {
  _RecordOrbPainter({
    required this.style,
    required this.isRecording,
    required this.amplitude,
    required this.phase,
    required this.breath,
    required this.isDark,
  });

  final RecordOrbStyle style;
  final bool isRecording;
  final double amplitude;
  final double phase;
  final double breath;
  final bool isDark;

  static const _barCount = 18;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case RecordOrbStyle.radialBars:
        if (isRecording) {
          _paintRadialRecording(canvas, size);
        } else {
          _paintRadialIdle(canvas, size);
        }
      case RecordOrbStyle.organicBlob:
        _paintOrganicBlob(canvas, size);
      case RecordOrbStyle.gradientFluid:
        _paintGradientFluid(canvas, size);
      case RecordOrbStyle.classicPulse:
        _paintClassic(canvas, size);
    }
  }

  void _paintRadialIdle(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final glowRadius = radius * (0.92 + breath * 0.08);

    for (var i = 0; i < 2; i++) {
      final ripple = (phase + i * 0.45) % 1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = DropColors.recordRed.withValues(alpha: (1 - ripple) * 0.12);
      canvas.drawCircle(center, glowRadius * (0.55 + ripple * 0.55), paint);
    }

    _drawRadialGlow(canvas, center, glowRadius, 0.08 + breath * 0.1);
    _drawCore(canvas, center, radius * (0.18 + breath * 0.03));
  }

  void _paintRadialRecording(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final amp = amplitude.clamp(0.0, 1.0);

    for (var i = 0; i < 3; i++) {
      final ripple = (phase + i * 0.28) % 1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lerpDouble(1.4, 2.4, amp)!
        ..color = DropColors.recordRed.withValues(
          alpha: (1 - ripple) * (0.18 + amp * 0.35),
        );
      canvas.drawCircle(center, radius * (0.45 + ripple * 0.95 + amp * 0.15), paint);
    }

    final innerR = radius * 0.34;
    final outerR = radius * (0.72 + amp * 0.18);
    for (var i = 0; i < _barCount; i++) {
      final angle = (i / _barCount) * math.pi * 2 - math.pi / 2;
      final wobble = math.sin(phase * math.pi * 2 + i * 0.65) * 0.5 + 0.5;
      final barAmp = amp * (0.35 + 0.65 * wobble);
      final len = innerR + (outerR - innerR) * barAmp;
      final dx = math.cos(angle);
      final dy = math.sin(angle);
      final paint = Paint()
        ..strokeWidth = lerpDouble(2.0, 3.2, amp)!
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(
          DropColors.recordRed.withValues(alpha: 0.5),
          const Color(0xFFFF8A8C),
          wobble,
        )!;
      canvas.drawLine(
        center + Offset(dx * innerR * 0.85, dy * innerR * 0.85),
        center + Offset(dx * len, dy * len),
        paint,
      );
    }

    _drawCore(canvas, center, radius * (0.26 + amp * 0.1));
  }

  void _paintOrganicBlob(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final amp = isRecording ? amplitude.clamp(0.0, 1.0) : breath * 0.25;
    const segments = 72;
    final path = Path();

    for (var i = 0; i <= segments; i++) {
      final t = (i / segments) * math.pi * 2;
      final wobble = 1.0 +
          amp * 0.22 * math.sin(t * 3 + phase * math.pi * 2) +
          amp * 0.12 * math.sin(t * 5 - phase * math.pi * 4) +
          breath * 0.06;
      final r = radius * (isRecording ? 0.52 : 0.38) * wobble;
      final point = center + Offset(math.cos(t) * r, math.sin(t) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          DropColors.recordRed.withValues(alpha: 0.35 + amp * 0.3),
          DropColors.recordRed.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius * 0.9, glow);

    final fill = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.45 + amp * 0.2),
          const Color(0xFFFF7072),
          DropColors.recordRed,
          const Color(0xFFC92E30),
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.6));
    canvas.drawPath(path, fill);

    if (isRecording) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.25 + amp * 0.2);
      canvas.drawPath(path, stroke);
    }
  }

  void _paintGradientFluid(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final amp = isRecording ? amplitude.clamp(0.0, 1.0) : breath * 0.2;
    final orbR = radius * (isRecording ? 0.58 + amp * 0.12 : 0.42 + breath * 0.06);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(phase * math.pi * 2);

    final outer = Paint()
      ..shader = SweepGradient(
        colors: [
          const Color(0xFFFF4D4F),
          const Color(0xFFFF6B9D),
          const Color(0xFF9B6BFF),
          const Color(0xFF5B8CFF),
          const Color(0xFFFF8A65),
          const Color(0xFFFF4D4F),
        ],
        transform: GradientRotation(phase * math.pi),
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: orbR * 1.2));
    canvas.drawCircle(Offset.zero, orbR * 1.15, outer);

    canvas.rotate(-phase * math.pi * 1.4);
    final mid = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.55),
          const Color(0xFFFF6B6D).withValues(alpha: 0.9),
          const Color(0xFF7C5CFF).withValues(alpha: 0.7),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: orbR));
    canvas.drawCircle(Offset.zero, orbR, mid);

    canvas.restore();

    if (isRecording) {
      for (var i = 0; i < 2; i++) {
        final ripple = (phase + i * 0.4) % 1.0;
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF9B6BFF).withValues(alpha: (1 - ripple) * amp * 0.35);
        canvas.drawCircle(center, orbR * (1.0 + ripple * 0.7), paint);
      }
    }
  }

  void _paintClassic(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final amp = isRecording ? amplitude.clamp(0.0, 1.0) : 0.0;

    if (isRecording) {
      final glow = Paint()
        ..color = DropColors.recordRed.withValues(alpha: 0.12 + amp * 0.35);
      canvas.drawCircle(center, radius * (0.9 + amp * 0.2), glow);
      final corner = 4.0 + amp * 8;
      final side = radius * (0.32 + amp * 0.2);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: side, height: side),
        Radius.circular(corner),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = DropColors.recordRed,
      );
    } else {
      final dotR = radius * (0.16 + breath * 0.03);
      canvas.drawCircle(
        center,
        dotR,
        Paint()..color = DropColors.recordRed.withValues(alpha: 0.6 + breath * 0.4),
      );
    }
  }

  void _drawRadialGlow(Canvas canvas, Offset center, double glowRadius, double opacity) {
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          DropColors.recordRed.withValues(alpha: opacity + 0.12),
          DropColors.recordRed.withValues(alpha: opacity * 0.4),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
    canvas.drawCircle(center, glowRadius, glow);
  }

  void _drawCore(Canvas canvas, Offset center, double coreRadius) {
    final coreGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.35),
          DropColors.recordRed,
          DropColors.recordRed.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius * 1.5));
    canvas.drawCircle(center, coreRadius * 1.4, coreGlow);

    final core = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.5),
          const Color(0xFFFF7072),
          DropColors.recordRed,
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius, core);
  }

  @override
  bool shouldRepaint(covariant _RecordOrbPainter oldDelegate) {
    return oldDelegate.style != style ||
        oldDelegate.isRecording != isRecording ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.phase != phase ||
        oldDelegate.breath != breath ||
        oldDelegate.isDark != isDark;
  }
}

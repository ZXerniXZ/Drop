import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Gradienti condivisi (chat AI, orb registrazione, ecc.).
abstract final class DropGradients {
  static const chat = [
    Color(0xFF5B8CFF),
    Color(0xFF9B59FF),
    Color(0xFF38BDF8),
    Color(0xFF7C3AED),
    Color(0xFF5B8CFF),
  ];

  static const chatStops = [0.0, 0.25, 0.5, 0.75, 1.0];

  static const chatMid = [
    Color(0xFF5B8CFF),
    Color(0xFF9B59FF),
    Color(0xFF38BDF8),
    Color(0xFF7C3AED),
  ];

  static SweepGradient chatSweep({
    required double rotation,
    double intensity = 1.0,
    bool isDark = true,
  }) {
    final t = intensity.clamp(0.0, 1.0);
    final idleA = isDark
        ? Colors.white.withValues(alpha: 0.28)
        : Colors.black.withValues(alpha: 0.14);
    final idleB = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);

    if (t < 1.0) {
      return SweepGradient(
        transform: GradientRotation(rotation * 2 * math.pi),
        colors: [
          Color.lerp(idleA, chat[0], t)!,
          Color.lerp(idleB, chat[1], t)!,
          Color.lerp(idleA, chat[2], t)!,
          Color.lerp(idleB, chat[3], t)!,
        ],
        stops: const [0.0, 0.33, 0.66, 1.0],
      );
    }

    return SweepGradient(
      transform: GradientRotation(rotation * 2 * math.pi),
      colors: chat,
      stops: chatStops,
    );
  }

  static RadialGradient chatOrbCore({double amp = 0}) {
    return RadialGradient(
      colors: [
        Colors.white.withValues(alpha: 0.5 + amp * 0.2),
        chat[0].withValues(alpha: 0.95),
        chat[1],
        chat[3].withValues(alpha: 0.85),
      ],
      stops: const [0.0, 0.35, 0.7, 1.0],
    );
  }

  static List<BoxShadow> chatGlow(double intensity, {double pulse = 0}) {
    final i = (intensity * 0.85 + pulse * 0.35).clamp(0.0, 1.0);
    if (i <= 0.02) return const [];

    return [
      BoxShadow(
        color: const Color(0xFF6366F1).withValues(alpha: 0.22 * i),
        blurRadius: 28 + pulse * 14,
        spreadRadius: 1 + pulse * 3,
      ),
      BoxShadow(
        color: const Color(0xFF38BDF8).withValues(alpha: 0.16 * i),
        blurRadius: 36 + pulse * 10,
        spreadRadius: -2,
        offset: Offset(-4 - pulse * 2, 0),
      ),
      BoxShadow(
        color: const Color(0xFFA855F7).withValues(alpha: 0.18 * i),
        blurRadius: 32 + pulse * 12,
        spreadRadius: -1,
        offset: Offset(4 + pulse * 2, 2),
      ),
    ];
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/drop_theme.dart';

class AskAiBar extends StatefulWidget {
  const AskAiBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.onOpenChat,
    this.enabled = true,
    this.hintText = 'Chiedi a Drop su questa nota...',
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onOpenChat;
  final bool enabled;
  final String hintText;

  @override
  State<AskAiBar> createState() => _AskAiBarState();
}

class _AskAiBarState extends State<AskAiBar> with TickerProviderStateMixin {
  late final FocusNode _focusNode;
  late final AnimationController _revealController;
  late final AnimationController _loopController;
  late final AnimationController _pulseController;
  late final Animation<double> _revealAnimation;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocusChange);
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _revealAnimation = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    );
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _revealController.forward().then((_) {
        if (mounted && _focusNode.hasFocus) {
          _loopController.repeat();
          _pulseController.repeat(reverse: true);
        }
      });
    } else {
      _loopController.stop();
      _loopController.reset();
      _pulseController.stop();
      _pulseController.reset();
      _revealController.reverse();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _revealController.dispose();
    _loopController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Gradient _borderGradient(bool isDark, double reveal, double rotation) {
    final angle = rotation * 2 * math.pi;
    final idleA = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.1);
    final idleB = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.04);

    if (reveal < 1.0) {
      return SweepGradient(
        transform: GradientRotation(angle),
        colors: [
          Color.lerp(idleA, const Color(0xFF5B8CFF), reveal)!,
          Color.lerp(idleB, const Color(0xFF9B59FF), reveal)!,
          Color.lerp(idleA, const Color(0xFF38BDF8), reveal)!,
          Color.lerp(idleB, const Color(0xFF7C3AED), reveal)!,
        ],
        stops: const [0.0, 0.33, 0.66, 1.0],
      );
    }

    return SweepGradient(
      transform: GradientRotation(angle),
      colors: const [
        Color(0xFF5B8CFF),
        Color(0xFF9B59FF),
        Color(0xFF38BDF8),
        Color(0xFF7C3AED),
        Color(0xFF5B8CFF),
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
    );
  }

  List<BoxShadow> _outerGlow(double reveal, double pulse) {
    final intensity = (reveal * 0.85 + pulse * 0.35).clamp(0.0, 1.0);
    if (intensity <= 0.02) return const [];

    return [
      BoxShadow(
        color: const Color(0xFF6366F1).withValues(alpha: 0.22 * intensity),
        blurRadius: 28 + pulse * 14,
        spreadRadius: 1 + pulse * 3,
      ),
      BoxShadow(
        color: const Color(0xFF38BDF8).withValues(alpha: 0.16 * intensity),
        blurRadius: 36 + pulse * 10,
        spreadRadius: -2,
        offset: Offset(-4 - pulse * 2, 0),
      ),
      BoxShadow(
        color: const Color(0xFFA855F7).withValues(alpha: 0.18 * intensity),
        blurRadius: 32 + pulse * 12,
        spreadRadius: -1,
        offset: Offset(4 + pulse * 2, 2),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: (isDark ? DropColors.darkBackground : DropColors.lightSurface)
            .withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: DropColors.border(context))),
      ),
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.55,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _revealController,
            _loopController,
            _pulseController,
          ]),
          builder: (context, child) {
            final reveal = _revealAnimation.value;
            final rotation = _loopController.value;
            final pulse = _pulseController.value;
            final glow = _outerGlow(reveal, pulse);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (glow.isNotEmpty)
                    Transform.scale(
                      scale: 1.04 + pulse * 0.03,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: glow,
                        ),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: _borderGradient(isDark, reveal, rotation),
                      boxShadow: reveal > 0.15
                          ? [
                              BoxShadow(
                                color: const Color(0xFF7C3AED)
                                    .withValues(alpha: 0.12 * reveal),
                                blurRadius: 16,
                                spreadRadius: 0.5,
                              ),
                            ]
                          : null,
                    ),
                    padding: const EdgeInsets.all(1.8),
                    child: child,
                  ),
                ],
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                if (widget.onOpenChat != null)
                  IconButton(
                    onPressed: widget.enabled ? widget.onOpenChat : null,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    color: DropColors.muted(context),
                    tooltip: 'Apri chat',
                  ),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    enabled: widget.enabled,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontSize: 13,
                                color: DropColors.muted(context),
                              ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: widget.enabled ? (_) => widget.onSend() : null,
                  ),
                ),
                IconButton(
                  onPressed: widget.enabled ? widget.onSend : null,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                  color: Theme.of(context).colorScheme.onSurface,
                  tooltip: 'Invia',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/drop_gradients.dart';
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
  late final AnimationController _focusLoopController;
  late final AnimationController _idleLoopController;
  late final AnimationController _pulseController;
  late final Animation<double> _revealAnimation;

  bool get _isFocused => _focusNode.hasFocus;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocusChange);
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _focusLoopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _idleLoopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _revealAnimation = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _revealController.forward().then((_) {
        if (mounted && _focusNode.hasFocus) {
          _focusLoopController.repeat();
          _pulseController.repeat(reverse: true);
        }
      });
    } else {
      _stopFocusEffects();
    }
    setState(() {});
  }

  void _stopFocusEffects() {
    _focusLoopController.stop();
    _focusLoopController.reset();
    _pulseController.stop();
    _pulseController.reset();
    _revealController.reverse();
  }

  @override
  void dispose() {
    _focusNode.unfocus();
    _stopFocusEffects();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _revealController.dispose();
    _focusLoopController.dispose();
    _idleLoopController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Gradient _borderGradient(
    bool isDark,
    double reveal,
    double rotation,
    bool focused,
  ) {
    final t = focused ? reveal : 0.0;
    return DropGradients.chatSweep(
      rotation: rotation,
      intensity: focused ? math.max(t, 0.35) : t,
      isDark: isDark,
    );
  }

  List<BoxShadow> _outerGlow(double reveal, double pulse) =>
      DropGradients.chatGlow(reveal, pulse: pulse);

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
            _focusLoopController,
            _idleLoopController,
            _pulseController,
          ]),
          builder: (context, child) {
            final reveal = _revealAnimation.value;
            final rotation = _isFocused
                ? _focusLoopController.value
                : _idleLoopController.value;
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
                      gradient: _borderGradient(
                        isDark,
                        reveal,
                        rotation,
                        _isFocused,
                      ),
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

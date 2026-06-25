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
  late final Animation<double> _revealAnimation;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocusChange);
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
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
        }
      });
    } else {
      _loopController.stop();
      _loopController.reset();
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
    super.dispose();
  }

  Gradient _buildBorderGradient(bool isDark, double reveal, double rotation) {
    final angle = rotation * 2 * 3.1415926535;

    if (reveal < 1.0) {
      final monoStart = isDark
          ? Colors.white.withValues(alpha: 0.35)
          : Colors.black.withValues(alpha: 0.12);
      final monoEnd = isDark
          ? Colors.black.withValues(alpha: 0.6)
          : Colors.white.withValues(alpha: 0.85);
      final colorStart = Color.lerp(monoStart, Colors.blue.withValues(alpha: 0.7), reveal)!;
      final colorEnd = Color.lerp(monoEnd, Colors.purple.withValues(alpha: 0.7), reveal)!;

      return SweepGradient(
        startAngle: 0,
        endAngle: 6.283185307,
        transform: GradientRotation(angle),
        colors: [colorStart, colorEnd, colorStart],
        stops: const [0.0, 0.5, 1.0],
      );
    }

    return SweepGradient(
      startAngle: 0,
      endAngle: 6.283185307,
      transform: GradientRotation(angle),
      colors: [
        Colors.blue.withValues(alpha: 0.65),
        Colors.purple.withValues(alpha: 0.65),
        Colors.blue.withValues(alpha: 0.35),
        Colors.purple.withValues(alpha: 0.65),
      ],
      stops: const [0.0, 0.33, 0.66, 1.0],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFocused = _focusNode.hasFocus;

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
          animation: Listenable.merge([_revealController, _loopController]),
          builder: (context, child) {
            final reveal = _revealAnimation.value;
            final rotation = _loopController.value;

            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: _buildBorderGradient(isDark, reveal, rotation),
                boxShadow: isFocused
                    ? [
                        BoxShadow(
                          color: Colors.purple.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              padding: const EdgeInsets.all(1.5),
              child: child,
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
                      hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            color: DropColors.muted(context),
                          ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
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

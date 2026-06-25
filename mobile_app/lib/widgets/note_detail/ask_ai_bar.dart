import 'package:flutter/material.dart';

import '../../theme/drop_theme.dart';

class AskAiBar extends StatelessWidget {
  const AskAiBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.onOpenChat,
    this.enabled = true,
    this.hintText = 'ASK DROP ABOUT THIS NOTE...',
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onOpenChat;
  final bool enabled;
  final String hintText;

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
        opacity: enabled ? 1 : 0.55,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                Colors.blue.withValues(alpha: 0.5),
                Colors.purple.withValues(alpha: 0.5),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(1.5),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                if (onOpenChat != null)
                  IconButton(
                    onPressed: enabled ? onOpenChat : null,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    color: DropColors.muted(context),
                    tooltip: 'Apri chat',
                  ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 0.8,
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle:
                          Theme.of(context).textTheme.labelSmall?.copyWith(
                                letterSpacing: 0.8,
                                fontSize: 11,
                                color: DropColors.muted(context),
                              ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: enabled ? (_) => onSend() : null,
                  ),
                ),
                IconButton(
                  onPressed: enabled ? onSend : null,
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

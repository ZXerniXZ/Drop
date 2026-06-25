import 'package:flutter/material.dart';

import '../../theme/drop_theme.dart';

class AskAiBar extends StatelessWidget {
  const AskAiBar({
    super.key,
    required this.controller,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                  decoration: InputDecoration(
                    hintText: 'ASK DROP ABOUT THIS NOTE...',
                    hintStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 0.8,
                          fontSize: 11,
                          color: DropColors.muted(context),
                        ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                ),
              ),
              IconButton(
                onPressed: onSend,
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                color: Theme.of(context).colorScheme.onSurface,
                tooltip: 'Invia',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

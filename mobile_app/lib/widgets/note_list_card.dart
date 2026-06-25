import 'package:flutter/material.dart';

import '../models/audio_note.dart';
import '../theme/drop_motion.dart';
import '../theme/drop_theme.dart';

class NoteListCard extends StatelessWidget {
  const NoteListCard({
    super.key,
    required this.note,
    required this.dateLabel,
    required this.onTap,
    required this.onDelete,
    this.onRetry,
  });

  final AudioNote note;
  final String dateLabel;
  final VoidCallback? onTap;
  final VoidCallback onDelete;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isProcessing = note.isProcessing;
    final isFailed = note.isFailed;
    final preview = isProcessing
        ? 'Analisi in corso...'
        : isFailed
            ? (note.transcription.isNotEmpty
                ? note.transcription
                : 'Analisi fallita')
            : note.transcription.isNotEmpty
                ? note.transcription
                : note.rawTranscription;

    return Material(
      color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
      borderRadius: BorderRadius.circular(16),
      child: _PressableCard(
        onTap: onTap,
        onLongPress: isProcessing ? null : () => _confirmDelete(context),
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: isProcessing ? 0.75 : 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isProcessing
                    ? DropColors.recordRed.withValues(alpha: 0.25)
                    : isFailed
                        ? DropColors.recordRed.withValues(alpha: 0.4)
                        : DropColors.border(context),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        note.title,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (note.isNew && !isProcessing) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          color: DropColors.recordRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                    if (isProcessing) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                if (note.isNew && !isProcessing) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: DropColors.recordRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Nuova',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: DropColors.recordRed,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: isFailed
                              ? DropColors.recordRed.withValues(alpha: 0.85)
                              : DropColors.muted(context),
                          fontStyle: isProcessing || isFailed
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                  ),
                ],
                if (isFailed && onRetry != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Riprova analisi'),
                      style: TextButton.styleFrom(
                        foregroundColor: DropColors.recordRed,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  [
                    dateLabel,
                    if (note.durationLabel.isNotEmpty) note.durationLabel,
                    note.tag,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.2,
                        fontWeight: FontWeight.w500,
                        color: DropColors.muted(context),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina nota'),
        content: Text('Vuoi eliminare "${note.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Elimina',
              style: TextStyle(color: DropColors.recordRed),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) onDelete();
  }
}

class _PressableCard extends StatefulWidget {
  const _PressableCard({
    required this.child,
    required this.borderRadius,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.985 : 1.0,
      duration: DropMotion.fast,
      curve: DropMotion.standard,
      child: InkWell(
        onTapDown: widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
        onTapUp: widget.onTap != null ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: widget.borderRadius,
        splashColor: DropColors.recordRed.withValues(alpha: 0.06),
        highlightColor: DropColors.recordRed.withValues(alpha: 0.03),
        child: widget.child,
      ),
    );
  }
}

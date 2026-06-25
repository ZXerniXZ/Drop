import 'package:flutter/material.dart';

import '../models/audio_note.dart';
import '../theme/drop_theme.dart';

class NoteListCard extends StatelessWidget {
  const NoteListCard({
    super.key,
    required this.note,
    required this.dateLabel,
    required this.onTap,
    required this.onDelete,
  });

  final AudioNote note;
  final String dateLabel;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final preview = note.transcription.isNotEmpty
        ? note.transcription
        : note.rawTranscription;

    return Material(
      color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _confirmDelete(context),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DropColors.border(context)),
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
              Text(
                note.title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: DropColors.muted(context),
                      ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 13,
                    color: DropColors.muted(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    dateLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  if (note.durationLabel.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Icon(
                      Icons.schedule_outlined,
                      size: 13,
                      color: DropColors.muted(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      note.durationLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            letterSpacing: 0.4,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                  if (note.summary.isNotEmpty) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: DropColors.recordRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'RIEPILOGO',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: DropColors.recordRed,
                              fontSize: 9,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
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

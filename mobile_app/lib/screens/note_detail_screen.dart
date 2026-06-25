import 'package:flutter/material.dart';

import '../models/audio_note.dart';

class NoteDetailScreen extends StatelessWidget {
  const NoteDetailScreen({super.key, required this.note});

  final AudioNote note;

  String _formatTimestamp(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final displayText = note.transcription.isNotEmpty
        ? note.transcription
        : note.rawTranscription;

    return Scaffold(
      appBar: AppBar(
        title: Text(note.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _formatTimestamp(note.dateTime),
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          Text(
            'Trascrizione',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            displayText.isEmpty ? '(Trascrizione vuota)' : displayText,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (note.summary.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Riepilogo',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              note.summary,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (note.rawTranscription.isNotEmpty &&
              note.rawTranscription != note.transcription) ...[
            const SizedBox(height: 24),
            Text(
              'Trascrizione grezza',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              note.rawTranscription,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade400,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

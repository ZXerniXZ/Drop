import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/audio_note.dart';
import '../theme/drop_theme.dart';

enum _DetailTab { summary, transcription }

class NoteDetailScreen extends StatefulWidget {
  const NoteDetailScreen({
    super.key,
    required this.note,
    required this.onDelete,
  });

  final AudioNote note;
  final VoidCallback onDelete;

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  _DetailTab _activeTab = _DetailTab.summary;

  String _formatTimestamp(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina nota'),
        content: Text('Vuoi eliminare "${widget.note.title}"?'),
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

    if (confirmed != true || !mounted) return;
    widget.onDelete();
    Navigator.of(context).pop();
  }

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiato negli appunti')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayText = widget.note.transcription.isNotEmpty
        ? widget.note.transcription
        : widget.note.rawTranscription;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.chevron_left, size: 28),
                    color: DropColors.muted(context),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _confirmDelete,
                    icon: const Icon(Icons.delete_outline, size: 22),
                    color: DropColors.muted(context),
                    tooltip: 'Elimina',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _TabBar(
                activeTab: _activeTab,
                onChanged: (tab) => setState(() => _activeTab = tab),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  Text(
                    widget.note.title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w300,
                          height: 1.25,
                        ),
                  ),
                  const SizedBox(height: 20),
                  _MetadataCard(
                    dateTime: _formatTimestamp(widget.note.dateTime),
                  ),
                  const SizedBox(height: 24),
                  if (_activeTab == _DetailTab.summary) ...[
                    _SectionHeader(label: 'OVERVIEW SUMMARY'),
                    const SizedBox(height: 12),
                    if (widget.note.summary.isNotEmpty)
                      Text(
                        widget.note.summary,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.85),
                            ),
                      )
                    else
                      _EmptyState(
                        message: 'Nessun riepilogo disponibile per questa nota.',
                      ),
                    if (widget.note.summary.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _CopyButton(
                        label: 'COPIA MARKDOWN',
                        onTap: () => _copyText(widget.note.summary, 'Riepilogo'),
                      ),
                    ],
                  ] else ...[
                    _SectionHeader(label: 'TRASCRIZIONE'),
                    const SizedBox(height: 12),
                    if (displayText.isNotEmpty)
                      Text(
                        displayText,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.85),
                            ),
                      )
                    else
                      const _EmptyState(
                        message: 'Trascrizione vuota.',
                      ),
                    if (widget.note.rawTranscription.isNotEmpty &&
                        widget.note.rawTranscription != widget.note.transcription) ...[
                      const SizedBox(height: 28),
                      _SectionHeader(label: 'TRASCRIZIONE GREZZA'),
                      const SizedBox(height: 12),
                      Text(
                        widget.note.rawTranscription,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 13,
                              color: DropColors.muted(context),
                            ),
                      ),
                    ],
                    if (displayText.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _CopyButton(
                        label: 'COPIA TESTO',
                        onTap: () => _copyText(displayText, 'Trascrizione'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.activeTab,
    required this.onChanged,
  });

  final _DetailTab activeTab;
  final ValueChanged<_DetailTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _TabPill(
            label: 'Summary',
            isActive: activeTab == _DetailTab.summary,
            onTap: () => onChanged(_DetailTab.summary),
          ),
          const SizedBox(width: 8),
          _TabPill(
            label: 'Trascrizione',
            isActive: activeTab == _DetailTab.transcription,
            onTap: () => onChanged(_DetailTab.transcription),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? Colors.white : Colors.black)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isActive
                    ? (isDark ? Colors.black : Colors.white)
                    : DropColors.muted(context),
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  const _MetadataCard({required this.dateTime});

  final String dateTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DropColors.border(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'DATE & TIME:',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Flexible(
            child: Text(
              dateTime,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.4,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 11,
            letterSpacing: 1.6,
          ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.upload_outlined, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: DropColors.border(context)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(
          color: DropColors.border(context),
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message.toUpperCase(),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/note_detail_mock_data.dart';
import '../models/audio_note.dart';
import '../models/note_structured_data.dart';
import '../theme/drop_theme.dart';
import '../widgets/note_detail/ask_ai_bar.dart';
import '../widgets/note_detail/note_audio_player.dart';

enum _DetailMode { sources, notes }

enum _NotesSubTab { highlights, summary, speakerView, keyData }

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
  _DetailMode _mode = _DetailMode.notes;
  _NotesSubTab _subTab = _NotesSubTab.summary;
  final _askAiController = TextEditingController();
  final Map<int, bool> _checkedItems = {};

  @override
  void dispose() {
    _askAiController.dispose();
    super.dispose();
  }

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

  void _onAskAiSend() {
    final text = _askAiController.text.trim();
    if (text.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ask AI — funzione in arrivo')),
    );
    _askAiController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            if (_mode == _DetailMode.notes) _buildSubTabBar(context),
            Expanded(
              child: _mode == _DetailMode.sources
                  ? NoteAudioPlayer(
                      audioPath: widget.note.audioPath,
                      fallbackDurationSeconds: widget.note.durationSeconds,
                    )
                  : _buildNotesContent(context),
            ),
            AskAiBar(
              controller: _askAiController,
              onSend: _onAskAiSend,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.chevron_left, size: 28),
            color: DropColors.muted(context),
          ),
          Expanded(child: Center(child: _ModeToggle(
            mode: _mode,
            onChanged: (m) => setState(() => _mode = m),
          ))),
          IconButton(
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete_outline, size: 22),
            color: DropColors.muted(context),
            tooltip: 'Elimina',
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabBar(BuildContext context) {
    const tabs = _NotesSubTab.values;
    const labels = ['Highlights', 'Summary', 'Speaker View', 'Key Data'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final tab = tabs[i];
          final isActive = _subTab == tab;
          return Padding(
            padding: EdgeInsets.only(right: i < tabs.length - 1 ? 8 : 0),
            child: _TabPill(
              label: labels[i],
              isActive: isActive,
              onTap: () => setState(() => _subTab = tab),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNotesContent(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      children: [
        Text(
          widget.note.title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w300,
                height: 1.25,
              ),
        ),
        const SizedBox(height: 16),
        _MetadataCard(dateTime: _formatTimestamp(widget.note.dateTime)),
        const SizedBox(height: 20),
        switch (_subTab) {
          _NotesSubTab.highlights => _HighlightsTab(
              highlights: widget.note.structuredData.highlights,
              checkedItems: _checkedItems,
              onToggle: (i, v) => setState(() => _checkedItems[i] = v),
            ),
          _NotesSubTab.summary => _SummaryTab(note: widget.note),
          _NotesSubTab.speakerView => _SpeakerViewTab(
              blocks: widget.note.structuredData.speakerView,
            ),
          _NotesSubTab.keyData => _KeyDataTab(
              location: widget.note.structuredData.location,
              participants: widget.note.structuredData.participants,
              tag: widget.note.tag.label,
            ),
        },
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.mode,
    required this.onChanged,
  });

  final _DetailMode mode;
  final ValueChanged<_DetailMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: DropColors.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            label: 'Sources',
            isActive: mode == _DetailMode.sources,
            onTap: () => onChanged(_DetailMode.sources),
          ),
          _ModeButton(
            label: 'Notes',
            isActive: mode == _DetailMode.notes,
            onTap: () => onChanged(_DetailMode.notes),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? DropColors.darkSurface : DropColors.lightSurface)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isActive
              ? Border.all(color: DropColors.border(context))
              : null,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: isActive
                    ? Theme.of(context).colorScheme.onSurface
                    : DropColors.muted(context),
              ),
        ),
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
          Text('DATE & TIME:', style: Theme.of(context).textTheme.labelSmall),
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

class _HighlightsTab extends StatelessWidget {
  const _HighlightsTab({
    required this.highlights,
    required this.checkedItems,
    required this.onToggle,
  });

  final List<String> highlights;
  final Map<int, bool> checkedItems;
  final void Function(int index, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    final items = highlights.isNotEmpty
        ? highlights
        : NoteDetailMockData.actionItems.map((e) => e.text).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Mappa mentale — in arrivo')),
            );
          },
          icon: const Icon(Icons.auto_awesome_outlined, size: 16),
          label: const Text('GENERA MAPPA MENTALE'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(color: DropColors.border(context)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'ACTION ITEMS',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.6,
              ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Text(
            'Nessun highlight disponibile.',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          ...List.generate(items.length, (i) {
          final text = items[i];
          final checked = checkedItems[i] ?? false;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => onToggle(i, !checked),
                  child: Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: DropColors.border(context)),
                      color: checked
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                    ),
                    child: checked
                        ? Icon(
                            Icons.circle,
                            size: 8,
                            color: Theme.of(context).colorScheme.surface,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.9),
                        ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.note});

  final AudioNote note;

  @override
  Widget build(BuildContext context) {
    final paragraphs =
        NoteDetailMockData.summaryParagraphs(note.summary.isNotEmpty ? note.summary : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'OVERVIEW SUMMARY',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.6,
                  ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: DropColors.border(context)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'MEETING TEMPLATE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...paragraphs.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              p,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.85),
                  ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: paragraphs.join('\n\n')));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Riepilogo copiato negli appunti')),
            );
          },
          icon: const Icon(Icons.upload_outlined, size: 16),
          label: const Text('COPIA MARKDOWN'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(color: DropColors.border(context)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}

class _SpeakerViewTab extends StatelessWidget {
  const _SpeakerViewTab({required this.blocks});

  final List<SpeakerBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final displayBlocks = blocks.isNotEmpty
        ? blocks
        : NoteDetailMockData.speakerBlocks
            .map(
              (b) => SpeakerBlock(
                speaker: b.speaker,
                text: b.text,
                time: b.time,
              ),
            )
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: DropColors.border(context)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'CERCA NELLA TRASCRIZIONE...',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: DropColors.muted(context),
                  letterSpacing: 0.8,
                ),
          ),
        ),
        const SizedBox(height: 20),
        if (displayBlocks.isEmpty)
          Text(
            'Nessun blocco speaker disponibile.',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          ...displayBlocks.map((block) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: DropColors.muted(context).withValues(alpha: 0.5),
                  ),
                ),
              ),
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        block.speaker.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                      if (block.time != null && block.time!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          '[${block.time}]',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: DropColors.muted(context),
                              ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: DropColors.border(context)),
                    ),
                    child: Text(
                      block.text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.9),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _KeyDataTab extends StatelessWidget {
  const _KeyDataTab({
    required this.location,
    required this.participants,
    required this.tag,
  });

  final String location;
  final List<String> participants;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final displayLocation =
        location.isNotEmpty ? location : NoteDetailMockData.location;
    final displayAttendees = participants.isNotEmpty
        ? participants.join(', ')
        : NoteDetailMockData.attendees;
    final displayTag = tag.isNotEmpty ? tag : 'Diario';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DropColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KeyDataRow(
            label: 'LOCATION:',
            value: displayLocation,
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Text(
            'ATTENDEES:',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          Text(
            displayAttendees,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 16),
          _KeyDataRow(
            label: 'TAG:',
            value: displayTag,
          ),
        ],
      ),
    );
  }
}

class _KeyDataRow extends StatelessWidget {
  const _KeyDataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.4,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ),
      ],
    );
  }
}

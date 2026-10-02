import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/audio_note.dart';
import '../models/note_structured_data.dart';
import '../services/app_preferences_service.dart';
import '../services/local_database_service.dart';
import '../services/note_analysis_service.dart';
import '../services/note_share_service.dart';
import '../theme/drop_theme.dart';
import '../widgets/drop_markdown.dart';
import '../widgets/note_detail/analysis_picker.dart';
import '../widgets/note_detail/ask_ai_bar.dart';
import '../widgets/note_detail/highlights_section.dart';
import '../widgets/note_detail/key_data_section.dart';
import '../widgets/note_detail/note_chat_sheet.dart';
import '../widgets/note_detail/note_audio_player.dart';
import '../widgets/note_detail/speakers_section.dart';

enum _DetailMode { sources, notes }

enum _NotesPage { summary, picker, highlights, speakers, keyData }

class NoteDetailScreen extends StatefulWidget {
  const NoteDetailScreen({
    super.key,
    required this.note,
    required this.onDelete,
    this.onRetry,
    this.onReanalyze,
    this.onChanged,
  });

  final AudioNote note;
  final VoidCallback onDelete;
  final VoidCallback? onRetry;
  final VoidCallback? onReanalyze;
  final ValueChanged<AudioNote>? onChanged;

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  _DetailMode _mode = _DetailMode.notes;
  _NotesPage _page = _NotesPage.summary;
  late AudioNote _note;
  final _askAiController = TextEditingController();
  final _running = <String>{};

  @override
  void initState() {
    super.initState();
    _note = widget.note;
  }

  @override
  void dispose() {
    _askAiController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina nota'),
        content: Text('Vuoi eliminare "${_note.title}"?'),
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

  Future<void> _confirmReanalyze() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rifai analisi'),
        content: const Text(
          'L\'audio verra\' trascritto di nuovo e il riassunto breve rifatto. '
          'Highlights, voci e dati gia\' generati vengono azzerati.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rifai'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    widget.onReanalyze!();
    Navigator.of(context).pop();
  }

  Future<void> _shareNote() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    try {
      final prefs = await AppPreferencesService.instance.loadAiPreferences();
      final url = await NoteShareService.instance.createShareUrl(
        _note,
        prefs: prefs,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Condividi nota'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Chi apre il link accede a Drop e riceve una copia della nota nella propria libreria.',
              ),
              const SizedBox(height: 12),
              SelectableText(
                url,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await NoteShareService.instance.revokeShare(_note.id);
                if (context.mounted) Navigator.pop(context, 'revoked');
              },
              child: const Text(
                'Revoca',
                style: TextStyle(color: DropColors.recordRed),
              ),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (context.mounted) Navigator.pop(context, 'copied');
              },
              child: const Text('Copia link'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (action == 'copied') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copiato')),
        );
      } else if (action == 'revoked') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link revocato')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  void _onAskAiSend() {
    final text = _askAiController.text.trim();
    if (text.isEmpty) {
      _openChatSheet();
      return;
    }
    _openChatSheet(initialMessage: text);
    _askAiController.clear();
  }

  void _openChatSheet({String? initialMessage}) {
    showNoteChatSheet(
      context,
      note: _note,
      initialMessage: initialMessage,
    );
  }

  void _goBack() {
    if (_mode == _DetailMode.notes && _page == _NotesPage.picker) {
      setState(() => _page = _NotesPage.summary);
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _toggleHighlight(String text, bool checked) async {
    final current = List<String>.from(_note.structuredData.checkedHighlights);
    if (checked) {
      if (!current.contains(text)) current.add(text);
    } else {
      current.remove(text);
    }
    final updated = _note.copyWith(
      structuredData: _note.structuredData.copyWith(checkedHighlights: current),
    );
    setState(() => _note = updated);
    await LocalDatabaseService.instance.saveNote(updated);
    widget.onChanged?.call(updated);
  }

  Future<void> _selectAnalysis(String kind) async {
    if (_note.structuredData.isReady(kind)) {
      setState(() => _page = _pageFor(kind));
      return;
    }
    if (_running.contains(kind)) return;

    setState(() => _running.add(kind));
    try {
      final updated = await NoteAnalysisService.instance.run(
        note: _note,
        kind: kind,
      );
      if (!mounted) {
        widget.onChanged?.call(updated);
        return;
      }
      setState(() {
        _note = updated;
        if (_page == _NotesPage.picker) _page = _pageFor(kind);
      });
      widget.onChanged?.call(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _running.remove(kind));
    }
  }

  _NotesPage _pageFor(String kind) {
    return switch (kind) {
      NoteStructuredData.speakersKind => _NotesPage.speakers,
      NoteStructuredData.keyDataKind => _NotesPage.keyData,
      _ => _NotesPage.highlights,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            if (_note.isFailed) _buildFailedBanner(context),
            if (_mode == _DetailMode.notes && _page != _NotesPage.picker)
              _buildSectionBar(context),
            Expanded(
              child: _mode == _DetailMode.sources
                  ? NoteAudioPlayer(
                      noteId: _note.id,
                      audioPath: _note.audioPath,
                      fallbackDurationSeconds: _note.durationSeconds,
                      segments: _note.transcriptSegments,
                    )
                  : _buildNotesBody(context),
            ),
            AskAiBar(
              controller: _askAiController,
              onSend: _onAskAiSend,
              onOpenChat: () => _openChatSheet(),
              enabled: !_note.isProcessing && !_note.isFailed,
              hintText: _note.isProcessing
                  ? 'Analisi in corso...'
                  : _note.isFailed
                      ? 'Analisi fallita'
                      : 'Chiedi a Drop su questa nota...',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DropColors.recordRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DropColors.recordRed.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Analisi fallita',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: DropColors.recordRed,
                  letterSpacing: 1,
                ),
          ),
          if (_note.transcription.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _note.transcription,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: DropColors.recordRed.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
            ),
          ],
          if (widget.onRetry != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  widget.onRetry!();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Riprova analisi'),
                style: TextButton.styleFrom(
                  foregroundColor: DropColors.recordRed,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: _goBack,
            icon: const Icon(Icons.chevron_left, size: 28),
            color: DropColors.muted(context),
          ),
          Expanded(
            child: Center(
              child: _ModeToggle(
                mode: _mode,
                onChanged: (mode) => setState(() => _mode = mode),
              ),
            ),
          ),
          if (widget.onReanalyze != null)
            IconButton(
              onPressed: _confirmReanalyze,
              icon: const Icon(Icons.autorenew, size: 22),
              color: DropColors.muted(context),
              tooltip: 'Rifai analisi',
            ),
          if (!_note.isFailed)
            IconButton(
              onPressed: _shareNote,
              icon: const Icon(Icons.ios_share, size: 22),
              color: DropColors.muted(context),
              tooltip: 'Condividi',
            ),
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

  Widget _buildSectionBar(BuildContext context) {
    final data = _note.structuredData;
    final tabs = <({String label, _NotesPage page})>[
      if (data.isReady(NoteStructuredData.highlightsKind))
        (label: 'Highlights', page: _NotesPage.highlights),
      (label: 'Summary', page: _NotesPage.summary),
      if (data.isReady(NoteStructuredData.speakersKind))
        (label: 'Speakers', page: _NotesPage.speakers),
      if (data.isReady(NoteStructuredData.keyDataKind))
        (label: 'Key data', page: _NotesPage.keyData),
    ];
    final showAdd = !_note.isFailed &&
        !(data.isReady(NoteStructuredData.highlightsKind) &&
            data.isReady(NoteStructuredData.speakersKind) &&
            data.isReady(NoteStructuredData.keyDataKind));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _TabPill(
              label: tabs[i].label,
              isActive: _page == tabs[i].page,
              onTap: () => setState(() => _page = tabs[i].page),
            ),
          ],
          if (showAdd) ...[
            const SizedBox(width: 8),
            _AddPill(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _page = _NotesPage.picker);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotesBody(BuildContext context) {
    if (_page == _NotesPage.picker) {
      return AnalysisPicker(
        data: _note.structuredData,
        running: _running,
        onSelect: _selectAnalysis,
      );
    }

    final summary = _note.summary.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      children: [
        Text(
          _note.title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w300,
                height: 1.25,
              ),
        ),
        const SizedBox(height: 20),
        switch (_page) {
          _NotesPage.summary => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (summary.isEmpty)
                  const SizedBox.shrink()
                else
                  DropMarkdown(data: summary),
              ],
            ),
          _NotesPage.highlights => HighlightsSection(
              highlights: _note.structuredData.highlights,
              checked: _note.structuredData.checkedHighlights,
              onToggle: (text, value) => _toggleHighlight(text, value),
            ),
          _NotesPage.speakers => SpeakersSection(
              blocks: _note.structuredData.speakerView,
            ),
          _NotesPage.keyData => KeyDataSection(data: _note.structuredData),
          _NotesPage.picker => const SizedBox.shrink(),
        },
      ],
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
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isActive
                    ? (isDark ? Colors.black : Colors.white)
                    : DropColors.muted(context),
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
        ),
      ),
    );
  }
}

class _AddPill extends StatelessWidget {
  const _AddPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: DropColors.border(context)),
        ),
        child: Icon(
          Icons.add,
          size: 16,
          color: DropColors.muted(context),
        ),
      ),
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
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
                letterSpacing: 0.2,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive
                    ? Theme.of(context).colorScheme.onSurface
                    : DropColors.muted(context),
              ),
        ),
      ),
    );
  }
}

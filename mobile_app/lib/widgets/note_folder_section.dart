import 'package:flutter/material.dart';

import '../models/note_folder.dart';
import '../theme/drop_motion.dart';
import '../theme/drop_theme.dart';
import '../utils/note_library.dart';

/// Barra delle cartelle in home: creazione, apertura, eliminazione e
/// rilascio di una nota trascinata.
class NoteFolderBar extends StatelessWidget {
  const NoteFolderBar({
    super.key,
    required this.folders,
    required this.noteCount,
    required this.dragging,
    required this.onCreate,
    required this.onOpen,
    required this.onDelete,
    required this.onDropNote,
  });

  final List<NoteFolder> folders;
  final int Function(String folderId) noteCount;
  final bool dragging;
  final VoidCallback onCreate;
  final ValueChanged<NoteFolder> onOpen;
  final ValueChanged<NoteFolder> onDelete;
  final void Function(String noteId, String folderId) onDropNote;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 78,
            child: Row(
              children: [
                const SizedBox(width: 24),
                _NewFolderTile(onTap: onCreate),
                const SizedBox(width: 10),
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 24),
                    itemCount: folders.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      return _FolderTile(
                        key: ValueKey(folder.id),
                        folder: folder,
                        countLabel: folderNotesLabel(noteCount(folder.id)),
                        dragging: dragging,
                        onOpen: () => onOpen(folder),
                        onDelete: () => onDelete(folder),
                        onDropNote: (noteId) => onDropNote(noteId, folder.id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (folders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(
                'Tieni premuta una nota e rilasciala su una cartella.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      color: DropColors.muted(context),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NewFolderTile extends StatelessWidget {
  const _NewFolderTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('create-folder'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
          child: Ink(
          width: 124,
          height: 78,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DropColors.border(context)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.create_new_folder_outlined, size: 20, color: DropColors.muted(context)),
              const SizedBox(height: 6),
              Text(
                'Nuova cartella',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    super.key,
    required this.folder,
    required this.countLabel,
    required this.dragging,
    required this.onOpen,
    required this.onDelete,
    required this.onDropNote,
  });

  final NoteFolder folder;
  final String countLabel;
  final bool dragging;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final ValueChanged<String> onDropNote;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onDropNote(details.data),
      builder: (context, candidate, rejected) {
        final hovered = candidate.isNotEmpty;
        final borderColor = hovered
            ? DropColors.recordRed
            : dragging
                ? DropColors.recordRed.withValues(alpha: 0.45)
                : DropColors.border(context);
        return AnimatedScale(
          scale: hovered ? 1.04 : 1,
          duration: DropMotion.fast,
          curve: DropMotion.standard,
          child: AnimatedContainer(
            duration: DropMotion.fast,
            curve: DropMotion.standard,
            width: 168,
            height: 78,
            decoration: BoxDecoration(
              color: hovered
                  ? DropColors.recordRed.withValues(alpha: isDark ? 0.16 : 0.08)
                  : (isDark ? DropColors.darkSurface : DropColors.lightSurface),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 22,
                        color: hovered
                            ? DropColors.recordRed
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              folder.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              countLabel,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: DropColors.muted(context),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: Key('delete-folder-${folder.id}'),
                        tooltip: 'Elimina cartella',
                        visualDensity: VisualDensity.compact,
                        onPressed: onDelete,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: DropColors.muted(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Compare dal basso quando, dentro una cartella, si trascina una nota.
class MoveOutFolderTarget extends StatelessWidget {
  const MoveOutFolderTarget({
    super.key,
    required this.visible,
    required this.onAccept,
  });

  final bool visible;
  final ValueChanged<String> onAccept;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion ? Duration.zero : DropMotion.medium;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1.25),
        duration: duration,
        curve: DropMotion.spring,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          curve: DropMotion.enter,
          child: DragTarget<String>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (details) => onAccept(details.data),
            builder: (context, candidate, rejected) {
              final hovered = candidate.isNotEmpty;
              return AnimatedContainer(
                key: const Key('move-out-folder'),
                duration: DropMotion.fast,
                curve: DropMotion.standard,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: hovered
                      ? DropColors.recordRed.withValues(alpha: isDark ? 0.22 : 0.1)
                      : (isDark ? DropColors.darkSurface : DropColors.lightSurface),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hovered
                        ? DropColors.recordRed
                        : DropColors.border(context),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: DropMotion.fast,
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: DropColors.recordRed.withValues(
                          alpha: hovered ? 0.18 : 0.1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.drive_file_move_outline,
                        size: 18,
                        color: hovered
                            ? DropColors.recordRed
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hovered ? 'Rilascia ora' : 'Fuori dalla cartella',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hovered
                                ? 'La nota torna nella home'
                                : 'Rilascia la nota qui',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  fontSize: 11,
                                  color: DropColors.muted(context),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Tocco prolungato, poi trascinamento. Lo swipe resta libero per
/// condividere ed eliminare.
class DraggableLibraryNote extends StatelessWidget {
  const DraggableLibraryNote({
    super.key,
    required this.noteId,
    required this.title,
    required this.child,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final String noteId;
  final String title;
  final Widget child;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width - 72;

    return LongPressDraggable<String>(
      data: noteId,
      delay: const Duration(milliseconds: 380),
      hapticFeedbackOnStart: true,
      maxSimultaneousDrags: 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnded(),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: width.clamp(180, 340),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: DropColors.recordRed.withValues(alpha: 0.55),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
  }
}

Future<String?> showCreateFolderDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _CreateFolderDialog(),
  );
}

class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog();

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canCreate = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Nuova cartella'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nome',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Riunioni, lezioni...',
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: DropColors.border(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: DropColors.border(context)),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        TextButton(
          onPressed: canCreate ? _submit : null,
          child: const Text('Crea'),
        ),
      ],
    );
  }
}

Future<bool> confirmDeleteFolder(BuildContext context, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Elimina cartella'),
      content: Text(
        'Le note in "$name" tornano nella home.',
      ),
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
  return confirmed == true;
}

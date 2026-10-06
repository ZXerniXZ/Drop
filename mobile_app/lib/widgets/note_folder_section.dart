import 'package:flutter/material.dart';

import '../models/note_folder.dart';
import '../theme/drop_motion.dart';
import '../theme/drop_theme.dart';

/// Riga di cartelle: chip sottili, non card.
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
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            const SizedBox(width: 24),
            _NewFolderChip(onTap: onCreate),
            const SizedBox(width: 8),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 24),
                itemCount: folders.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final folder = folders[index];
                  return _FolderChip(
                    key: ValueKey(folder.id),
                    folder: folder,
                    noteCount: noteCount(folder.id),
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
    );
  }
}

class _NewFolderChip extends StatelessWidget {
  const _NewFolderChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('create-folder'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: DropColors.border(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 15, color: DropColors.muted(context)),
              const SizedBox(width: 4),
              Text(
                'Nuova',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
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

class _FolderChip extends StatelessWidget {
  const _FolderChip({
    super.key,
    required this.folder,
    required this.noteCount,
    required this.dragging,
    required this.onOpen,
    required this.onDelete,
    required this.onDropNote,
  });

  final NoteFolder folder;
  final int noteCount;
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
        return AnimatedContainer(
          duration: DropMotion.fast,
          curve: DropMotion.standard,
          height: 34,
          decoration: BoxDecoration(
            color: hovered
                ? DropColors.recordRed.withValues(alpha: isDark ? 0.16 : 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: borderColor),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(17),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 15,
                      color: hovered
                          ? DropColors.recordRed
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 148),
                      child: Text(
                        folder.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                    ),
                    if (noteCount > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '$noteCount',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 11,
                              color: DropColors.muted(context),
                            ),
                      ),
                    ],
                    Tooltip(
                      message: 'Elimina cartella',
                      child: InkWell(
                        key: Key('delete-folder-${folder.id}'),
                        onTap: onDelete,
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.close,
                            size: 13,
                            color: DropColors.muted(context),
                          ),
                        ),
                      ),
                    ),
                  ],
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
    this.parentName,
  });

  final bool visible;
  final ValueChanged<String> onAccept;

  /// Cartella di livello sopra. Null: la nota torna nella home.
  final String? parentName;

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
              final parent = parentName;
              final restingSubtitle = parent == null
                  ? 'Rilascia la nota qui'
                  : 'Torna in $parent';
              final hoveredSubtitle = parent == null
                  ? 'La nota torna nella home'
                  : 'La nota torna in $parent';
              return AnimatedContainer(
                key: const Key('move-out-folder'),
                duration: DropMotion.fast,
                curve: DropMotion.standard,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      width: 32,
                      height: 32,
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
                            hovered ? hoveredSubtitle : restingSubtitle,
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

Future<String?> showCreateFolderDialog(
  BuildContext context, {
  String? insideName,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _CreateFolderDialog(insideName: insideName),
  );
}

class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog({this.insideName});

  final String? insideName;

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
          if (widget.insideName != null) ...[
            Text(
              'Dentro ${widget.insideName}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: DropColors.muted(context),
                  ),
            ),
            const SizedBox(height: 14),
          ],
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

Future<bool> confirmDeleteFolder(
  BuildContext context, {
  required String detail,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Elimina cartella'),
      content: Text(detail),
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

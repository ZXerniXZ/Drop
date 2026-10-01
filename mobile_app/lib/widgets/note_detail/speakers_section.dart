import 'package:flutter/material.dart';

import '../../models/note_structured_data.dart';
import '../../theme/drop_theme.dart';

class SpeakersSection extends StatefulWidget {
  const SpeakersSection({super.key, required this.blocks});

  final List<SpeakerBlock> blocks;

  @override
  State<SpeakersSection> createState() => _SpeakersSectionState();
}

class _SpeakersSectionState extends State<SpeakersSection> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final blocks = query.isEmpty
        ? widget.blocks
        : widget.blocks
            .where(
              (block) =>
                  block.text.toLowerCase().contains(query) ||
                  block.speaker.toLowerCase().contains(query),
            )
            .toList();
    final names = <String>[];
    for (final block in widget.blocks) {
      if (!names.contains(block.speaker)) names.add(block.speaker);
    }
    final monologue = names.length <= 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: Theme.of(context).textTheme.bodyMedium,
          cursorColor: Theme.of(context).colorScheme.onSurface,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Cerca',
            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: DropColors.muted(context),
                ),
            prefixIcon: Icon(
              Icons.search,
              size: 18,
              color: DropColors.muted(context),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: _border(context),
            enabledBorder: _border(context),
            focusedBorder: _border(context, focused: true),
          ),
        ),
        const SizedBox(height: 22),
        if (!monologue && names.length > 1) ...[
          _VoiceLegend(names: names),
          const SizedBox(height: 18),
        ],
        for (final block in blocks)
          monologue
              ? _MonologueLine(block: block)
              : _Turn(
                  block: block,
                  alignRight: names.indexOf(block.speaker).isOdd,
                ),
      ],
    );
  }

  OutlineInputBorder _border(BuildContext context, {bool focused = false}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: focused
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)
            : DropColors.border(context),
      ),
    );
  }
}

class _VoiceLegend extends StatelessWidget {
  const _VoiceLegend({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (var i = 0; i < names.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i.isOdd
                      ? DropColors.muted(context)
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                names[i],
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
      ],
    );
  }
}

class _MonologueLine extends StatelessWidget {
  const _MonologueLine({required this.block});

  final SpeakerBlock block;

  @override
  Widget build(BuildContext context) {
    final time = block.time?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (time.isNotEmpty) ...[
            Text(
              time,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: DropColors.muted(context),
                    letterSpacing: 0.4,
                  ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            block.text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

class _Turn extends StatelessWidget {
  const _Turn({required this.block, required this.alignRight});

  final SpeakerBlock block;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final time = block.time?.trim() ?? '';
    final caption = time.isEmpty ? block.speaker : '${block.speaker}  $time';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          child: Column(
            crossAxisAlignment:
                alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                caption,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: DropColors.muted(context),
                    ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: alignRight
                      ? Colors.transparent
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.035)),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: DropColors.border(context)),
                ),
                child: Text(
                  block.text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

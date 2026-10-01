import 'package:flutter/material.dart';

import '../../models/note_structured_data.dart';
import '../../theme/drop_theme.dart';

class KeyDataSection extends StatelessWidget {
  const KeyDataSection({super.key, required this.data});

  final NoteStructuredData data;

  @override
  Widget build(BuildContext context) {
    final people = data.participants;
    final deadlines = data.deadlines.where((fact) => !fact.isEmpty).toList();
    final figures = data.figures.where((fact) => !fact.isEmpty).toList();
    final decisions = data.decisions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (people.isNotEmpty) ...[
          Wrap(
            spacing: 18,
            runSpacing: 16,
            children: [for (final name in people) _Person(name: name)],
          ),
          const SizedBox(height: 28),
        ],
        if (data.hasLocation) ...[
          Text(
            data.location,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 28),
        ],
        if (figures.isNotEmpty) ...[
          for (final fact in figures) ...[
            if (fact.lead.isNotEmpty)
              Text(
                fact.lead,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
              ),
            if (fact.detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  fact.detail,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: DropColors.muted(context),
                      ),
                ),
              ),
            const SizedBox(height: 18),
          ],
          const SizedBox(height: 10),
        ],
        if (deadlines.isNotEmpty) ...[
          for (final fact in deadlines)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (fact.lead.isNotEmpty)
                    Text(
                      fact.lead,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            letterSpacing: 0.6,
                            color: DropColors.muted(context),
                          ),
                    ),
                  if (fact.detail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        fact.detail,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.35,
                            ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (decisions.isNotEmpty) ...[
          for (final line in decisions)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 1.5,
                  ),
                ),
              ),
              child: Text(
                line,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                    ),
              ),
            ),
        ],
        if (data.hasTag) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: DropColors.border(context)),
              ),
              child: Text(
                data.tagLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.3,
                    ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Person extends StatelessWidget {
  const _Person({required this.name});

  final String name;

  String get _initials {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return '';
    return parts.map((part) => part.characters.first).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: DropColors.border(context)),
            ),
            child: Text(
              _initials,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.25,
                ),
          ),
        ],
      ),
    );
  }
}

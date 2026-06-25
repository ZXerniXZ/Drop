import 'package:flutter/material.dart';

import '../models/note_filters.dart';
import '../theme/drop_theme.dart';

class NoteSearchBar extends StatelessWidget {
  const NoteSearchBar({
    super.key,
    required this.controller,
    required this.isExpanded,
    required this.onToggle,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!isExpanded) {
      return IconButton(
        onPressed: onToggle,
        icon: const Icon(Icons.search, size: 20),
        style: IconButton.styleFrom(
          side: BorderSide(color: DropColors.border(context)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    return Expanded(
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: true,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Cerca per titolo o testo...',
          hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: DropColors.muted(context),
                fontSize: 13,
              ),
          prefixIcon: Icon(Icons.search, size: 18, color: DropColors.muted(context)),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              controller.clear();
              onChanged('');
              onToggle();
            },
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
    );
  }
}

class NoteFilterBar extends StatelessWidget {
  const NoteFilterBar({
    super.key,
    required this.filters,
    required this.onDateChanged,
    required this.onTagChanged,
  });

  final NoteFilters filters;
  final ValueChanged<DateFilter> onDateChanged;
  final ValueChanged<TagFilter> onTagChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                'DATA',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      letterSpacing: 1,
                    ),
              ),
              const SizedBox(width: 8),
              _chip(context, 'Tutte', filters.dateFilter == DateFilter.all,
                  () => onDateChanged(DateFilter.all)),
              _chip(context, 'Oggi', filters.dateFilter == DateFilter.today,
                  () => onDateChanged(DateFilter.today)),
              _chip(
                context,
                'Ultima settimana',
                filters.dateFilter == DateFilter.week,
                () => onDateChanged(DateFilter.week),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                'TIPO',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      letterSpacing: 1,
                    ),
              ),
              const SizedBox(width: 8),
              _chip(context, 'Tutti', filters.tagFilter == TagFilter.all,
                  () => onTagChanged(TagFilter.all)),
              _chip(context, 'Meeting', filters.tagFilter == TagFilter.meeting,
                  () => onTagChanged(TagFilter.meeting)),
              _chip(context, 'Lezione', filters.tagFilter == TagFilter.lezione,
                  () => onTagChanged(TagFilter.lezione)),
              _chip(context, 'Diario', filters.tagFilter == TagFilter.diario,
                  () => onTagChanged(TagFilter.diario)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
              ),
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: DropColors.border(context)),
        selectedColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.08),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/note_filters.dart';
import '../theme/drop_theme.dart';

class FileSearchFilters extends StatelessWidget {
  const FileSearchFilters({
    super.key,
    required this.searchController,
    required this.filters,
    required this.availableTags,
    required this.filtersVisible,
    required this.onSearchChanged,
    required this.onToggleFilters,
    required this.onTagChanged,
    required this.onDurationChanged,
    required this.onStatusChanged,
  });

  final TextEditingController searchController;
  final NoteFilters filters;
  final List<String> availableTags;
  final bool filtersVisible;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onToggleFilters;
  final ValueChanged<String?> onTagChanged;
  final ValueChanged<DurationFilter> onDurationChanged;
  final ValueChanged<StatusFilter> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: fieldBg,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 18, color: DropColors.muted(context)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          onChanged: onSearchChanged,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontSize: 14,
                              ),
                          decoration: InputDecoration(
                            hintText: 'Cerca per titolo, trascrizione...',
                            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontSize: 13,
                                  color: DropColors.muted(context),
                                ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: filters.hasActiveFilters || filtersVisible
                    ? Theme.of(context).colorScheme.onSurface
                    : fieldBg,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: onToggleFilters,
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.filter_list,
                      size: 20,
                      color: filters.hasActiveFilters || filtersVisible
                          ? Theme.of(context).colorScheme.surface
                          : DropColors.muted(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (filtersVisible) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _FilterDropdown<String?>(
                    label: 'TIPO NOTA',
                    value: filters.tagFilter,
                    items: [
                      const _DropdownItem<String?>(null, 'Tutti'),
                      ...availableTags.map(
                        (t) => _DropdownItem<String?>(t, t),
                      ),
                    ],
                    onChanged: onTagChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FilterDropdown<DurationFilter>(
                    label: 'DURATA',
                    value: filters.durationFilter,
                    items: const [
                      _DropdownItem(DurationFilter.all, 'Tutte'),
                      _DropdownItem(DurationFilter.short, '< 5 min'),
                      _DropdownItem(DurationFilter.medium, '5–15 min'),
                      _DropdownItem(DurationFilter.long, '> 15 min'),
                    ],
                    onChanged: (v) => onDurationChanged(v ?? DurationFilter.all),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FilterDropdown<StatusFilter>(
                    label: 'STATO',
                    value: filters.statusFilter,
                    items: const [
                      _DropdownItem(StatusFilter.all, 'Tutti'),
                      _DropdownItem(StatusFilter.processing, 'In elaborazione'),
                      _DropdownItem(StatusFilter.ready, 'Pronte'),
                      _DropdownItem(StatusFilter.failed, 'Fallite'),
                    ],
                    onChanged: (v) => onStatusChanged(v ?? StatusFilter.all),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DropdownItem<T> {
  const _DropdownItem(this.value, this.label);
  final T value;
  final String label;
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<_DropdownItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9,
                letterSpacing: 0.8,
                color: DropColors.muted(context),
              ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DropColors.border(context)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              isDense: true,
              icon: Icon(Icons.expand_more, size: 18, color: DropColors.muted(context)),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
              items: items
                  .map(
                    (item) => DropdownMenuItem<T>(
                      value: item.value,
                      child: Text(
                        item.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

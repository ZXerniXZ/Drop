import 'package:flutter/material.dart';

import '../models/ai_preferences.dart';
import '../services/open_router_catalog.dart';
import '../theme/drop_theme.dart';

class ModelPickerField extends StatelessWidget {
  const ModelPickerField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AiModel value;
  final ValueChanged<AiModel> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.02)
          : Colors.black.withValues(alpha: 0.02),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: DropColors.border(context)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                      ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: DropColors.muted(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<AiModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _ModelPickerSheet(selectedId: value.openRouterId),
    );
    if (picked != null) onChanged(picked);
  }
}

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({required this.selectedId});

  final String selectedId;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  final _search = TextEditingController();
  List<AiModel> _models = AiModel.fallbacks;
  bool _fromCatalog = false;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cached = await OpenRouterCatalog.instance.readCache();
    if (!mounted) return;
    if (cached.isNotEmpty) {
      setState(() {
        _models = cached;
        _fromCatalog = true;
      });
    }
    final fresh = await OpenRouterCatalog.instance.refresh();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (fresh.isNotEmpty) {
        _models = fresh;
        _fromCatalog = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.88;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: DropColors.muted(context),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Modello',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _fromCatalog
                      ? 'Catalogo OpenRouter'
                      : 'Catalogo non aggiornato',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DropColors.muted(context),
                        fontSize: 12,
                      ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _search,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                    ),
                decoration: InputDecoration(
                  hintText: 'Cerca per nome o id',
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: DropColors.muted(context),
                      ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: DropColors.muted(context),
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            color: DropColors.muted(context),
                          ),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: DropColors.border(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: DropColors.border(context)),
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(child: _list()),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    final rows = _rows();
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'Nessun modello',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: DropColors.muted(context),
              ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.model == null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
            child: Text(
              row.title!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: DropColors.muted(context),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          );
        }
        return _ModelTile(
          model: row.model!,
          selected: row.model!.openRouterId == widget.selectedId,
          onTap: () => Navigator.pop(context, row.model),
        );
      },
    );
  }

  List<_PickerRow> _rows() {
    final source = _models.isEmpty ? AiModel.fallbacks : _models;
    final query = _query.trim();
    if (query.isNotEmpty) {
      return [
        for (final model in filterOpenRouterModels(source, query))
          _PickerRow.model(model),
      ];
    }
    final recommended = source
        .where((model) => isRecommendedOpenRouterModel(model.openRouterId))
        .toList();
    final recommendedIds = recommended.map((model) => model.openRouterId).toSet();
    final rest = source
        .where((model) => !recommendedIds.contains(model.openRouterId))
        .toList();
    return [
      if (recommended.isNotEmpty) const _PickerRow.header('Consigliati'),
      for (final model in recommended) _PickerRow.model(model),
      if (rest.isNotEmpty) const _PickerRow.header('Catalogo'),
      for (final model in rest) _PickerRow.model(model),
    ];
  }
}

class _PickerRow {
  const _PickerRow.header(this.title) : model = null;
  const _PickerRow.model(this.model) : title = null;

  final String? title;
  final AiModel? model;
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final AiModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w600 : null,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    model.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DropColors.muted(context),
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check,
                size: 18,
                color: Theme.of(context).colorScheme.onSurface,
              ),
          ],
        ),
      ),
    );
  }
}

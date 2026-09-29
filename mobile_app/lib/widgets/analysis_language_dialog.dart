import 'package:flutter/material.dart';

import '../models/app_language.dart';
import '../services/note_share_service.dart';
import '../theme/drop_theme.dart';

class LanguageChoice {
  const LanguageChoice({
    required this.sourceLanguage,
    required this.outputLanguage,
  });

  final AppLanguage sourceLanguage;
  final AppLanguage outputLanguage;
}

Future<LanguageChoice?> showAnalysisLanguageDialog({
  required BuildContext context,
  required Future<DetectedLanguages> detection,
  required AppLanguage fallbackSource,
  required AppLanguage fallbackOutput,
}) {
  return showDialog<LanguageChoice>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AnalysisLanguageDialog(
      detection: detection,
      fallbackSource: fallbackSource,
      fallbackOutput: fallbackOutput,
    ),
  );
}

class _AnalysisLanguageDialog extends StatefulWidget {
  const _AnalysisLanguageDialog({
    required this.detection,
    required this.fallbackSource,
    required this.fallbackOutput,
  });

  final Future<DetectedLanguages> detection;
  final AppLanguage fallbackSource;
  final AppLanguage fallbackOutput;

  @override
  State<_AnalysisLanguageDialog> createState() => _AnalysisLanguageDialogState();
}

class _AnalysisLanguageDialogState extends State<_AnalysisLanguageDialog> {
  late AppLanguage _source;
  late AppLanguage _output;
  bool _listening = true;

  @override
  void initState() {
    super.initState();
    _source = widget.fallbackSource;
    _output = widget.fallbackOutput;
    widget.detection.then(_applyDetection).catchError((_) {
      if (!mounted) return;
      setState(() => _listening = false);
    });
  }

  void _applyDetection(DetectedLanguages detected) {
    if (!mounted) return;
    setState(() {
      _source = detected.sourceLanguage;
      _output = detected.outputLanguage;
      _listening = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lingue della nota'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _listening
                ? 'Sto ascoltando un pezzo della registrazione per suggerire le lingue.'
                : 'Controlla lingua della registrazione e lingua del risultato.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_listening) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 18),
          Text(
            'Registrazione',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: DropColors.muted(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          _LanguageDropdown(
            value: _source,
            items: AppLanguage.sourceChoices,
            enabled: !_listening,
            onChanged: (v) => setState(() => _source = v),
          ),
          const SizedBox(height: 14),
          Text(
            'Risultato analisi',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: DropColors.muted(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          _LanguageDropdown(
            value: _output,
            items: AppLanguage.spoken,
            enabled: !_listening,
            onChanged: (v) => setState(() => _output = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            LanguageChoice(sourceLanguage: _source, outputLanguage: _output),
          ),
          child: const Text('Analizza'),
        ),
      ],
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  final AppLanguage value;
  final List<AppLanguage> items;
  final ValueChanged<AppLanguage> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = items.contains(value) ? value : items.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DropColors.border(context)),
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.02),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppLanguage>(
          value: selected,
          isExpanded: true,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(item.label),
                ),
              )
              .toList(),
            onChanged: enabled
              ? (v) {
                  if (v != null) onChanged(v);
                }
              : null,
          menuMaxHeight: 320,
        ),
      ),
    );
  }
}

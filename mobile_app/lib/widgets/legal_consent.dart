import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/legal_links.dart';
import '../theme/drop_theme.dart';

class LegalConsent extends StatefulWidget {
  const LegalConsent({
    super.key,
    required this.requireCheckbox,
    required this.accepted,
    required this.onChanged,
    this.leadIn = 'Creando un account accetti le ',
  });

  final bool requireCheckbox;
  final bool accepted;
  final ValueChanged<bool> onChanged;
  final String leadIn;

  @override
  State<LegalConsent> createState() => _LegalConsentState();
}

class _LegalConsentState extends State<LegalConsent> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => LegalLinks.open(LegalLinks.terms);
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => LegalLinks.open(LegalLinks.privacy);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = DropColors.muted(context);
    final base = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: muted,
          height: 1.4,
        );
    final link = base?.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
      decoration: TextDecoration.underline,
      decorationColor: DropColors.border(context),
    );

    final statement = Text.rich(
      TextSpan(
        style: base,
        children: [
          if (widget.requireCheckbox) TextSpan(text: widget.leadIn),
          TextSpan(
            text: 'condizioni d’uso',
            style: link,
            recognizer: _termsTap,
          ),
          TextSpan(text: widget.requireCheckbox ? ' e l’' : ' · '),
          TextSpan(
            text: 'informativa privacy',
            style: link,
            recognizer: _privacyTap,
          ),
          if (widget.requireCheckbox) const TextSpan(text: '.'),
        ],
      ),
    );

    if (!widget.requireCheckbox) return statement;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: widget.accepted,
            onChanged: (value) => widget.onChanged(value ?? false),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: statement),
      ],
    );
  }
}

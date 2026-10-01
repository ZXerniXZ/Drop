import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_preferences_service.dart';
import '../theme/drop_motion.dart';
import '../theme/drop_theme.dart';

class _TutorialStep {
  const _TutorialStep({
    required this.title,
    required this.caption,
    this.lightAsset,
    this.darkAsset,
    this.uiAsset,
  });

  final String title;
  final String caption;
  final String? lightAsset;
  final String? darkAsset;
  final String? uiAsset;

  String assetFor(bool isDark) {
    final ui = uiAsset;
    if (ui != null) return ui;
    return isDark ? darkAsset! : lightAsset!;
  }
}

const _steps = <_TutorialStep>[
  _TutorialStep(
    title: 'La voce resta',
    caption: 'Registri. Torna una nota.',
    lightAsset: 'assets/tutorial/voce_light.jpg',
    darkAsset: 'assets/tutorial/voce_dark.jpg',
  ),
  _TutorialStep(
    title: 'Il tasto al centro',
    caption: 'Avvia, mette in pausa, chiude.',
    uiAsset: 'assets/tutorial/ui_orb.png',
  ),
  _TutorialStep(
    title: 'Un attimo',
    caption: 'L\'audio esce e torna scritto.',
    lightAsset: 'assets/tutorial/attesa_light.jpg',
    darkAsset: 'assets/tutorial/attesa_dark.jpg',
  ),
  _TutorialStep(
    title: 'La nota',
    caption: 'Prima il riassunto.',
    lightAsset: 'assets/tutorial/nota_light.jpg',
    darkAsset: 'assets/tutorial/nota_dark.jpg',
  ),
  _TutorialStep(
    title: 'Se ti serve',
    caption: 'Una bolla, un approfondimento.',
    lightAsset: 'assets/tutorial/bolle_light.jpg',
    darkAsset: 'assets/tutorial/bolle_dark.jpg',
  ),
  _TutorialStep(
    title: 'Chiedi qui',
    caption: 'La domanda resta su questa registrazione.',
    uiAsset: 'assets/tutorial/ui_chiedi.jpg',
  ),
  _TutorialStep(
    title: 'Pronta',
    caption: 'Puoi registrare.',
    lightAsset: 'assets/tutorial/pronta_light.jpg',
    darkAsset: 'assets/tutorial/pronta_dark.jpg',
  ),
];

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _pageController = PageController();
  int _index = 0;

  bool get _isLast => _index == _steps.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    unawaited(AppPreferencesService.instance.setTutorialSeen());
    super.dispose();
  }

  void _advance() {
    if (_isLast) {
      HapticFeedback.selectionClick();
      Navigator.of(context).pop();
      return;
    }
    _pageController.nextPage(
      duration: DropMotion.medium,
      curve: DropMotion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : Colors.black;

    return Scaffold(
      backgroundColor: isDark
          ? DropColors.darkScaffold
          : DropColors.lightBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: _isLast
                    ? const SizedBox(height: 40)
                    : TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Salta',
                          style: TextStyle(color: DropColors.muted(context)),
                        ),
                      ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _steps.length,
                  onPageChanged: (index) {
                    HapticFeedback.selectionClick();
                    setState(() => _index = index);
                  },
                  itemBuilder: (context, index) {
                    final step = _steps[index];
                    return Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Image.asset(
                              step.assetFor(isDark),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          step.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: ink),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          step.caption,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    AnimatedContainer(
                      duration: DropMotion.fast,
                      curve: DropMotion.standard,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _index ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? ink
                            : ink.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _advance,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: ink,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                ),
                child: Text(_isLast ? 'Registra' : 'Avanti'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

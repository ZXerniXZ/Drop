import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/record_orb_style.dart';
import '../services/app_preferences_service.dart';
import '../theme/drop_theme.dart';
import '../widgets/siri_record_orb.dart';

/// Debug-only screen to compare record orb styles before shipping.
class RecordOrbPreviewScreen extends StatefulWidget {
  const RecordOrbPreviewScreen({super.key, this.onToggleTheme});

  final VoidCallback? onToggleTheme;

  @override
  State<RecordOrbPreviewScreen> createState() => _RecordOrbPreviewScreenState();
}

class _RecordOrbPreviewScreenState extends State<RecordOrbPreviewScreen>
    with TickerProviderStateMixin {
  late final AnimationController _breathController;
  late final AnimationController _waveController;
  RecordOrbStyle _selected = RecordOrbStyle.radialBars;
  bool _simulateRecording = true;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _loadSelected();
  }

  Future<void> _loadSelected() async {
    final style = await AppPreferencesService.instance.loadRecordOrbStyle();
    if (!mounted) return;
    setState(() => _selected = style);
  }

  @override
  void dispose() {
    _breathController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  Future<void> _applyStyle(RecordOrbStyle style) async {
    await AppPreferencesService.instance.saveRecordOrbStyle(style);
    if (!mounted) return;
    setState(() => _selected = style);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Stile attivo: ${style.label}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anteprima tasto record'),
        centerTitle: false,
        actions: [
          if (widget.onToggleTheme != null)
            IconButton(
              onPressed: widget.onToggleTheme,
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.wb_sunny_outlined
                    : Icons.dark_mode_outlined,
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Text(
            'Confronta gli stili e scegli quello che preferisci. La scelta resta salvata su questo dispositivo.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  color: DropColors.muted(context),
                ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Simula registrazione'),
            subtitle: const Text('Anima l\'ampiezza audio senza microfono'),
            value: _simulateRecording,
            onChanged: (v) => setState(() => _simulateRecording = v),
          ),
          const SizedBox(height: 8),
          ...RecordOrbStyle.values.map((style) {
            final isActive = style == _selected;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _StylePreviewCard(
                style: style,
                isSelected: isActive,
                isDark: isDark,
                simulateRecording: _simulateRecording,
                breathController: _breathController,
                waveController: _waveController,
                onSelect: () => _applyStyle(style),
              ),
            );
          }),
          const SizedBox(height: 8),
          _FullscreenMockCard(
            style: _selected,
            isDark: isDark,
            simulateRecording: _simulateRecording,
            breathController: _breathController,
            waveController: _waveController,
          ),
        ],
      ),
    );
  }
}

class _StylePreviewCard extends StatelessWidget {
  const _StylePreviewCard({
    required this.style,
    required this.isSelected,
    required this.isDark,
    required this.simulateRecording,
    required this.breathController,
    required this.waveController,
    required this.onSelect,
  });

  final RecordOrbStyle style;
  final bool isSelected;
  final bool isDark;
  final bool simulateRecording;
  final AnimationController breathController;
  final AnimationController waveController;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? DropColors.recordRed.withValues(alpha: 0.6)
                  : DropColors.border(context),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              _OrbPreview(
                size: 88,
                style: style,
                isRecording: simulateRecording,
                isDark: isDark,
                breathController: breathController,
                waveController: waveController,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      style.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      style.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DropColors.muted(context),
                            fontSize: 12,
                          ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(height: 8),
                      Text(
                        'ATTIVO',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: DropColors.recordRed,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullscreenMockCard extends StatelessWidget {
  const _FullscreenMockCard({
    required this.style,
    required this.isDark,
    required this.simulateRecording,
    required this.breathController,
    required this.waveController,
  });

  final RecordOrbStyle style;
  final bool isDark;
  final bool simulateRecording;
  final AnimationController breathController;
  final AnimationController waveController;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DropColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'D — Modalità ascolto (mock)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Anteprima di come apparirebbe un takeover full-screen. Non ancora implementato nell\'app.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DropColors.muted(context),
                  fontSize: 12,
                ),
          ),
          const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: 1.1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ColoredBox(
                color: isDark ? Colors.black : const Color(0xFF111111),
                child: Center(
                  child: _OrbPreview(
                    size: 160,
                    style: style,
                    isRecording: simulateRecording,
                    isDark: true,
                    breathController: breathController,
                    waveController: waveController,
                    showNavShell: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbPreview extends StatelessWidget {
  const _OrbPreview({
    required this.size,
    required this.style,
    required this.isRecording,
    required this.isDark,
    required this.breathController,
    required this.waveController,
    this.showNavShell = false,
  });

  final double size;
  final RecordOrbStyle style;
  final bool isRecording;
  final bool isDark;
  final AnimationController breathController;
  final AnimationController waveController;
  final bool showNavShell;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([breathController, waveController]),
      builder: (context, child) {
        final breath = CurvedAnimation(
          parent: breathController,
          curve: Curves.easeInOutSine,
        ).value;
        final phase = waveController.value;
        final amp = isRecording
            ? (math.sin(phase * math.pi * 2) * 0.5 + 0.5) * 0.75 + 0.15
            : 0.0;

        final orb = Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
            border: Border.all(
              color: isRecording
                  ? DropColors.recordRed.withValues(alpha: 0.5)
                  : DropColors.border(context),
            ),
            boxShadow: [
              if (isRecording)
                BoxShadow(
                  color: DropColors.recordRed.withValues(alpha: 0.25),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
            ],
          ),
          child: Center(
            child: SiriRecordOrb(
              size: size * 0.82,
              style: style,
              isRecording: isRecording,
              amplitude: amp,
              phase: phase,
              breath: breath,
              isDark: isDark,
            ),
          ),
        );

        if (!showNavShell) return orb;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Transform.scale(scale: 1.4, child: orb),
            const Spacer(),
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        );
      },
    );
  }
}

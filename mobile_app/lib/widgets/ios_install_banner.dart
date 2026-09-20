import 'package:flutter/material.dart';

import '../services/app_preferences_service.dart';
import '../services/web_session.dart';
import '../theme/drop_theme.dart';

class IosInstallBanner extends StatefulWidget {
  const IosInstallBanner({super.key});

  @override
  State<IosInstallBanner> createState() => _IosInstallBannerState();
}

class _IosInstallBannerState extends State<IosInstallBanner> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!WebSession.shouldPromptHomeScreenInstall) return;
    final dismissed =
        await AppPreferencesService.instance.loadIosInstallBannerDismissed();
    if (!mounted || dismissed) return;
    setState(() => _visible = true);
  }

  Future<void> _dismiss() async {
    await AppPreferencesService.instance.setIosInstallBannerDismissed();
    if (!mounted) return;
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: DropColors.border(context)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.ios_share,
                  size: 18,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Per usarla come app: tocca Condividi, poi Aggiungi a Home.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ),
              IconButton(
                onPressed: _dismiss,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Nascondi',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

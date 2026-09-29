import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_identity.dart';
import '../services/app_preferences_service.dart';
import '../services/app_update_service.dart';
import '../services/web_session.dart';

/// In alto sulla versione web: legge la versione e propone APK o PWA.
class WebGetAppBanner extends StatefulWidget {
  const WebGetAppBanner({super.key});

  @override
  State<WebGetAppBanner> createState() => _WebGetAppBannerState();
}

class _WebGetAppBannerState extends State<WebGetAppBanner> {
  bool _visible = false;
  bool _outdated = false;
  String _apkUrl = 'https://github.com/ZXerniXZ/Drop/releases/latest';

  @override
  void initState() {
    super.initState();
    WebSession.listenForInstallPrompt();
    _load();
  }

  Future<void> _load() async {
    if (!kIsWeb) return;
    final policy =
        AppUpdateService.instance.lastPolicy ??
        await AppUpdateService.instance.fetchPolicy();
    if (!mounted) return;

    final outdated = policy != null &&
        AppIdentity.isBelow(policy.minVersion, policy.minBuild);
    final inBrowser = !WebSession.isStandalone;
    if (!outdated && !inBrowser) return;

    if (!outdated) {
      final dismissed =
          await AppPreferencesService.instance.loadWebGetAppBannerDismissed();
      if (!mounted || dismissed) return;
    }

    setState(() {
      _outdated = outdated;
      _apkUrl = policy?.androidUrl ?? _apkUrl;
      _visible = true;
    });
  }

  Future<void> _dismiss() async {
    await AppPreferencesService.instance.setWebGetAppBannerDismissed();
    if (!mounted) return;
    setState(() => _visible = false);
  }

  Future<void> _installPwa() async {
    if (WebSession.canPromptInstall) {
      await WebSession.promptInstall();
      return;
    }
    if (!mounted) return;
    final ios = WebSession.isIosSafari;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Installa la PWA'),
        content: Text(
          ios
              ? 'Tocca Condividi, poi Aggiungi a Home.'
              : 'Apri il menu del browser e scegli Installa app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ok'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    const ink = Color(0xFF1C1404);
    final version = 'Versione ${AppIdentity.version} (${AppIdentity.build})';
    final message = _outdated
        ? '$version non aggiornata. Scarica l\'APK oppure installa la PWA.'
        : '$version. Scarica l\'APK oppure installa la PWA.';

    return Material(
      color: const Color(0xFFF5C518),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.system_update_alt, size: 18, color: ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => WebSession.openExternal(_apkUrl),
                          style: TextButton.styleFrom(
                            foregroundColor: ink,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text('Scarica APK'),
                        ),
                        TextButton(
                          onPressed: _installPwa,
                          style: TextButton.styleFrom(
                            foregroundColor: ink,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text('Installa PWA'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!_outdated)
                IconButton(
                  onPressed: _dismiss,
                  visualDensity: VisualDensity.compact,
                  color: ink,
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

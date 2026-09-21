import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_identity.dart';
import '../services/app_update_service.dart';
import '../services/web_session.dart';
import '../utils/drop_platform.dart';

class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({super.key, required this.policy});

  final AppVersionPolicy policy;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  String? _error;

  Future<void> _update() async {
    setState(() => _error = null);
    final policy = widget.policy;
    try {
      if (kIsWeb) {
        final target = Uri.tryParse(policy.webUrl);
        if (target != null &&
            target.host.isNotEmpty &&
            target.host != Uri.base.host) {
          WebSession.open(policy.webUrl);
          return;
        }
        WebSession.reload();
        return;
      }

      final url = DropPlatform.isAndroid ? policy.androidUrl : policy.webUrl;
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(
          () => _error = 'Non riesco ad aprire il link di aggiornamento.',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Non riesco ad aprire il link di aggiornamento.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttonLabel = kIsWeb
        ? 'Aggiorna'
        : DropPlatform.isAndroid
        ? 'Scarica l\'aggiornamento'
        : 'Apri la versione aggiornata';

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Drop',
                  style: TextStyle(
                    color: Color(0xFFF4F4F5),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Aggiornamento necessario',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFF4F4F5),
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.policy.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Versione ${AppIdentity.version} (${AppIdentity.build})',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _update,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF4F4F5),
                      foregroundColor: const Color(0xFF09090B),
                    ),
                    child: Text(buttonLabel),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF4D4F),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

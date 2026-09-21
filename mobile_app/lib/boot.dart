import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart' deferred as rest;
import 'screens/update_required_screen.dart';
import 'services/app_identity.dart';
import 'services/app_update_service.dart';
import 'services/web_session.dart';

class DropBootApp extends StatefulWidget {
  const DropBootApp({super.key});

  @override
  State<DropBootApp> createState() => _DropBootAppState();
}

class _DropBootAppState extends State<DropBootApp> {
  String? _error;
  bool _slow = false;
  AppVersionPolicy? _updatePolicy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WebSession.hideHtmlSplash();
      unawaited(_start());
    });
  }

  Future<void> _start() async {
    final slowTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _error == null) setState(() => _slow = true);
    });
    try {
      await AppUpdateService.instance.loadIdentity();
      final policy = await AppUpdateService.instance.fetchPolicy();
      if (policy != null &&
          AppIdentity.isBelow(policy.minVersion, policy.minBuild)) {
        slowTimer.cancel();
        if (!mounted) return;
        setState(() => _updatePolicy = policy);
        return;
      }
      await rest.loadLibrary();
      await rest.startDropApp();
      slowTimer.cancel();
    } catch (error, stack) {
      slowTimer.cancel();
      debugPrint('Drop boot: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _error = 'Drop non si è avviato.';
      });
    }
  }

  void _retry() {
    if (kIsWeb) {
      WebSession.reload();
      return;
    }
    setState(() {
      _error = null;
      _slow = false;
    });
    unawaited(_start());
  }

  @override
  Widget build(BuildContext context) {
    final updatePolicy = _updatePolicy;
    return MaterialApp(
      title: 'Drop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: updatePolicy != null
          ? UpdateRequiredScreen(policy: updatePolicy)
          : Scaffold(
              backgroundColor: const Color(0xFF09090B),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
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
                      const SizedBox(height: 20),
                      if (_error == null) ...[
                        if (_slow)
                          Text(
                            'Ci sto mettendo più del solito…',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 14,
                            ),
                          ),
                      ] else ...[
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _retry,
                          child: const Text('Riprova'),
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

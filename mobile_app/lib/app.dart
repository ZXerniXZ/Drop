import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'screens/recorder_screen.dart';
import 'services/drop_bootstrap.dart';
import 'services/supabase_auth_service.dart';
import 'services/web_session.dart';
import 'theme/drop_motion.dart';
import 'theme/drop_theme.dart';
import 'widgets/drop_logo.dart';
import 'widgets/ios_install_banner.dart';

class DropBootApp extends StatefulWidget {
  const DropBootApp({super.key});

  @override
  State<DropBootApp> createState() => _DropBootAppState();
}

class _DropBootAppState extends State<DropBootApp> {
  String? _error;
  bool _slow = false;

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
      await bootstrapDrop();
      slowTimer.cancel();
      if (!mounted) return;
      runApp(const DropApp());
    } catch (error, stack) {
      slowTimer.cancel();
      debugPrint('Drop boot: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _error = error is TimeoutException
            ? 'Avvio troppo lento. Riprova.'
            : 'Drop non si è avviato.';
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
    return MaterialApp(
      title: 'Drop',
      debugShowCheckedModeBanner: false,
      theme: DropTheme.dark(),
      home: Scaffold(
        backgroundColor: DropColors.darkBackground,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DropLogo(height: 72),
                const SizedBox(height: 16),
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

class DropApp extends StatefulWidget {
  const DropApp({super.key});

  @override
  State<DropApp> createState() => _DropAppState();
}

class _DropAppState extends State<DropApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drop',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      themeAnimationDuration: DropMotion.slow,
      themeAnimationCurve: DropMotion.standard,
      theme: DropTheme.light(),
      darkTheme: DropTheme.dark(),
      builder: (context, child) {
        return Column(
          children: [
            const IosInstallBanner(),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
      home: StreamBuilder<AuthState>(
        stream: SupabaseAuthService.instance.authStateChanges,
        builder: (context, snapshot) {
          final session = SupabaseAuthService.instance.currentSession;
          if (session == null) {
            return const LoginScreen();
          }
          return RecorderScreen(
            isDarkMode: _themeMode == ThemeMode.dark,
            onToggleTheme: _toggleTheme,
          );
        },
      ),
    );
  }
}

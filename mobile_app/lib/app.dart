import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/accept_terms_screen.dart';
import 'screens/login_screen.dart';
import 'screens/recorder_screen.dart';
import 'services/drop_bootstrap.dart';
import 'services/legal_acceptance.dart';
import 'services/supabase_auth_service.dart';
import 'theme/drop_motion.dart';
import 'theme/drop_theme.dart';
import 'widgets/ios_install_banner.dart';
import 'widgets/web_get_app_banner.dart';

Future<void> startDropApp() async {
  await bootstrapDrop();
  runApp(const DropApp());
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
            const WebGetAppBanner(),
            const IosInstallBanner(),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
      home: StreamBuilder<AuthState>(
        stream: SupabaseAuthService.instance.authStateChanges,
        builder: (context, snapshot) {
          final session = SupabaseAuthService.instance.currentSession;
          final confirmed = session?.user.emailConfirmedAt != null;
          if (session == null || !confirmed) {
            return const LoginScreen();
          }
          if (!LegalAcceptance.hasAcceptedCurrentTerms) {
            return const AcceptTermsScreen();
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

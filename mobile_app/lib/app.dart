import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'screens/recorder_screen.dart';
import 'services/supabase_auth_service.dart';
import 'theme/drop_theme.dart';

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
      theme: DropTheme.light(),
      darkTheme: DropTheme.dark(),
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

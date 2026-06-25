import 'package:flutter/material.dart';

import 'screens/record_orb_preview_screen.dart';
import 'services/app_preferences_service.dart';
import 'theme/drop_theme.dart';

/// Entry point leggero solo per confrontare gli stili del tasto record in locale.
/// Uso: flutter run -t lib/preview_main.dart -d chrome
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferencesService.instance.init();
  runApp(const OrbPreviewApp());
}

class OrbPreviewApp extends StatefulWidget {
  const OrbPreviewApp({super.key});

  @override
  State<OrbPreviewApp> createState() => _OrbPreviewAppState();
}

class _OrbPreviewAppState extends State<OrbPreviewApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drop — Orb preview',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: DropTheme.light(),
      darkTheme: DropTheme.dark(),
      home: RecordOrbPreviewScreen(
        onToggleTheme: () => setState(
          () => _themeMode = _themeMode == ThemeMode.dark
              ? ThemeMode.light
              : ThemeMode.dark,
        ),
      ),
    );
  }
}

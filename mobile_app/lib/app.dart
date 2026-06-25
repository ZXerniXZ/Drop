import 'package:flutter/material.dart';

import 'screens/recorder_screen.dart';
import 'services/app_icon_service.dart';
import 'theme/drop_theme.dart';

class DropApp extends StatefulWidget {
  const DropApp({super.key});

  @override
  State<DropApp> createState() => _DropAppState();
}

class _DropAppState extends State<DropApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppIconService.instance.syncWithTheme(
        isDarkMode: _themeMode == ThemeMode.dark,
      );
    });
  }

  void _toggleTheme() {
    final nextDark = _themeMode != ThemeMode.dark;
    setState(() {
      _themeMode = nextDark ? ThemeMode.dark : ThemeMode.light;
    });
    AppIconService.instance.syncWithTheme(isDarkMode: nextDark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drop',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: DropTheme.light(),
      darkTheme: DropTheme.dark(),
      home: RecorderScreen(
        isDarkMode: _themeMode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

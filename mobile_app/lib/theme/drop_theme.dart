import 'package:flutter/material.dart';

class DropColors {
  DropColors._();

  static const recordRed = Color(0xFFFF4D4F);

  static const lightBackground = Color(0xFFFAFAFA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightScaffold = Color(0xFFFCFCFC);

  static const darkBackground = Color(0xFF000000);
  static const darkSurface = Color(0xFF0C0C0E);
  static const darkScaffold = Color(0xFF09090B);

  static Color border(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
  }

  static Color muted(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.45);
  }
}

class DropTheme {
  DropTheme._();

  static ThemeData light() {
    const scheme = ColorScheme.light(
      surface: DropColors.lightSurface,
      onSurface: Colors.black,
      primary: Colors.black,
      onPrimary: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: DropColors.lightBackground,
      dividerColor: Colors.black.withValues(alpha: 0.06),
      appBarTheme: const AppBarTheme(
        backgroundColor: DropColors.lightSurface,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textTheme: _textTheme(Brightness.light),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      surface: DropColors.darkSurface,
      onSurface: Color(0xFFF4F4F5),
      primary: Colors.white,
      onPrimary: Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: DropColors.darkBackground,
      dividerColor: Colors.white.withValues(alpha: 0.06),
      appBarTheme: const AppBarTheme(
        backgroundColor: DropColors.darkBackground,
        foregroundColor: Color(0xFFF4F4F5),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textTheme: _textTheme(Brightness.dark),
    );
  }

  static TextTheme _textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark ? Colors.white : Colors.black;
    final muted = brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.7);

    return TextTheme(
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: base,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        color: base,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.55,
        color: muted,
      ),
      labelSmall: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: muted,
      ),
    );
  }
}

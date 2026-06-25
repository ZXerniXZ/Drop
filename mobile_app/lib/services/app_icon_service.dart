import 'package:dynamic_app_icon_flutter_plus/dynamic_app_icon_flutter_plus.dart';
import 'package:flutter/foundation.dart';

class AppIconService {
  AppIconService._();

  static final AppIconService instance = AppIconService._();

  Future<void> syncWithTheme({required bool isDarkMode}) async {
    if (kIsWeb) return;

    try {
      final supported =
          await DynamicAppIconFlutterPlus.supportsAlternateIcons;
      if (!supported) return;

      if (isDarkMode) {
        await DynamicAppIconFlutterPlus.setAlternateIconName(
          null,
          showAlert: false,
        );
      } else {
        await DynamicAppIconFlutterPlus.setAlternateIconName(
          'light',
          showAlert: false,
        );
      }
    } catch (_) {
      // Icon switching is best-effort; unsupported OEMs fail silently.
    }
  }
}

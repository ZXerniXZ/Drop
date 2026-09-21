import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'api_url_resolver.dart';
import 'app_identity.dart';
import 'drop_api_headers.dart';

class AppVersionPolicy {
  const AppVersionPolicy({
    required this.minVersion,
    required this.minBuild,
    required this.message,
    required this.androidUrl,
    required this.webUrl,
  });

  final String minVersion;
  final int minBuild;
  final String message;
  final String androidUrl;
  final String webUrl;
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  Future<void> loadIdentity() async {
    final info = await PackageInfo.fromPlatform();
    final name = info.version.split('+').first.trim();
    AppIdentity.version = name.isEmpty ? '0.0.0' : name;
    AppIdentity.build = int.tryParse(info.buildNumber) ?? 0;
  }

  /// Null se il server non risponde: l'app resta usabile in locale.
  Future<AppVersionPolicy?> fetchPolicy() async {
    try {
      final url = await ApiUrlResolver.resolveEndpoint('/app/version');
      final response = await http
          .get(Uri.parse(url), headers: DropApiHeaders.version())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      final minVersion = body['min_version'] as String?;
      final minBuild = (body['min_build'] as num?)?.round();
      if (minVersion == null || minVersion.isEmpty || minBuild == null) {
        return null;
      }
      return AppVersionPolicy(
        minVersion: minVersion,
        minBuild: minBuild,
        message:
            body['message'] as String? ??
            'Questa versione di Drop non è più supportata. Aggiorna per continuare.',
        androidUrl:
            body['android_url'] as String? ??
            'https://github.com/ZXerniXZ/Drop/releases/latest',
        webUrl: body['web_url'] as String? ?? 'https://drop-app-3x2.pages.dev',
      );
    } catch (_) {
      return null;
    }
  }
}

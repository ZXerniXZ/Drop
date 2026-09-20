import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import 'android_emulator.dart';

const String physicalDeviceBackendHost = 'http://192.168.1.35:8083';

class ApiUrlResolver {
  ApiUrlResolver._();

  static Future<String> resolveEndpoint(String path) async {
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    if (kReleaseMode) {
      return '$productionApiBaseUrl$normalizedPath';
    }
    if (kIsWeb) {
      return 'http://localhost:8080$normalizedPath';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (await isAndroidEmulator()) {
        return 'http://10.0.2.2:8080$normalizedPath';
      }
      return '$physicalDeviceBackendHost$normalizedPath';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return '$physicalDeviceBackendHost$normalizedPath';
    }
    return 'http://localhost:8080$normalizedPath';
  }
}

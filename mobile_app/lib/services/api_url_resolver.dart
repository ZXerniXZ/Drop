import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/api_config.dart';

const String physicalDeviceBackendHost = 'http://192.168.1.35:8083';

class ApiUrlResolver {
  ApiUrlResolver._();

  static Future<String> resolveEndpoint(String path) async {
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    if (kReleaseMode) {
      return '$productionApiBaseUrl$normalizedPath';
    }
    if (Platform.isAndroid) {
      if (await _isAndroidEmulator()) {
        return 'http://10.0.2.2:8080$normalizedPath';
      }
      return '$physicalDeviceBackendHost$normalizedPath';
    }
    if (Platform.isIOS) {
      return '$physicalDeviceBackendHost$normalizedPath';
    }
    return 'http://localhost:8080$normalizedPath';
  }

  static Future<bool> _isAndroidEmulator() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await Process.run('getprop', ['ro.kernel.qemu']);
      return result.stdout.toString().trim() == '1';
    } catch (_) {
      return false;
    }
  }
}

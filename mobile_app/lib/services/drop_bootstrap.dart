import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../utils/drop_platform.dart';
import '../utils/init_sqflite.dart';
import 'app_preferences_service.dart';
import 'local_database_service.dart';
import 'recording_foreground_service.dart';

Future<T> _awaitOrTimeout<T>(
  Future<T> future,
  Duration duration,
  String label,
) async {
  try {
    return await future.timeout(duration);
  } on TimeoutException {
    future.ignore();
    throw TimeoutException(label, duration);
  }
}

Future<void> bootstrapDrop() async {
  await _awaitOrTimeout(initSqflite(), const Duration(seconds: 12), 'sqlite');
  await _awaitOrTimeout(
    RecordingForegroundService.init(),
    const Duration(seconds: 5),
    'foreground',
  );
  await _awaitOrTimeout(
    Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: !DropPlatform.isWeb,
      ),
    ),
    const Duration(seconds: 12),
    'auth',
  );
  if (DropPlatform.isWeb) {
    final uri = Uri.base;
    final fragment = Uri.splitQueryString(uri.fragment);
    if (uri.queryParameters.containsKey('code') ||
        fragment.containsKey('access_token') ||
        fragment.containsKey('error_description')) {
      try {
        await _awaitOrTimeout(
          Supabase.instance.client.auth.getSessionFromUrl(uri),
          const Duration(seconds: 12),
          'oauth',
        );
      } catch (error, stack) {
        debugPrint('OAuth callback: $error\n$stack');
      }
    }
  }
  await _awaitOrTimeout(
    LocalDatabaseService.instance.init(),
    const Duration(seconds: 12),
    'database',
  );
  await _awaitOrTimeout(
    AppPreferencesService.instance.init(),
    const Duration(seconds: 5),
    'prefs',
  );
}

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../utils/drop_platform.dart';
import '../utils/init_sqflite.dart';
import 'app_preferences_service.dart';
import 'http_client.dart';
import 'local_database_service.dart';
import 'recording_foreground_service.dart';

Future<void> bootstrapDrop() async {
  await initSqflite().timeout(const Duration(seconds: 12));
  await RecordingForegroundService.init().timeout(
    const Duration(seconds: 5),
  );
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
    httpClient: createHttpClient(),
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      detectSessionInUri: !DropPlatform.isWeb,
    ),
  ).timeout(const Duration(seconds: 12));
  if (DropPlatform.isWeb) {
    final uri = Uri.base;
    final fragment = Uri.splitQueryString(uri.fragment);
    if (uri.queryParameters.containsKey('code') ||
        fragment.containsKey('access_token') ||
        fragment.containsKey('error_description')) {
      try {
        await Supabase.instance.client.auth
            .getSessionFromUrl(uri)
            .timeout(const Duration(seconds: 12));
      } catch (error, stack) {
        debugPrint('OAuth callback: $error\n$stack');
      }
    }
  }
  await LocalDatabaseService.instance.init().timeout(
    const Duration(seconds: 12),
  );
  await AppPreferencesService.instance.init().timeout(
    const Duration(seconds: 5),
  );
}

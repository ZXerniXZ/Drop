import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/supabase_config.dart';
import 'services/app_preferences_service.dart';
import 'services/local_database_service.dart';
import 'services/recording_foreground_service.dart';
import 'utils/init_sqflite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSqflite();
  FlutterForegroundTask.initCommunicationPort();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
  await RecordingForegroundService.init();
  await LocalDatabaseService.instance.init();
  await AppPreferencesService.instance.init();
  runApp(const DropApp());
}

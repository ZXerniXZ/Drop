import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app.dart';
import 'services/app_preferences_service.dart';
import 'services/local_database_service.dart';
import 'services/recording_foreground_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  await RecordingForegroundService.init();
  await LocalDatabaseService.instance.init();
  await AppPreferencesService.instance.init();
  runApp(const DropApp());
}

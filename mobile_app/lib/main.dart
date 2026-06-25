import 'package:flutter/material.dart';

import 'app.dart';
import 'services/local_database_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabaseService.instance.init();
  runApp(const DropApp());
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'boot.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const DropBootApp());
}

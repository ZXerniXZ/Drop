import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<void> initSqflite() async {
  // SharedWorker is flaky in iOS Safari PWAs. Load sqlite3.wasm on the
  // main thread instead.
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
}

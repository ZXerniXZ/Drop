import 'dart:io';

Future<bool> isAndroidEmulator() async {
  if (!Platform.isAndroid) return false;
  try {
    final result = await Process.run('getprop', ['ro.kernel.qemu']);
    return result.stdout.toString().trim() == '1';
  } catch (_) {
    return false;
  }
}

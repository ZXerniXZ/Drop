class AppIdentity {
  AppIdentity._();

  static String version = '0.0.0';
  static int build = 0;

  static bool isBelow(String minVersion, int minBuild) {
    return isOlderThan(
      version: version,
      build: build,
      minVersion: minVersion,
      minBuild: minBuild,
    );
  }
}

bool isOlderThan({
  required String version,
  required int build,
  required String minVersion,
  required int minBuild,
}) {
  final client = parseVersion(version);
  final minimum = parseVersion(minVersion);
  for (var i = 0; i < 3; i++) {
    if (client[i] != minimum[i]) return client[i] < minimum[i];
  }
  return build < minBuild;
}

List<int> parseVersion(String value) {
  final parts = value.split('.');
  final numbers = <int>[];
  for (final part in parts.take(3)) {
    final digits = part.replaceAll(RegExp(r'[^0-9]'), '');
    numbers.add(int.tryParse(digits) ?? 0);
  }
  while (numbers.length < 3) {
    numbers.add(0);
  }
  return numbers;
}

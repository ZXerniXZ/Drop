import 'package:flutter_test/flutter_test.dart';

import 'package:drop/services/app_identity.dart';

void main() {
  test('build below the minimum is outdated', () {
    expect(
      isOlderThan(
        version: '1.0.4',
        build: 29,
        minVersion: '1.0.4',
        minBuild: 30,
      ),
      isTrue,
    );
  });

  test('the current build is accepted', () {
    expect(
      isOlderThan(
        version: '1.0.4',
        build: 30,
        minVersion: '1.0.4',
        minBuild: 30,
      ),
      isFalse,
    );
  });

  test('a newer version is accepted even with a lower build', () {
    expect(
      isOlderThan(
        version: '1.1.0',
        build: 1,
        minVersion: '1.0.4',
        minBuild: 30,
      ),
      isFalse,
    );
  });

  test('an older version is rejected even with a higher build', () {
    expect(
      isOlderThan(
        version: '1.0.3',
        build: 99,
        minVersion: '1.0.4',
        minBuild: 30,
      ),
      isTrue,
    );
  });
}

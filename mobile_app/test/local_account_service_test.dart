import 'package:flutter_test/flutter_test.dart';

import 'package:drop/services/local_account_service.dart';

void main() {
  test('dimentica le note locali che il server di questo account non ha', () {
    final forget = localNotesToForget(
      processingById: {
        'mia': false,
        'altrui': false,
        'in-corso': true,
      },
      remoteIds: {'mia'},
    );

    expect(forget, {'altrui'});
  });

  test('un account senza note sul server non tiene la cache precedente', () {
    final forget = localNotesToForget(
      processingById: {'vecchia': false},
      remoteIds: {},
    );

    expect(forget, {'vecchia'});
  });
}

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'owned_http_client_test_support.dart';

void main() {
  test('a closed real client preserves the successful result', () async {
    expect(
      await expectOwnedHttpClientsClosed(() async {
        HttpClient().close(force: true);
        return 42;
      }),
      42,
    );
  });
  test(
    'an idle unclosed real client fails the ownership oracle and is reaped',
    () async {
      late HttpClient client;
      await expectLater(
        expectOwnedHttpClientsClosed(() async {
          client = HttpClient();
        }),
        throwsA(
          isA<TestFailure>().having(
            (e) => e.message,
            'ownership assertion',
            contains('close every owned HTTP client'),
          ),
        ),
      );
      await expectLater(
        () => client.getUrl(Uri.parse('http://127.0.0.1:9/')),
        throwsStateError,
      );
    },
  );
  for (final error in <Object>[
    const SocketException('connection refused'),
    TimeoutException('deadline'),
    const FormatException('unknown protocol error'),
  ]) {
    test(
      '$error retains its original exception and reaps the client',
      () async {
        late HttpClient client;
        await expectLater(
          expectOwnedHttpClientsClosed(() async {
            client = HttpClient();
            throw error;
          }),
          throwsA(same(error)),
        );
        await expectLater(
          () => client.getUrl(Uri.parse('http://127.0.0.1:9/')),
          throwsStateError,
        );
      },
    );
  }
}

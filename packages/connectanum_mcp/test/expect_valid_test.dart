import 'dart:async';

import 'package:test/test.dart';

import 'support/expect_valid.dart';

void main() {
  test('valid-operation oracles preserve returned identity', () async {
    final value = Object();
    expect(expectValid(() => value), same(value));
    expect(await expectValidAsync(() async => value), same(value));
  });

  test('synchronous oracle fails on unexpected errors', () {
    expect(
      () => expectValid<void>(() => throw StateError('operation failed')),
      throwsA(isA<TestFailure>()),
    );
  });

  test('synchronous oracle preserves timeouts', () {
    final timeout = TimeoutException('operation deadline');
    expect(
      () => expectValid<void>(() => throw timeout),
      throwsA(same(timeout)),
    );
  });

  for (final synchronous in [false, true]) {
    test('asynchronous oracle preserves timeout, synchronous=$synchronous', () {
      final timeout = TimeoutException('operation deadline');
      expect(
        expectValidAsync<void>(() {
          if (synchronous) throw timeout;
          return Future<void>.error(timeout);
        }),
        throwsA(same(timeout)),
      );
    });

    test('unexpected error fails the success assertion, sync=$synchronous', () {
      final failure = StateError('operation failed');
      expect(
        expectValidAsync<void>(() {
          if (synchronous) throw failure;
          return Future<void>.error(failure);
        }),
        throwsA(isA<TestFailure>()),
      );
    });
  }
}

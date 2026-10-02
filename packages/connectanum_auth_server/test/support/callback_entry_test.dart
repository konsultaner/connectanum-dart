import 'dart:async';

import 'package:test/test.dart';

import 'callback_entry.dart';

void main() {
  test(
    'an early result is an assertion failure, not a callback timeout',
    () async {
      await expectLater(
        expectCallbackEntry(Completer<void>().future, Future.value('rejected')),
        throwsA(
          isA<TestFailure>().having(
            (error) => error.message,
            'message',
            'Operation completed before required callback entry',
          ),
        ),
      );
    },
  );

  test(
    'an early operation error fails without disclosing its payload',
    () async {
      await expectLater(
        expectCallbackEntry(
          Completer<void>().future,
          Future<Object?>.error(StateError('private provider data')),
        ),
        throwsA(
          isA<TestFailure>().having(
            (error) => error.message,
            'message',
            'Operation failed before required callback entry',
          ),
        ),
      );
    },
  );

  for (final failsLater in [false, true]) {
    test(
      'callback entry wins and handles later operation failure $failsLater',
      () async {
        final entry = Completer<void>();
        final operation = Completer<Object?>();
        final waiting = expectCallbackEntry(entry.future, operation.future);
        entry.complete();
        await waiting;
        if (failsLater) {
          operation.completeError(StateError('later provider failure'));
        } else {
          operation.complete('completed');
        }
        // Let the losing branch settle; an unhandled error fails this test.
        await Future<void>.delayed(Duration.zero);
      },
    );
  }
}

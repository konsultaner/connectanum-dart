import 'dart:core' hide Error;
import 'dart:core' as dart_core;

import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  test('abandonment closes existing payload views without dispatch', () {
    final invocation = Invocation(7, 11, InvocationDetails(null, null, true));
    final payload = invocation.toPayload();
    final lazy = invocation.toLazyInvocationPayload();
    final responses = <AbstractMessageWithPayload>[];
    invocation.onResponse(responses.add);
    expect(invocation.closeResponse, returnsNormally);
    expect(invocation.closeResponse, returnsNormally);
    expect(invocation.responseClosed, isTrue);
    expect(payload.isResponseClosed(), isTrue);
    expect(lazy.isResponseClosed(), isTrue);
    expect(responses, isEmpty);
    invocation.onResponse(responses.add);
    expect(() => invocation.respondWith(), throwsStateError);
    expect(() => payload.respondWith(), throwsStateError);
    expect(() => lazy.respondWith(), throwsStateError);
    expect(responses, isEmpty);
  });

  for (final progress in [false, true]) {
    for (final throwsAfterClosing in [false, true]) {
      test(
        'adapter abandonment stays closed progress=$progress '
        'throws=$throwsAfterClosing',
        () {
          final invocation = Invocation(
            7,
            11,
            InvocationDetails(null, null, true),
          );
          final failure = StateError('closed during dispatch');
          var attempts = 0;
          invocation.onResponse((_) {
            attempts++;
            invocation.closeResponse();
            expect(invocation.responseClosed, isTrue);
            if (throwsAfterClosing) {
              throw failure;
            }
          });
          expect(
            () => invocation.respondWith(
              options: YieldOptions(progress: progress),
            ),
            throwsAfterClosing ? throwsA(same(failure)) : returnsNormally,
          );
          expect(invocation.responseClosed, isTrue);
          expect(() => invocation.respondWith(), throwsStateError);
          expect(attempts, 1);
        },
      );
    }
  }

  for (final isError in [false, true]) {
    test(
      'terminal response rejects synchronous nested delivery error=$isError',
      () {
        final invocation = Invocation(
          7,
          11,
          InvocationDetails(null, null, true),
        );
        final responses = <AbstractMessageWithPayload>[];
        var first = true;
        Object? nestedFailure;
        bool? closedDuringDelivery;
        invocation.onResponse((response) {
          responses.add(response);
          if (first) {
            first = false;
            closedDuringDelivery = invocation.responseClosed;
            try {
              invocation.respondWith(arguments: ['late']);
            } catch (error) {
              nestedFailure = error;
            }
          }
        });
        invocation.respondWith(
          isError: isError,
          errorUri: isError ? Error.notAuthorized : null,
          arguments: ['terminal'],
        );
        expect(responses, hasLength(1));
        expect(closedDuringDelivery, isTrue);
        expect(nestedFailure, isA<StateError>());
        expect(invocation.responseClosed, isTrue);
      },
    );

    test(
      'rejected terminal response permits retry error=$isError',
      () {
        final invocation = Invocation(
          7,
          11,
          InvocationDetails(null, null, true),
        );
        final responses = <AbstractMessageWithPayload>[];
        final failure = StateError('synthetic adapter rejection');
        final failureStack = StackTrace.fromString('adapter rejection stack');
        var dispatches = 0;
        invocation.onResponse((_) {
          dispatches++;
          expect(invocation.responseClosed, isTrue);
          // A broken completion guard must fail, not recursively hang the suite.
          if (dispatches == 1) {
            expect(
              () => invocation.respondWith(arguments: ['nested']),
              throwsStateError,
            );
          }
          dart_core.Error.throwWithStackTrace(failure, failureStack);
        });
        Object? caught;
        StackTrace? caughtStack;
        try {
          invocation.respondWith(
            isError: isError,
            errorUri: isError ? Error.notAuthorized : null,
            arguments: ['terminal'],
          );
        } catch (error, stack) {
          caught = error;
          caughtStack = stack;
        }
        expect(caught, same(failure));
        expect(caughtStack.toString(), failureStack.toString());
        expect(dispatches, 1);
        expect(invocation.responseClosed, isFalse);
        expect(responses, isEmpty);
        invocation.onResponse(responses.add);
        invocation.respondWith(arguments: ['retry']);
        expect(invocation.responseClosed, isTrue);
        expect(responses.single.arguments, ['retry']);
        expect(
          () => invocation.respondWith(arguments: ['late']),
          throwsStateError,
        );
        expect(responses, hasLength(1));
      },
    );
  }

  for (final progress in [false, true]) {
    test('adapter cannot change completion by mutating progress=$progress', () {
      final invocation = Invocation(7, 11, InvocationDetails(null, null, true));
      final options = YieldOptions(progress: progress);
      bool? deliveredProgress;
      invocation.onResponse((response) {
        deliveredProgress = (response as Yield).options!.progress;
        options.progress = !progress;
      });
      invocation.respondWith(options: options, arguments: ['payload']);
      expect(deliveredProgress, progress);
      expect(invocation.responseClosed, !progress);
    });
  }

  test(
    'progressive adapter may synchronously deliver another progress result',
    () {
      final invocation = Invocation(7, 11, InvocationDetails(null, null, true));
      final values = <Object?>[];
      final closedStates = <bool>[];
      invocation.onResponse((response) {
        closedStates.add(invocation.responseClosed);
        values.add(response.arguments!.single);
        if (values.length == 1) {
          invocation.respondWith(
            arguments: [2],
            options: YieldOptions(progress: true),
          );
        }
      });
      invocation.respondWith(
        arguments: [1],
        options: YieldOptions(progress: true),
      );
      expect(invocation.responseClosed, isFalse);
      invocation.respondWith(arguments: [3]);
      expect(values, [1, 2, 3]);
      expect(closedStates, [false, false, true]);
      expect(invocation.responseClosed, isTrue);
    },
  );

  test('failure before dispatch attachment does not close a response', () {
    final invocation = Invocation(7, 11, InvocationDetails(null, null, true));
    expect(
      () => invocation.respondWith(arguments: ['not delivered']),
      throwsStateError,
    );
    expect(invocation.responseClosed, isFalse);
    final responses = <AbstractMessageWithPayload>[];
    invocation.onResponse(responses.add);
    invocation.respondWith(arguments: ['delivered']);
    expect(responses.single.arguments, ['delivered']);
    expect(invocation.responseClosed, isTrue);
  });

  test(
    'progress callback failure cannot reopen an accepted nested final result',
    () {
      final invocation = Invocation(7, 11, InvocationDetails(null, null, true));
      final failure = StateError('outer progress callback failed');
      final values = <Object?>[];
      invocation.onResponse((response) {
        values.add(response.arguments!.single);
        if ((response as Yield).options?.progress == true) {
          invocation.respondWith(arguments: ['final']);
          throw failure;
        }
      });
      expect(
        () => invocation.respondWith(
          arguments: ['progress'],
          options: YieldOptions(progress: true),
        ),
        throwsA(same(failure)),
      );
      expect(values, ['progress', 'final']);
      expect(invocation.responseClosed, isTrue);
      expect(() => invocation.respondWith(), throwsStateError);
      expect(values, ['progress', 'final']);
    },
  );

  test(
    'throwing progressive adapter leaves completion to a later final result',
    () {
      final invocation = Invocation(7, 11, InvocationDetails(null, null, true));
      final failure = StateError('synthetic progressive adapter failure');
      invocation.onResponse((_) => throw failure);
      expect(
        () => invocation.respondWith(options: YieldOptions(progress: true)),
        throwsA(same(failure)),
      );
      expect(invocation.responseClosed, isFalse);
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);
      invocation.respondWith(arguments: ['terminal']);
      expect(responses.single.arguments, ['terminal']);
      expect(invocation.responseClosed, isTrue);
    },
  );
}

@TestOn('vm')
library;

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  for (final failureIndex in [0, 1, 2]) {
    test(
      'replay matcher failure at $failureIndex preserves every buffered event in order',
      () {
        fakeAsync((async) {
          final buffer = WampEventBuffer();
          final events = [for (var i = 1; i <= 3; i++) _event(i)];
          events.forEach(buffer.add);
          final failure = StateError('malformed event metadata');
          final seen = <core.LazyEventPayload>[];
          expect(
            () {
              buffer.nextWhere((event) {
                seen.add(event);
                if (identical(event, events[failureIndex])) throw failure;
                return false;
              });
            },
            throwsA(same(failure)),
          );
          expect(seen, events.take(failureIndex + 1).toList());
          final later = _event(4);
          buffer.add(later);
          buffer.close();
          final received = <core.LazyEventPayload>[];
          final errors = <(Object, StackTrace)>[];
          for (var i = 0; i < 4; i++) {
            _observe(buffer.nextWhere((_) => true), received, errors);
          }
          async.flushMicrotasks();
          expect(received, [...events, later]);
          expect(errors, isEmpty);
          _observe(buffer.nextWhere((_) => true), received, errors);
          async.flushMicrotasks();
          expect(received, [...events, later]);
          expect(errors, hasLength(1));
          expect(errors.single.$1, isA<StateError>());
        });
      },
    );
  }

  test('normal close fails every pending consumer and remains closed', () {
    fakeAsync((async) {
      final buffer = WampEventBuffer();
      final received = <core.LazyEventPayload>[];
      final errors = <(Object, StackTrace)>[];
      for (var i = 0; i < 3; i++) {
        _observe(buffer.nextWhere((_) => true), received, errors);
      }
      buffer.close();
      buffer.close();
      async.flushMicrotasks();
      expect(received, isEmpty);
      expect(errors, hasLength(3));
      for (final error in errors) {
        expect(
          error.$1,
          isA<StateError>().having(
            (value) => value.message,
            'message',
            'No element',
          ),
        );
      }
      _observe(buffer.nextWhere((_) => true), received, errors);
      async.flushMicrotasks();
      expect(received, isEmpty);
      expect(errors, hasLength(4));
      expect(errors.last.$1, isA<StateError>());
    });
  });

  test(
    'error close preserves error and stack for pending and later consumers',
    () {
      fakeAsync((async) {
        final buffer = WampEventBuffer();
        final failure = StateError('transport disconnected');
        final stack = StackTrace.fromString('original transport stack');
        final received = <core.LazyEventPayload>[];
        final errors = <(Object, StackTrace)>[];
        for (var i = 0; i < 3; i++) {
          _observe(buffer.nextWhere((_) => true), received, errors);
        }
        buffer.closeWithError(failure, stack);
        buffer.close();
        async.flushMicrotasks();
        expect(received, isEmpty);
        expect(errors, hasLength(3));
        for (final error in errors) {
          expect(error.$1, same(failure));
          expect(error.$2.toString(), stack.toString());
        }
        _observe(buffer.nextWhere((_) => true), received, errors);
        async.flushMicrotasks();
        expect(received, isEmpty);
        expect(errors, hasLength(4));
        expect(errors.last.$1, same(failure));
        expect(errors.last.$2.toString(), stack.toString());
      });
    },
  );

  test('buffered events drain before the terminal error', () {
    fakeAsync((async) {
      final buffer = WampEventBuffer();
      final first = _event(1);
      final second = _event(2);
      buffer.add(first);
      buffer.add(second);
      final failure = StateError('end of stream');
      buffer.closeWithError(failure);
      final received = <core.LazyEventPayload>[];
      final errors = <(Object, StackTrace)>[];
      _observe(
        buffer.nextWhere((event) => event.publicationId == 2),
        received,
        errors,
      );
      _observe(buffer.nextWhere((_) => true), received, errors);
      async.flushMicrotasks();
      expect(received, [second, first]);
      expect(errors, isEmpty);
      _observe(buffer.nextWhere((_) => true), received, errors);
      async.flushMicrotasks();
      expect(received, [second, first]);
      expect(errors, hasLength(1));
      expect(errors.single.$1, same(failure));
    });
  });

  test(
    'a rejected live matcher leaves the event available to another waiter',
    () {
      fakeAsync((async) {
        final buffer = WampEventBuffer();
        final failure = StateError('consumer decode failed');
        final received = <core.LazyEventPayload>[];
        final errors = <(Object, StackTrace)>[];
        _observe(buffer.nextWhere((_) => throw failure), received, errors);
        _observe(buffer.nextWhere((_) => true), received, errors);
        final event = _event(9);
        buffer.add(event);
        async.flushMicrotasks();
        expect(received, [event]);
        expect(errors, hasLength(1));
        expect(errors.single.$1, same(failure));
        buffer.close();
        async.flushMicrotasks();
        expect(received, [event]);
        expect(errors, hasLength(1));
      });
    },
  );

  test('nonmatching live events are replayed once in arrival order', () {
    fakeAsync((async) {
      final buffer = WampEventBuffer();
      final received = <core.LazyEventPayload>[];
      final errors = <(Object, StackTrace)>[];
      final first = _event(1);
      final second = _event(2);
      final wanted = _event(3);
      _observe(
        buffer.nextWhere((event) => identical(event, wanted)),
        received,
        errors,
      );
      buffer.add(first);
      buffer.add(second);
      async.flushMicrotasks();
      expect(received, isEmpty);
      expect(errors, isEmpty);
      buffer.add(wanted);
      async.flushMicrotasks();
      expect(received, [wanted]);
      _observe(buffer.nextWhere((_) => true), received, errors);
      _observe(buffer.nextWhere((_) => true), received, errors);
      async.flushMicrotasks();
      expect(received, [wanted, first, second]);
      expect(errors, isEmpty);
      buffer.close();
      _observe(buffer.nextWhere((_) => true), received, errors);
      async.flushMicrotasks();
      expect(received, [wanted, first, second]);
      expect(errors, hasLength(1));
      expect(errors.single.$1, isA<StateError>());
    });
  });
}

// Completing a buffer operation only schedules microtasks; no wall-clock or
// fake deadline is needed to assert its delivered value or terminal error.
void _observe(
  Future<core.LazyEventPayload> future,
  List<core.LazyEventPayload> received,
  List<(Object, StackTrace)> errors,
) {
  future.then<void>(
    received.add,
    onError: (Object error, StackTrace stack) {
      errors.add((error, stack));
    },
  );
}

core.LazyEventPayload _event(int publication) => core.Event(
  1,
  publication,
  core.EventDetails(),
  arguments: [publication],
).toLazyEventPayload();

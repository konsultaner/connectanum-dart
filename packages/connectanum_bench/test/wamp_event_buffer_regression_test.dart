@TestOn('vm')
library;

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:test/test.dart';

void main() {
  for (final failureIndex in [0, 1, 2]) {
    test(
      'replay matcher failure at $failureIndex preserves every buffered event in order',
      () async {
        final buffer = WampEventBuffer();
        final events = [for (var i = 1; i <= 3; i++) _event(i)];
        events.forEach(buffer.add);
        final failure = StateError('malformed event metadata');
        final seen = <core.LazyEventPayload>[];
        expect(
          () => buffer.nextWhere((event) {
            seen.add(event);
            if (identical(event, events[failureIndex])) throw failure;
            return false;
          }),
          throwsA(same(failure)),
        );
        expect(seen, events.take(failureIndex + 1).toList());
        final later = _event(4);
        buffer.add(later);
        buffer.close();
        for (final event in events) {
          await expectLater(
            buffer.nextWhere((_) => true),
            completion(same(event)),
          );
        }
        expect(await buffer.nextWhere((_) => true), same(later));
        await expectLater(buffer.nextWhere((_) => true), throwsStateError);
      },
    );
  }

  test(
    'normal close fails every pending consumer and remains closed',
    () async {
      final buffer = WampEventBuffer();
      final pending = [
        for (var i = 0; i < 3; i++) buffer.nextWhere((_) => true),
      ];
      final results = pending
          .map(
            (future) => expectLater(
              future,
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'message',
                  'No element',
                ),
              ),
            ),
          )
          .toList();
      buffer.close();
      buffer.close();
      await Future.wait(results);
      await expectLater(buffer.nextWhere((_) => true), throwsStateError);
    },
  );

  test(
    'error close preserves error and stack for pending and later consumers',
    () async {
      final buffer = WampEventBuffer();
      final failure = StateError('transport disconnected');
      final stack = StackTrace.fromString('original transport stack');
      final pending = [
        for (var i = 0; i < 3; i++) _failure(buffer.nextWhere((_) => true)),
      ];
      buffer.closeWithError(failure, stack);
      buffer.close();
      for (final result in await Future.wait(pending)) {
        expect(result.$1, same(failure));
        expect(result.$2.toString(), stack.toString());
      }
      final later = await _failure(buffer.nextWhere((_) => true));
      expect(later.$1, same(failure));
      expect(later.$2.toString(), stack.toString());
    },
  );

  test('buffered events drain before the terminal error', () async {
    final buffer = WampEventBuffer();
    final first = _event(1);
    final second = _event(2);
    buffer.add(first);
    buffer.add(second);
    final failure = StateError('end of stream');
    buffer.closeWithError(failure);
    expect(
      await buffer.nextWhere((event) => event.publicationId == 2),
      same(second),
    );
    expect(await buffer.nextWhere((_) => true), same(first));
    await expectLater(buffer.nextWhere((_) => true), throwsA(same(failure)));
  });

  test(
    'a rejected live matcher leaves the event available to another waiter',
    () async {
      final buffer = WampEventBuffer();
      final failure = StateError('consumer decode failed');
      final rejected = expectLater(
        buffer.nextWhere((_) => throw failure),
        throwsA(same(failure)),
      );
      final accepted = buffer.nextWhere((_) => true);
      final event = _event(9);
      buffer.add(event);
      await rejected;
      expect(await accepted, same(event));
      buffer.close();
    },
  );
}

Future<(Object, StackTrace)> _failure(Future<Object?> future) {
  return future.then<(Object, StackTrace)>(
    (_) => throw TestFailure('Expected a terminal error, not an event.'),
    onError: (Object error, StackTrace stack) => (error, stack),
  );
}

core.LazyEventPayload _event(int publication) => core.Event(
  1,
  publication,
  core.EventDetails(),
  arguments: [publication],
).toLazyEventPayload();

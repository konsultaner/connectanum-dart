import 'dart:async';
import 'package:test/test.dart';
import 'package:connectanum_router/src/router/copy_metrics_fence.dart';

void main() {
  test('snapshot waits for earlier work and blocks later work', () async {
    final fence = CopyMetricsFence();
    final release = Completer<void>();
    final events = <String>[];
    final first = fence.submit(() async {
      events.add('first-start');
      await release.future;
      events.add('first-end');
    });
    final snapshot = fence.snapshot(() {
      events.add('snapshot');
      return events.toList();
    });
    final later = fence.submit(() async => events.add('later'));
    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);
    release.complete();
    expect(await snapshot, ['first-start', 'first-end', 'snapshot']);
    await Future.wait([first, later]);
    expect(events, ['first-start', 'first-end', 'snapshot', 'later']);
  });

  test('overlapping fences retain command order', () async {
    final fence = CopyMetricsFence();
    final release = Completer<void>();
    var count = 0;
    final operation = fence.submit(() async {
      await release.future;
      count++;
    });
    final first = fence.snapshot(() => count);
    final between = fence.submit(() async {
      count += 2;
    });
    final second = fence.snapshot(() => count);
    release.complete();
    expect(await first, 1);
    expect(await second, 3);
    await Future.wait([operation, between]);
  });

  test(
    'failed observation releases later work but remains failed closed',
    () async {
      final fence = CopyMetricsFence();
      final failed = fence.snapshot<int>(() => throw StateError('reader'));
      final failure = expectLater(failed, throwsStateError);
      var ran = false;
      await fence.submit(() async {
        ran = true;
      });
      await failure;
      expect(ran, isTrue);
      expect(await fence.snapshot(() => 4), 4);
    },
  );

  test(
    'timeout releases later commands and invalidates later snapshots',
    () async {
      final fence = CopyMetricsFence();
      final never = Completer<void>();
      unawaited(fence.submit(() => never.future));
      final snapshot = fence.snapshot(
        () => 0,
        timeout: const Duration(milliseconds: 5),
      );
      final failure = expectLater(snapshot, throwsA(isA<TimeoutException>()));
      var ran = false;
      await fence
          .submit(() async {
            ran = true;
          })
          .timeout(const Duration(seconds: 1));
      await failure;
      expect(ran, isTrue);
      await expectLater(fence.snapshot(() => 0), throwsStateError);
      never.complete();
    },
  );

  test('a late operation error after timeout is observed once', () async {
    final fence = CopyMetricsFence();
    final release = Completer<void>();
    final operation = fence.submit(() => release.future);
    final operationFailure = expectLater(operation, throwsStateError);
    await expectLater(
      fence.snapshot(() => 0, timeout: const Duration(milliseconds: 5)),
      throwsA(isA<TimeoutException>()),
    );
    await expectLater(fence.snapshot(() => 0), throwsStateError);
    release.completeError(StateError('late failure'));
    await operationFailure;
    await Future<void>.delayed(Duration.zero);
  });

  test('settled observations restore immediate command submission', () async {
    final fence = CopyMetricsFence();
    await fence.snapshot(() => 1);
    await Future<void>.delayed(Duration.zero);
    var started = false;
    final operation = fence.submit(() async {
      started = true;
    });
    expect(started, isTrue);
    await operation;
  });

  test('failed operation invalidates this and later observations', () async {
    final fence = CopyMetricsFence();
    final release = Completer<void>();
    final operation = fence.submit(() async {
      await release.future;
      throw StateError('lost work');
    });
    final failure = expectLater(operation, throwsStateError);
    final snapshot = fence.snapshot(() => 0);
    final observationFailure = expectLater(snapshot, throwsStateError);
    release.complete();
    await Future.wait([failure, observationFailure]);
    await fence.submit(() async {});
    await expectLater(fence.snapshot(() => 0), throwsStateError);
  });
}

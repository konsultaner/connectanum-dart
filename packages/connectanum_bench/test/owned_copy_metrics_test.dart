import 'package:connectanum_bench/src/owned_copy_metrics.dart';
import 'package:test/test.dart';

void main() {
  final zero = <String, Object?>{
    for (final field in ownedCopyObservationFields) field: 0,
  };
  test('complete zero window differs from disabled observation', () {
    expect(ownedBufferCopyMetricsDelta(zero, zero)['known_copy_bytes'], 0);
    for (final pair in [(null, zero), (zero, null)]) {
      final result = ownedBufferCopyMetricsDelta(pair.$1, pair.$2);
      expect(result['status'], 'not_measured');
      expect(result, isNot(contains('known_copy_bytes')));
    }
  });
  test(
    'only new bytes count and old failure flags do not invalidate a window',
    () {
      final before = {for (final field in ownedCopyObservationFields) field: 9};
      final after = <String, Object?>{...before};
      for (var i = 0; i < ownedCopyObservationFields.length - 2; i++) {
        after[ownedCopyObservationFields[i]] = 10 + i;
      }
      final result = ownedBufferCopyMetricsDelta(before, after);
      expect(result['status'], 'measured');
      expect(result['known_copy_bytes'], 45);
      expect(result['failed_copy_operations'], 0);
      expect(result['unmeasured_copy_operations'], 0);
    },
  );
  for (final field in ownedCopyObservationFields) {
    for (final side in ['before', 'after']) {
      for (final invalid in <Object?>[null, -1, '1', true, 1.0, [], {}]) {
        test('$side $field=$invalid fails closed', () {
          final changed = {...zero, field: invalid};
          final result = ownedBufferCopyMetricsDelta(
            side == 'before' ? changed : zero,
            side == 'after' ? changed : zero,
          );
          expect(result['status'], 'not_measured');
          expect(result, isNot(contains('known_copy_bytes')));
        });
      }
    }
    test('$field rewind fails closed', () {
      final result = ownedBufferCopyMetricsDelta({...zero, field: 1}, zero);
      expect(result['status'], 'not_measured');
      expect(result, isNot(contains('known_copy_bytes')));
    });
  }
  for (final flag in ['failed_copy_operations', 'unmeasured_copy_operations']) {
    test('$flag retains diagnostic bytes without certifying a total', () {
      final result = ownedBufferCopyMetricsDelta(zero, {
        ...zero,
        'clone_copy_bytes': 12,
        flag: 1,
      });
      expect(result['status'], 'not_measured');
      expect(result, isNot(contains('known_copy_bytes')));
      expect((result['observed_deltas'] as Map)['clone_copy_bytes'], 12);
    });
  }

  Map<String, Object?> router({
    int generation = 1,
    Map<String, Object?>? main,
    Map<String, Object?>? workers,
  }) => {
    'status': 'measured',
    'boss_generation': generation,
    'main_isolate': main ?? zero,
    'workers': workers ?? {'3': zero, '5': zero},
  };
  test('router message volume requires every stable quiescent isolate', () {
    Map<String, Object?> snapshot(int bytes) => {
      ...zero,
      'encoded_wamp_volume_version': 1,
      'encoded_wamp_bytes_accepted': bytes,
      'encoded_wamp_send_rejections': 0,
    };
    final before = router(
      main: snapshot(7),
      workers: {'3': snapshot(11), '5': snapshot(13)},
    );
    final after = router(
      main: snapshot(17),
      workers: {'3': snapshot(31), '5': snapshot(43)},
    );
    final result = routerOwnedBufferCopyMetricsDelta(
      before,
      after,
      quiescent: true,
    );
    final volume = result['encoded_wamp_volume'] as Map;
    expect(volume['accepted_bytes'], 60);
    expect(volume['components'], {'main_isolate': 10, '3': 20, '5': 30});
    expect(result['known_copy_bytes'], 0);
    final incomplete = routerOwnedBufferCopyMetricsDelta(
      before,
      router(main: snapshot(17), workers: {'3': snapshot(31), '5': zero}),
      quiescent: true,
    );
    expect(
      (incomplete['encoded_wamp_volume'] as Map)['status'],
      'not_measured',
    );
    expect(incomplete['known_copy_bytes'], 0);
    expect(
      routerOwnedBufferCopyMetricsDelta(
        before,
        after,
        quiescent: false,
      )['status'],
      'not_measured',
    );
  });

  test('router adds main and every stable worker exactly once', () {
    final result = routerOwnedBufferCopyMetricsDelta(
      router(),
      router(
        main: {...zero, 'clone_copy_bytes': 3},
        workers: {
          '5': {...zero, 'isolate_transfer_copy_bytes': 7},
          '3': {...zero, 'coalescing_copy_bytes': 5},
        },
      ),
      quiescent: true,
    );
    expect(result['status'], 'measured');
    expect(result['known_copy_bytes'], 15);
    expect((result['workers'] as Map).keys, unorderedEquals(['3', '5']));
  });
  for (final after in <Map<String, Object?>?>[
    null,
    {'status': 'not_measured'},
    router(generation: 2),
    router(workers: {}),
    router(workers: {'3': zero}),
    router(workers: {'3': zero, '5': zero, '6': zero}),
    router(workers: {'3': zero, '6': zero}),
    router(main: {...zero, 'failed_copy_operations': 1}),
    router(
      workers: {
        '3': zero,
        '5': {...zero, 'unmeasured_copy_operations': 1},
      },
    ),
    {...router(), 'boss_generation': '1'},
    {...router(), 'main_isolate': []},
    {
      ...router(),
      'workers': {1: zero},
    },
  ]) {
    test('incomplete or replaced router snapshot fails closed $after', () {
      final result = routerOwnedBufferCopyMetricsDelta(
        router(),
        after,
        quiescent: true,
      );
      expect(result['status'], 'not_measured');
      expect(result, isNot(contains('known_copy_bytes')));
    });
  }
  test('unsettled router window cannot certify a total', () {
    final result = routerOwnedBufferCopyMetricsDelta(
      router(),
      router(),
      quiescent: false,
    );
    expect(result['status'], 'not_measured');
    expect(result, isNot(contains('known_copy_bytes')));
  });
}

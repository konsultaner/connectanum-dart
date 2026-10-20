import 'package:connectanum_bench/src/dart_heap_allocation_volume.dart';
import 'package:test/test.dart';

const group = 'isolateGroups/7';
DartHeapUsageSnapshot snapshot({
  bool end = false,
  int? used,
  int? young,
  int old = 4,
  String identity = group,
}) => DartHeapUsageSnapshot(
  beforeMicros: end ? 190 : 100,
  afterMicros: end ? 200 : 110,
  groups: {
    identity: (
      usedBytes: used ?? (end ? 900000 : 1000000),
      youngCollections: young ?? (end ? 3 : 2),
      oldCollections: old,
    ),
  },
);

Map<String, dynamic> collection({String name = 'CollectNewGeneration'}) => {
  'name': name,
  'cat': 'GC',
  'ph': 'E',
  'ts': 140,
  'tid': 9,
  'args': <String, dynamic>{
    'isolateGroupId': group,
    'Before.New.Used (kB)': '8000',
    'After.New.Used (kB)': '6000',
    'Before.Old.Used (kB)': '5000',
    'After.Old.Used (kB)': '5000',
  },
};

void main() {
  test('KB conversion and cross-group heap sums cannot overflow', () {
    final oversized = collection();
    (oversized['args'] as Map)['Before.New.Used (kB)'] = 8796093022208;
    expect(
      dartHeapAllocationVolume(snapshot(), snapshot(end: true), [
        oversized,
      ])['status'],
      'not_measured',
    );
    final groups = {
      group: (
        usedBytes: 9007199254740991,
        youngCollections: 0,
        oldCollections: 0,
      ),
      'isolateGroups/8': (usedBytes: 1, youngCollections: 0, oldCollections: 0),
    };
    expect(
      dartHeapAllocationVolume(
        DartHeapUsageSnapshot(
          beforeMicros: 100,
          afterMicros: 110,
          groups: groups,
        ),
        DartHeapUsageSnapshot(
          beforeMicros: 190,
          afterMicros: 200,
          groups: groups,
        ),
        [],
      )['status'],
      'not_measured',
    );
  });
  test(
    'boundary capture rejects unknown heap collectors but ignores phase markers',
    () async {
      final unknown = collection(name: 'FutureCollector')..['ts'] = 105;
      expect(
        await captureDartHeapBoundary(
          capture: () async => snapshot(),
          events: (_) async => [unknown],
          quiet: () async {
            fail('Unsupported evidence must stay unavailable');
          },
        ),
        isNull,
      );
      final marker = {
        'cat': 'GC',
        'name': 'PhaseMarker',
        'args': {'isolateGroupId': group},
      };
      expect(
        await captureDartHeapBoundary(
          capture: () async => snapshot(),
          events: (_) async => [marker],
          quiet: () async {
            fail('An informational marker does not cross a collection');
          },
        ),
        isNotNull,
      );
    },
  );

  test(
    'snapshot retry retains earlier GC in the complete allocation window',
    () async {
      final crossed = collection()..['ts'] = 195;
      var calls = 0;
      var waits = 0;
      final end = await captureDartHeapBoundary(
        capture: () async {
          calls++;
          return calls == 1
              ? snapshot(end: true)
              : DartHeapUsageSnapshot(
                  beforeMicros: 250,
                  afterMicros: 260,
                  groups: snapshot(end: true).groups,
                );
        },
        events: (s) async => s.beforeMicros == 190 ? [crossed] : [],
        quiet: () async {
          waits++;
        },
      );
      expect(calls, 2);
      expect(waits, 1);
      final volume = dartHeapAllocationVolume(snapshot(), end, [crossed]);
      expect(volume['status'], 'measured');
      expect(volume['estimated_bytes'], 1948000);
      expect(volume['young_gc_events'], 1);
    },
  );
  test(
    'snapshot retries are bounded and do not accept persistent overlap',
    () async {
      var calls = 0;
      var waits = 0;
      final result = await captureDartHeapBoundary(
        capture: () async {
          calls++;
          return snapshot();
        },
        events: (_) async => [collection()..['ts'] = 105],
        quiet: () async {
          waits++;
        },
      );
      expect(result, isNull);
      expect(calls, 3);
      expect(waits, 2);
    },
  );
  for (final missing in ['snapshot', 'trace', 'malformed']) {
    test('boundary fails closed for $missing evidence', () async {
      var calls = 0;
      final result = await captureDartHeapBoundary(
        capture: () async {
          calls++;
          return missing == 'snapshot' ? null : snapshot();
        },
        events: (_) async =>
            missing == 'trace' ? null : [collection()..['ts'] = -1],
        quiet: () async {
          fail('Missing evidence cannot be retried into success');
        },
      );
      expect(result, isNull);
      expect(calls, 1);
    });
  }

  Map<String, Object?> measured(List<Map<String, dynamic>> events) =>
      dartHeapAllocationVolume(snapshot(), snapshot(end: true), events);

  test(
    'volume retains reclaimed objects and reports bounded KB uncertainty',
    () {
      final result = measured([collection()]);
      expect(result['status'], 'measured');
      expect(result['estimated_bytes'], 1948000);
      expect(result['rounding_error_bound_bytes'], 2048);
      expect(result['young_gc_events'], 1);
      expect(result['old_gc_events'], 0);
      expect(result['heap_group_ids'], [group]);
    },
  );
  test('promotion cancels across generations instead of counting copies', () {
    final event = collection();
    final args = event['args'] as Map;
    args['After.New.Used (kB)'] = '4000';
    args['After.Old.Used (kB)'] = '8000';
    expect(measured([event])['estimated_bytes'], 924000);
  });
  test(
    'consistent replay is deduplicated but conflicting replay is rejected',
    () {
      expect(
        measured([collection(), collection()])['estimated_bytes'],
        1948000,
      );
      final conflict = collection();
      (conflict['args'] as Map)['After.New.Used (kB)'] = '5999';
      expect(measured([collection(), conflict])['status'], 'not_measured');
    },
  );
  test('both concurrent start and final collection contribute old counts', () {
    final start = collection(name: 'StartConcurrentMarking')..['ts'] = 120;
    (start['args'] as Map)['After.New.Used (kB)'] = '8000';
    final end = collection(name: 'CollectOldGeneration');
    final result = dartHeapAllocationVolume(
      snapshot(),
      snapshot(end: true, young: 2, old: 6),
      [start, end],
    );
    expect(result['status'], 'measured');
    expect(result['old_gc_events'], 2);
    expect(result['rounding_error_bound_bytes'], 4096);
    expect(result['estimated_bytes'], 1948000);
  });
  test(
    'missing or extra collections cannot silently change allocation volume',
    () {
      expect(measured([])['status'], 'not_measured');
      final extra = collection()..['ts'] = 150;
      expect(measured([collection(), extra])['status'], 'not_measured');
    },
  );
  for (final time in [100, 105, 110, 190, 195, 200]) {
    test('collection at ambiguous snapshot timestamp $time is unavailable', () {
      expect(measured([collection()..['ts'] = time])['status'], 'not_measured');
    });
  }
  for (final field in ['Before.New.Used (kB)', 'After.Old.Used (kB)']) {
    for (final invalid in <Object?>[
      null,
      -1,
      '-1',
      1.5,
      true,
      '1e3',
      ' 1',
      1 << 62,
    ]) {
      test('invalid $field=$invalid cannot certify an allocation window', () {
        final event = collection();
        (event['args'] as Map)[field] = invalid;
        expect(measured([event])['status'], 'not_measured');
      });
    }
  }
  test('future collection format and malformed event timing fail closed', () {
    expect(
      measured([collection(name: 'FutureCollection')])['status'],
      'not_measured',
    );
    expect(measured([collection()..['ts'] = 1.0])['status'], 'not_measured');
    expect(measured([collection()..['tid'] = true])['status'], 'not_measured');
    expect(measured([collection()..['ph'] = 'X'])['status'], 'not_measured');
  });
  test('duration-format event uses its ending timestamp', () {
    final event = collection()..addAll({'ph': 'X', 'ts': 120, 'dur': 20});
    expect(measured([event])['estimated_bytes'], 1948000);
  });
  test(
    'missing/replaced heaps and rewound native counters are unavailable',
    () {
      for (final end in [
        null,
        snapshot(end: true, identity: 'isolateGroups/8'),
        snapshot(end: true, young: 1),
        snapshot(end: true, old: 3),
        snapshot(end: true, used: -1),
      ]) {
        expect(
          dartHeapAllocationVolume(snapshot(), end, [collection()])['status'],
          'not_measured',
        );
      }
      expect(
        dartHeapAllocationVolume(null, snapshot(end: true), [])['status'],
        'not_measured',
      );
    },
  );
  test(
    'rounding uncertainty must fit the one-percent precision requirement',
    () {
      final result = dartHeapAllocationVolume(
        snapshot(),
        snapshot(end: true, used: 0),
        [collection()],
      );
      expect(result['status'], 'measured');
      final event = collection();
      (event['args'] as Map)['After.New.Used (kB)'] = '7800';
      expect(measured([event])['status'], 'not_measured');
    },
  );
  test('zero collections use heap growth while unobserved shrinkage fails', () {
    expect(
      dartHeapAllocationVolume(
        snapshot(),
        snapshot(end: true, young: 2, used: 1500000),
        [],
      )['estimated_bytes'],
      500000,
    );
    expect(
      dartHeapAllocationVolume(
        snapshot(),
        snapshot(end: true, young: 2),
        [],
      )['status'],
      'not_measured',
    );
    expect(
      dartHeapAllocationVolume(
        snapshot(),
        snapshot(end: true, young: 2, used: 1000000),
        [],
      )['estimated_bytes'],
      0,
    );
  });
}

import 'dart:convert';
import 'package:connectanum_bench/src/dart_heap_allocation_volume.dart';
import 'package:connectanum_bench/src/dart_vm_metrics.dart';
import 'package:connectanum_bench/src/dart_vm_metrics_wire.dart';
import 'package:test/test.dart';

void main() {
  const group = 'isolateGroups/7';
  const start = DartHeapUsageSnapshot(
    beforeMicros: 100,
    afterMicros: 110,
    groups: {
      group: (usedBytes: 1000000, youngCollections: 1, oldCollections: 2),
    },
  );
  const window = DartVmMetricsWindow(
    cpuUserTicks: 11,
    cpuSystemTicks: 12,
    isolateIds: ['isolates/1', 'isolates/2'],
    profiledIsolateIds: ['isolates/1'],
    gcSnapshots: {
      group: DartVmGcHeapSnapshot(
        newCollections: 1,
        oldCollections: 2,
        newPauseMicros: 3,
        oldPauseMicros: 4,
        heapUsedBytes: 1000000,
      ),
    },
    allocationSnapshot: start,
  );
  Map<String, Object?> copy(Map<String, Object?> value) =>
      Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

  test(
    'window crosses a real JSON boundary without duplicating shared heaps',
    () {
      final restored = decodeMetricsWindow(copy(encodeMetricsWindow(window)));
      expect(restored.isolateIds, window.isolateIds);
      expect(restored.profiledIsolateIds, ['isolates/1']);
      expect(restored.cpuUserTicks, 11);
      expect(restored.cpuSystemTicks, 12);
      expect(restored.gcSnapshots!.length, 1);
      expect(restored.gcSnapshots![group]!.newPauseMicros, 3);
      expect(restored.gcSnapshots![group]!.oldPauseMicros, 4);
      expect(restored.allocationSnapshot!.groups, start.groups);
      expect(restored.allocationSnapshot!.beforeMicros, 100);
      expect(restored.allocationSnapshot!.afterMicros, 110);
    },
  );
  test('unavailable window metadata remains unavailable', () {
    const missing = DartVmMetricsWindow(
      cpuUserTicks: null,
      cpuSystemTicks: null,
      isolateIds: [],
    );
    final restored = decodeMetricsWindow(copy(encodeMetricsWindow(missing)));
    expect(restored.cpuUserTicks, isNull);
    expect(restored.cpuSystemTicks, isNull);
    expect(restored.gcSnapshots, isNull);
    expect(restored.allocationSnapshot, isNull);
    expect(restored.profiledIsolateIds, isNull);
  });
  test('allocation snapshots cannot lose their heap usage evidence', () {
    for (final missing in ['heap', 'bytes']) {
      final json = copy(encodeMetricsWindow(window));
      if (missing == 'heap') {
        json['gc_snapshots'] = null;
      } else {
        ((json['gc_snapshots'] as Map)[group] as Map)['heap_used_bytes'] = null;
      }
      expect(() => decodeMetricsWindow(json), throwsFormatException);
    }
  });
  for (final invalid in <Object?>[
    null,
    1,
    [],
    {1: 2},
  ]) {
    test('non-object $invalid fails before decoding resource values', () {
      expect(() => metricsObject(invalid), throwsFormatException);
    });
  }
  for (final invalid in <Object?>[
    null,
    1,
    [1],
    [''],
    ['isolates/1', 'isolates/1'],
  ]) {
    test('invalid isolate identities $invalid cannot cross the observer', () {
      final json = copy(encodeMetricsWindow(window));
      json['isolate_ids'] = invalid;
      expect(() => decodeMetricsWindow(json), throwsFormatException);
    });
  }
  test(
    'missing required heap counters and empty group identities are rejected',
    () {
      final json = copy(encodeMetricsWindow(window));
      ((json['gc_snapshots'] as Map)[group] as Map).remove('young_collections');
      expect(() => decodeMetricsWindow(json), throwsFormatException);
      final empty = copy(encodeMetricsWindow(window));
      final heaps = empty['gc_snapshots'] as Map;
      heaps[''] = heaps.remove(group);
      expect(() => decodeMetricsWindow(empty), throwsFormatException);
    },
  );
  final metadata = dartHeapAllocationVolume(
    start,
    const DartHeapUsageSnapshot(
      beforeMicros: 200,
      afterMicros: 210,
      groups: {
        group: (usedBytes: 1500000, youngCollections: 1, oldCollections: 2),
      },
    ),
    [],
  );
  final result = DartVmMetricsResult(
    allocatedBytes: 500000,
    allocationMeasurement: metadata,
    gcCount: 0,
    gcPauseMicros: 0,
    cpuUserMicros: 5,
    cpuSystemMicros: 6,
    currentRssBytes: 7000000,
    peakRssBytes: 8000000,
  );
  test('raw allocation proof and process metrics survive JSON roundtrip', () {
    final restored = decodeMetricsResult(copy(encodeMetricsResult(result)));
    expect(encodeMetricsResult(restored), encodeMetricsResult(result));
    expect(restored.allocationMeasurement!['estimated_bytes'], 500000);
    expect(restored.allocationMeasurement!['gc_observations'], isEmpty);
  });
  const fields = [
    'allocated_bytes',
    'gc_count',
    'gc_pause_us',
    'cpu_user_us',
    'cpu_system_us',
    'current_rss_bytes',
    'peak_rss_bytes',
  ];
  for (final field in fields) {
    test('missing $field stays null rather than becoming zero', () {
      final json = copy(encodeMetricsResult(result))..remove(field);
      expect(encodeMetricsResult(decodeMetricsResult(json))[field], isNull);
    });
    for (final invalid in <Object?>[-1, true, 1.5, '1', 1 << 62]) {
      test(
        'invalid resource $field=$invalid cannot become numeric evidence',
        () {
          final json = copy(encodeMetricsResult(result))..[field] = invalid;
          expect(() => decodeMetricsResult(json), throwsFormatException);
        },
      );
    }
  }
}

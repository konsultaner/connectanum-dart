import 'package:connectanum_bench/src/dart_vm_metrics.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

Map<String, dynamic> _heap({Object? count = 2, Object? seconds = 0.001234}) => {
  'collections': count,
  'time': seconds,
};

DartVmGcHeapSnapshot _snapshot(int count, int micros) => DartVmGcHeapSnapshot(
  newCollections: count,
  oldCollections: count * 2,
  newPauseMicros: micros,
  oldPauseMicros: micros * 3,
);

void main() {
  test(
    'profiles a shared heap once, while retaining separate isolate groups',
    () {
      expect(
        selectDartVmMetricHeapRepresentativeIds(
          [
            IsolateRef(id: 'main', isolateGroupId: 'g1'),
            IsolateRef(id: 'worker', isolateGroupId: 'g1'),
            IsolateRef(id: 'other', isolateGroupId: 'g2'),
          ],
          ['main', 'worker', 'other'],
        ),
        ['main', 'other'],
      );
    },
  );

  test('missing selected isolate or group cannot imply heap uniqueness', () {
    for (final refs in [
      <IsolateRef>[],
      [IsolateRef(id: 'main')],
      [IsolateRef(id: 'main', isolateGroupId: '')],
    ]) {
      expect(selectDartVmMetricHeapRepresentativeIds(refs, ['main']), isNull);
    }
  });

  test('native seconds become microseconds for both heap generations', () {
    final snapshot = DartVmGcHeapSnapshot.parse({
      '_heaps': {
        'new': _heap(),
        'old': _heap(count: 3, seconds: 0.005678),
      },
    })!;
    expect(snapshot.newCollections, 2);
    expect(snapshot.oldCollections, 3);
    expect(snapshot.newPauseMicros, 1234);
    expect(snapshot.oldPauseMicros, 5678);
  });

  for (final invalid in [null, 'unknown', -1, 1.5]) {
    test('invalid collection count $invalid is unavailable', () {
      expect(
        DartVmGcHeapSnapshot.parse({
          '_heaps': {'new': _heap(count: invalid), 'old': _heap()},
        }),
        isNull,
      );
    });
  }
  for (final invalid in [
    null,
    'unknown',
    -1,
    double.nan,
    double.infinity,
    1e300,
  ]) {
    test('invalid cumulative GC time $invalid is unavailable', () {
      expect(
        DartVmGcHeapSnapshot.parse({
          '_heaps': {'new': _heap(), 'old': _heap(seconds: invalid)},
        }),
        isNull,
      );
    });
  }
  test('missing SDK heap fields stay unavailable', () {
    for (final isolate in <Map<String, dynamic>?>[
      null,
      {},
      {'_heaps': 'unknown'},
      {'_heaps': {}},
      {
        '_heaps': {'new': _heap(), 'old': null},
      },
    ]) {
      expect(DartVmGcHeapSnapshot.parse(isolate), isNull);
    }
  });

  test('adds both generation deltas once for every observed group', () {
    expect(
      dartVmGcHeapDelta(
        {'g1': _snapshot(2, 100), 'g2': _snapshot(4, 200)},
        {'g1': _snapshot(3, 110), 'g2': _snapshot(6, 220)},
      ),
      (count: 9, pauseMicros: 120),
    );
    expect(
      dartVmGcHeapDelta({'g1': _snapshot(0, 0)}, {'g1': _snapshot(0, 0)}),
      (count: 0, pauseMicros: 0),
    );
  });

  test('missing snapshots or changed group sets cannot produce zero', () {
    final valid = {'g1': _snapshot(2, 100)};
    for (final missing in <Map<String, DartVmGcHeapSnapshot>?>[
      null,
      {},
      {'g2': _snapshot(2, 100)},
      {'g1': _snapshot(2, 100), 'g2': _snapshot(1, 1)},
    ]) {
      expect(dartVmGcHeapDelta(valid, missing), isNull);
      expect(dartVmGcHeapDelta(missing, valid), isNull);
    }
  });

  for (var field = 0; field < 4; field++) {
    test('rewind of generation counter $field invalidates the whole delta', () {
      final after = DartVmGcHeapSnapshot(
        newCollections: field == 0 ? 1 : 20,
        oldCollections: field == 1 ? 1 : 20,
        newPauseMicros: field == 2 ? 1 : 1000,
        oldPauseMicros: field == 3 ? 1 : 1000,
      );
      expect(
        dartVmGcHeapDelta({'g1': _snapshot(2, 100)}, {'g1': after}),
        isNull,
      );
    });
  }
}

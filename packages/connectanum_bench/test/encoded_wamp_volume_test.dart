import 'package:connectanum_bench/src/encoded_wamp_volume.dart';
import 'package:connectanum_bench/src/codec_copy_metrics.dart';
import 'package:connectanum_bench/src/owned_copy_metrics.dart';
import 'package:connectanum_core/src/serializer/owned_copy_metrics.dart';
import 'package:test/test.dart';

Map<String, Object?> snapshot({int bytes = 0, int rejected = 0}) => {
  encodedWampVolumeVersionField: 1,
  encodedWampVolumeBytesField: bytes,
  encodedWampVolumeRejectedField: rejected,
};

void main() {
  test(
    'zero and positive volume use actual disjoint monotonic observations',
    () {
      expect(
        encodedWampVolumeDelta(snapshot(), snapshot())['accepted_bytes'],
        0,
      );
      final measured = encodedWampVolumeDelta(
        snapshot(bytes: 11),
        snapshot(bytes: 39),
      );
      expect(measured['accepted_bytes'], 28);
      final merged = mergeEncodedWampVolumes({'a': measured, 'b': measured});
      expect(merged['status'], 'measured');
      expect(merged['accepted_bytes'], 56);
      expect(merged['components'], {'a': 28, 'b': 28});
    },
  );
  for (final invalid in [null, true, 1.0, 1.5, '1', 0, -1, 2]) {
    for (final earlier in [true, false]) {
      test(
        'version $invalid earlier=$earlier cannot certify byte observations',
        () {
          final bad = {...snapshot(), encodedWampVolumeVersionField: invalid};
          expect(
            encodedWampVolumeDelta(
              earlier ? bad : snapshot(),
              earlier ? snapshot() : bad,
            )['status'],
            'not_measured',
          );
        },
      );
    }
  }
  for (final field in [
    encodedWampVolumeBytesField,
    encodedWampVolumeRejectedField,
  ]) {
    for (final invalid in [null, true, 1.0, '1', -1, 9007199254740992]) {
      for (final earlier in [true, false]) {
        test('$field $invalid earlier=$earlier is unavailable', () {
          final bad = {...snapshot(), field: invalid};
          expect(
            encodedWampVolumeDelta(
              earlier ? bad : snapshot(),
              earlier ? snapshot() : bad,
            )['status'],
            'not_measured',
          );
        });
      }
    }
    test('$field rewind is unavailable', () {
      expect(
        encodedWampVolumeDelta(
          {...snapshot(), field: 2},
          {...snapshot(), field: 1},
        )['status'],
        'not_measured',
      );
    });
  }
  test('missing snapshots and rejected sends retain uncertainty', () {
    expect(encodedWampVolumeDelta(null, snapshot())['status'], 'not_measured');
    expect(encodedWampVolumeDelta(snapshot(), null)['status'], 'not_measured');
    final failed = encodedWampVolumeDelta(
      snapshot(),
      snapshot(bytes: 17, rejected: 1),
    );
    expect(failed['status'], 'not_measured');
    expect(failed['known_accepted_bytes'], 17);
    expect(failed['rejected_submissions'], 1);
    expect(failed, isNot(contains('accepted_bytes')));
  });
  for (final mutate in <void Function(Map<String, Object?>)>[
    (m) => m['status'] = 'not_measured',
    (m) => m['measurement_scope'] = 'application_bytes',
    (m) => m['accepted_bytes'] = null,
    (m) => m['accepted_bytes'] = -1,
    (m) => m['accepted_bytes'] = 1.0,
    (m) => m['accepted_bytes'] = 9007199254740992,
    (m) => m['rejected_submissions'] = 0.0,
    (m) => m['rejected_submissions'] = 1,
  ]) {
    test('incomplete component cannot become a measured aggregate $mutate', () {
      final bad = encodedWampVolumeDelta(snapshot(), snapshot());
      mutate(bad);
      expect(mergeEncodedWampVolumes({'bad': bad})['status'], 'not_measured');
    });
  }
  test('empty, malformed, and overflowing aggregates fail closed', () {
    expect(mergeEncodedWampVolumes({})['status'], 'not_measured');
    expect(mergeEncodedWampVolumes({'x': null})['status'], 'not_measured');
    final large = encodedWampVolumeDelta(
      snapshot(),
      snapshot(bytes: 9007199254740991),
    );
    expect(
      mergeEncodedWampVolumes({'a': large, 'b': large})['status'],
      'not_measured',
    );
  });
  test(
    'independent volume carriers never increase Dart or native copy totals',
    () {
      final dart = {
        for (final field in ownedCopyObservationFields) field: 0,
        ...snapshot(),
      };
      final native = {
        'coverage_version': 1,
        for (final field in codecCopyMetricFields) field: 0,
        ...snapshot(),
      };
      final after = snapshot(bytes: 123456);
      final dartDelta = ownedBufferCopyMetricsDelta(dart, {...dart, ...after});
      final nativeDelta = codecCopyMetricsDelta(
        native.cast<String, int>(),
        {...native, ...after}.cast<String, int>(),
      );
      for (final delta in [dartDelta, nativeDelta]) {
        expect(delta['known_copy_bytes'], 0);
        expect((delta['encoded_wamp_volume'] as Map)['accepted_bytes'], 123456);
      }
      expect(
        OwnedCopyMetrics.fields,
        isNot(contains(encodedWampVolumeBytesField)),
      );
    },
  );
}

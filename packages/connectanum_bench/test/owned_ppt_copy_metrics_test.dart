import 'package:connectanum_bench/src/transport_copy_metrics.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:test/test.dart';

void main() {
  test(
    'eligible settings without a measured owned submission are unmeasured',
    () {
      expect(ownedFlatBuffersPayloadCopyBytes([_sample({})]), _unmeasured);
      expect(ownedFlatBuffersPayloadCopyBytes([]), _unmeasured);
    },
  );

  for (final observation in [
    {
      'native_ppt_frame_submissions': 0,
      'native_ppt_payload_bytes': 10,
      'native_ppt_payload_reused_bytes': 0,
    },
    {
      'native_ppt_frame_submissions': 2,
      'native_ppt_payload_bytes': 10,
      'native_ppt_payload_reused_bytes': 20,
    },
    {
      'native_ppt_frame_submissions': 1,
      'native_ppt_payload_bytes': 10,
      'native_ppt_payload_reused_bytes': 9,
    },
    {
      'native_ppt_frame_submissions': 1,
      'native_ppt_payload_bytes': -1,
      'native_ppt_payload_reused_bytes': -1,
    },
    {'native_ppt_frame_submissions': 1, 'native_ppt_payload_bytes': 10},
    {'native_ppt_payload_bytes': 10, 'native_ppt_payload_reused_bytes': 10},
  ]) {
    test(
      'missing, fallback or mismatched owner observation $observation fails closed',
      () {
        if (observation['native_ppt_payload_bytes'] == -1) {
          expect(() => _sample(observation), throwsFormatException);
        } else {
          expect(
            ownedFlatBuffersPayloadCopyBytes([_sample(observation)]),
            _unmeasured,
          );
        }
      },
    );
  }

  for (final field in [
    'native_ppt_frame_submissions',
    'native_ppt_payload_bytes',
    'native_ppt_payload_reused_bytes',
  ]) {
    for (final invalid in <Object?>[
      '1',
      true,
      [],
      {},
      -1,
      0.5,
      double.nan,
      double.infinity,
      9007199254740992.0,
    ]) {
      test('rejects malformed owned observation $field=$invalid', () {
        expect(() => _sample({field: invalid}), throwsFormatException);
      });
    }
  }

  test('different owners cannot cancel a missing or extra submission', () {
    final samples = [
      _sample({
        'native_ppt_frame_submissions': 2,
        'native_ppt_payload_bytes': 10,
        'native_ppt_payload_reused_bytes': 20,
      }),
      _sample({
        'native_ppt_frame_submissions': 0,
        'native_ppt_payload_bytes': 20,
        'native_ppt_payload_reused_bytes': 10,
      }, worker: 1),
    ];
    // Aggregate counts (2) and reused bytes (30) match, but neither owner does.
    expect(ownedFlatBuffersPayloadCopyBytes(samples), _unmeasured);
  });

  test(
    'exact numeric observations round-trip without weakening legacy samples',
    () {
      final sample = _sample({
        'native_ppt_frame_submissions': 1.0,
        'native_ppt_payload_bytes': 10.0,
        'native_ppt_payload_reused_bytes': 10.0,
      });
      expect(sample.toJson()['native_ppt_frame_submissions'], 1);
      expect(sample.toJson()['native_ppt_payload_bytes'], 10);
      expect(sample.toJson()['native_ppt_payload_reused_bytes'], 10);
      expect(WampSample.fromJson(sample.toJson()).toJson(), sample.toJson());
      expect(
        _sample({}).toJson(),
        isNot(contains('native_ppt_frame_submissions')),
      );
    },
  );

  test('one observed native frame per owner reports zero payload copies', () {
    final samples = [
      _sample({
        'native_ppt_frame_submissions': 1,
        'native_ppt_payload_bytes': 10,
        'native_ppt_payload_reused_bytes': 10,
      }),
      _sample({
        'native_ppt_frame_submissions': 1,
        'native_ppt_payload_bytes': 20,
        'native_ppt_payload_reused_bytes': 20,
      }, worker: 1),
    ];
    expect(ownedFlatBuffersPayloadCopyBytes(samples), 0);
  });

  test('an observed empty owner differs from absent measurements', () {
    expect(
      ownedFlatBuffersPayloadCopyBytes([
        _sample({
          'native_ppt_frame_submissions': 1,
          'native_ppt_payload_bytes': 0,
          'native_ppt_payload_reused_bytes': 0,
        }),
      ]),
      0,
    );
    expect(ownedFlatBuffersPayloadCopyBytes([_sample({})]), _unmeasured);
  });
}

final _unmeasured = isA<Map<String, Object?>>().having(
  (value) => value['status'],
  'status',
  'not_measured',
);

WampSample _sample(Map<String, Object?> observation, {int worker = 0}) =>
    WampSample.fromJson({
      'worker': worker,
      'iteration': 0,
      'latency_ms': 1.0,
      'request_bytes': 10,
      'response_bytes': 10,
      ...observation,
    });

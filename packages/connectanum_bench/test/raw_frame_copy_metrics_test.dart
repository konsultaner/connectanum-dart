import 'package:connectanum_bench/src/raw_frame_copy_metrics.dart';
import 'package:test/test.dart';

void main() {
  final zero = {for (final field in rawFrameCopyMetricFields) field: 0};
  test(
    'retained single-span requests are separate from actual copied bytes',
    () {
      final result = rawFrameCopyMetricsDelta(zero, {
        ...zero,
        'single_segment_contiguous_requests': 19,
      });
      expect(result['status'], 'measured');
      expect(result['known_copy_bytes'], 0);
      expect(result['single_segment_contiguous_requests'], 19);
    },
  );
  test('coalescing and range copies add independently across a window', () {
    final result = rawFrameCopyMetricsDelta(
      {
        ...zero,
        'coalescing_copy_bytes': 10,
        'range_copy_bytes': 5,
      },
      {
        ...zero,
        'coalescing_copy_bytes': 110,
        'range_copy_bytes': 25,
        'multi_segment_contiguous_requests': 2,
      },
    );
    expect(result['coalescing_copy_bytes'], 100);
    expect(result['range_copy_bytes'], 20);
    expect(result['known_copy_bytes'], 120);
    expect(result['multi_segment_contiguous_requests'], 2);
  });
  for (final missing in [true, false]) {
    test(
      'missing ${missing ? 'before' : 'after'} observation is unavailable',
      () {
        final result = rawFrameCopyMetricsDelta(
          missing ? null : zero,
          missing ? zero : null,
        );
        expect(result['status'], 'not_measured');
        expect(result, isNot(contains('known_copy_bytes')));
      },
    );
  }
  for (final field in rawFrameCopyMetricFields) {
    for (final invalid in ['missing', 'negative', 'rewound']) {
      test('$field $invalid cannot certify a zero-copy window', () {
        final before = {...zero, field: 2};
        final after = {...zero, field: invalid == 'negative' ? -1 : 1};
        if (invalid == 'missing') after.remove(field);
        final result = rawFrameCopyMetricsDelta(before, after);
        expect(result['status'], 'not_measured');
        expect(result['reason'], contains(field));
        expect(result, isNot(contains('known_copy_bytes')));
      });
    }
  }
}

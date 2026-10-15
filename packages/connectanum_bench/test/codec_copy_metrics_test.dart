import 'package:connectanum_bench/src/codec_copy_metrics.dart';
import 'package:test/test.dart';

void main() {
  final zero = {for (final field in codecCopyMetricFields) field: 0};
  test('each native operation contributes source bytes once', () {
    final after = {for (final field in codecCopyMetricFields) field: 9};
    final result = codecCopyMetricsDelta(zero, after);
    expect(result['status'], 'measured');
    expect(result['known_copy_bytes'], 54);
    for (final field in codecCopyMetricFields) {
      expect(result[field], 9);
    }
  });
  for (final missing in [true, false]) {
    test(
      'missing ${missing ? 'before' : 'after'} observation is unavailable',
      () {
        final result = codecCopyMetricsDelta(
          missing ? null : zero,
          missing ? zero : null,
        );
        expect(result['status'], 'not_measured');
        expect(result, isNot(contains('known_copy_bytes')));
      },
    );
  }
  for (final field in codecCopyMetricFields) {
    for (final invalid in ['missing', 'negative', 'rewound']) {
      test('$field $invalid cannot certify a zero-copy window', () {
        final before = {...zero, field: 2};
        final after = {...zero, field: invalid == 'negative' ? -1 : 1};
        if (invalid == 'missing') after.remove(field);
        final result = codecCopyMetricsDelta(before, after);
        expect(result['status'], 'not_measured');
        expect(result['reason'], contains(field));
        expect(result, isNot(contains('known_copy_bytes')));
      });
    }
  }
}

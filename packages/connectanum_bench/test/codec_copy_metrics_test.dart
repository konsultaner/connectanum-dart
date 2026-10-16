import 'package:connectanum_bench/src/codec_copy_metrics.dart';
import 'package:test/test.dart';

void main() {
  test('an older six-counter ABI cannot certify expanded copy coverage', () {
    final oldSnapshot = {for (final field in codecCopyMetricFields) field: 0};
    expect(
      codecCopyMetricsDelta(oldSnapshot, oldSnapshot)['status'],
      'not_measured',
    );
  });
  final zero = {
    'coverage_version': 1,
    for (final field in codecCopyMetricFields) field: 0,
  };
  for (final version in [null, 0, -1, 2]) {
    for (final beforeInvalid in [true, false]) {
      test('coverage $version before=$beforeInvalid is unavailable', () {
        final invalid = {...zero};
        if (version == null) {
          invalid.remove('coverage_version');
        } else {
          invalid['coverage_version'] = version;
        }
        expect(
          codecCopyMetricsDelta(
            beforeInvalid ? invalid : zero,
            beforeInvalid ? zero : invalid,
          )['status'],
          'not_measured',
        );
      });
    }
  }
  test('each native operation contributes source bytes once', () {
    final after = {
      'coverage_version': 1,
      for (final field in codecCopyMetricFields) field: 9,
    };
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

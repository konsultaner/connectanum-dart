import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:test/test.dart';
import 'package:connectanum_bench/src/native_crypto_copy_metrics.dart';

NativeE2eeCopyMetrics _metrics(List<int?> values) => NativeE2eeCopyMetrics(
  dartToNativeCopiedBytesTotal: values[0]!,
  nativeToDartCopiedBytesTotal: values[1]!,
  ciphertextCoercionCopyBytesTotal: values[2]!,
  plaintextStagingCopyBytesTotal: values[3],
  ciphertextStagingCopyBytesTotal: values[4],
  nonceTagCopyBytesTotal: values[5],
  plaintextFramingCopyBytesTotal: values[6],
);
void main() {
  final zero = List<int?>.filled(7, 0);
  test('active provider retains every exact delta and their sum', () {
    final before = List<int?>.filled(7, 11);
    final after = [for (var i = 0; i < 7; i++) 12 + i];
    final report = nativeCryptoCopyMetricsDelta(
      _metrics(before),
      _metrics(after),
      active: true,
    );
    expect(report['status'], 'measured');
    expect(report['active'], true);
    expect(report['known_copy_bytes'], 28);
    for (var i = 0; i < 7; i++) {
      expect(report[nativeCryptoCopyFields[i]], i + 1);
    }
  });
  for (var i = 0; i < 7; i++) {
    for (final active in [true, false]) {
      test(
        '${nativeCryptoCopyFields[i]} rewind active=$active is unavailable',
        () {
          final before = [...zero]..[i] = 1;
          final report = nativeCryptoCopyMetricsDelta(
            _metrics(before),
            _metrics(zero),
            active: active,
          );
          expect(report['status'], 'not_measured');
          expect(report, isNot(contains('known_copy_bytes')));
        },
      );
      test(
        '${nativeCryptoCopyFields[i]} negative active=$active is unavailable',
        () {
          final before = [...zero]..[i] = -1;
          final report = nativeCryptoCopyMetricsDelta(
            _metrics(before),
            _metrics(zero),
            active: active,
          );
          expect(report['status'], 'not_measured');
        },
      );
    }
    test(
      '${nativeCryptoCopyFields[i]} unexpected inactive activity is unavailable',
      () {
        final after = [...zero]..[i] = 1;
        final report = nativeCryptoCopyMetricsDelta(
          _metrics(zero),
          _metrics(after),
          active: false,
        );
        expect(report['status'], 'not_measured');
        expect(
          report['observed_deltas'],
          containsPair(nativeCryptoCopyFields[i], 1),
        );
      },
    );
    if (i >= 3) {
      for (final side in [0, 1]) {
        test(
          '${nativeCryptoCopyFields[i]} missing side=$side fails active provider',
          () {
            final missing = [...zero]..[i] = null;
            final report = nativeCryptoCopyMetricsDelta(
              _metrics(side == 0 ? missing : zero),
              _metrics(side == 1 ? missing : zero),
              active: true,
            );
            expect(report['status'], 'not_measured');
          },
        );
        test(
          '${nativeCryptoCopyFields[i]} changing availability fails inactive provider',
          () {
            final missing = [...zero]..[i] = null;
            final report = nativeCryptoCopyMetricsDelta(
              _metrics(side == 0 ? missing : zero),
              _metrics(side == 1 ? missing : zero),
              active: false,
            );
            expect(report['status'], 'not_measured');
          },
        );
      }
    }
  }
  test('portable provider does not require an unused optional native ABI', () {
    final absent = _metrics([0, 0, 0, null, null, null, null]);
    final report = nativeCryptoCopyMetricsDelta(absent, absent, active: false);
    expect(report['status'], 'measured');
    expect(report['active'], false);
    expect(report['known_copy_bytes'], 0);
    expect(report['plaintext_staging_copy_bytes'], isNull);
  });
  test('observed inactive native ABI preserves exact zero deltas', () {
    final same = _metrics(List<int?>.filled(7, 91));
    final report = nativeCryptoCopyMetricsDelta(same, same, active: false);
    expect(report['status'], 'measured');
    expect(report['known_copy_bytes'], 0);
    expect([
      for (final field in nativeCryptoCopyFields) report[field],
    ], everyElement(0));
  });
}

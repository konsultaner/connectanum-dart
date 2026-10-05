@TestOn('vm')
library;

import 'package:connectanum_bench/src/e2ee_copy_metrics.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:test/test.dart';

void main() {
  test('cleartext workloads do not report crypto copies', () {
    final result = e2eeCopyMetricsFor(_scenario(null), _metrics(10, 20));
    expect((result['e2ee_copy_bytes'] as Map)['status'], 'not_applicable');
    expect(result, isNot(contains('known_e2ee_staging_copy_bytes')));
  });

  test('known staging copies cannot certify an encrypted pipeline', () {
    final result = e2eeCopyMetricsFor(_scenario('wamp'), _metrics(10, 20));
    expect(result['known_e2ee_staging_copy_bytes'], 37);
    expect((result['e2ee_copy_bytes'] as Map)['status'], 'not_measured');
    final breakdown = result['e2ee_copy_breakdown'] as Map;
    expect(breakdown['coverage'], 'known_staging_only');
    expect(breakdown['excludes'], contains('other isolate Dart bridges'));
  });

  test('missing native ABI leaves native measurements unavailable', () {
    final result = e2eeCopyMetricsFor(_scenario('wamp'), _metrics(null, null));
    expect(result['known_e2ee_staging_copy_bytes'], 7);
    final breakdown = result['e2ee_copy_breakdown'] as Map;
    for (final key in [
      'client_process_plaintext_staging_copy_bytes',
      'client_process_ciphertext_staging_copy_bytes',
    ]) {
      expect((breakdown[key] as Map)['status'], 'not_measured');
    }
  });

  test('deltas preserve unavailable counters across capability changes', () {
    final delta = _metrics(10, 20).deltaFrom(_metrics(null, 5));
    expect(delta.plaintextStagingCopyBytesTotal, isNull);
    expect(delta.ciphertextStagingCopyBytesTotal, 15);
    expect(delta.dartToNativeCopiedBytesTotal, 0);
    final reset = _metrics(10, 20).deltaFrom(_metrics(30, 40));
    expect(reset.plaintextStagingCopyBytesTotal, 10);
    expect(reset.ciphertextStagingCopyBytesTotal, 20);
  });
}

NativeE2eeCopyMetrics _metrics(int? plaintext, int? ciphertext) =>
    NativeE2eeCopyMetrics(
      dartToNativeCopiedBytesTotal: 3,
      nativeToDartCopiedBytesTotal: 4,
      plaintextStagingCopyBytesTotal: plaintext,
      ciphertextStagingCopyBytesTotal: ciphertext,
    );

WampScenario _scenario(String? scheme) => WampScenario(
  transport: WampTransport.rawsocket,
  serializer: WampSerializer.flatbuffers,
  mode: WampMode.rpc,
  uri: 'com.example.echo',
  iterations: 1,
  concurrency: 1,
  payloadBytes: 65536,
  pptScheme: scheme,
);

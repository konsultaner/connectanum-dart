// The VM benchmark reads runtime instrumentation rather than a client API.
// ignore: implementation_imports
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:connectanum_core/connectanum_core.dart';

import 'wamp_workload_runner.dart';

/// Native crypto copies are measured separately from transport/framing work.
/// A staging lower bound cannot certify complete E2EE pipeline coverage.
Map<String, Object?> e2eeCopyMetricsFor(
  WampScenario scenario,
  NativeE2eeCopyMetrics metrics,
) {
  if (scenario.pptScheme != ConnectanumE2eeProfile.scheme) {
    return {
      'e2ee_copy_bytes': {
        'status': 'not_applicable',
        'reason': 'workload does not use the E2EE profile',
      },
    };
  }
  Map<String, Object?> unavailable() => {
    'status': 'not_measured',
    'reason': 'native crypto copy metrics ABI v1 is unavailable',
  };
  return {
    'e2ee_copy_bytes': {
      'status': 'not_measured',
      'reason':
          'serializer/framing and Dart crypto copies are not fully measured',
    },
    'known_e2ee_staging_copy_bytes':
        metrics.dartToNativeCopiedBytesTotal +
        metrics.nativeToDartCopiedBytesTotal +
        (metrics.plaintextStagingCopyBytesTotal ?? 0) +
        (metrics.ciphertextStagingCopyBytesTotal ?? 0),
    'e2ee_copy_breakdown': {
      'client_worker_isolate_dart_to_native_copy_bytes':
          metrics.dartToNativeCopiedBytesTotal,
      'client_worker_isolate_native_to_dart_copy_bytes':
          metrics.nativeToDartCopiedBytesTotal,
      'client_process_plaintext_staging_copy_bytes':
          metrics.plaintextStagingCopyBytesTotal ?? unavailable(),
      'client_process_ciphertext_staging_copy_bytes':
          metrics.ciphertextStagingCopyBytesTotal ?? unavailable(),
      'coverage': 'known_staging_only',
      'excludes': [
        'nonce/tag construction',
        'cipher processing',
        'serializer/framing',
        'Dart crypto',
        'other isolate Dart bridges',
      ],
    },
  };
}

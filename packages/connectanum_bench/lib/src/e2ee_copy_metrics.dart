// The VM benchmark reads runtime instrumentation rather than a client API.
// ignore: implementation_imports
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:connectanum_core/connectanum_core.dart';
// The worker also collects explicit portable-provider copy boundaries.
// ignore: implementation_imports
import 'package:connectanum_core/src/message/e2ee_copy_metrics.dart';

import 'wamp_workload_runner.dart';

/// Crypto provider copies are measured separately from transport/framing work.
/// A staging lower bound cannot certify complete E2EE pipeline coverage.
Map<String, Object?> e2eeCopyMetricsFor(
  WampScenario scenario,
  NativeE2eeCopyMetrics metrics, {
  PortableE2eeCopyMetricsSnapshot? portableMetrics,
}) {
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
          'serializer/framing and crypto dependency copies are not fully measured',
    },
    'known_e2ee_staging_copy_bytes':
        metrics.dartToNativeCopiedBytesTotal +
        metrics.nativeToDartCopiedBytesTotal +
        (metrics.plaintextStagingCopyBytesTotal ?? 0) +
        (metrics.ciphertextStagingCopyBytesTotal ?? 0) +
        (portableMetrics?.knownOwnCopyBytes ?? 0),
    'e2ee_copy_breakdown': {
      'client_worker_isolate_dart_to_native_copy_bytes':
          metrics.dartToNativeCopiedBytesTotal,
      'client_worker_isolate_native_to_dart_copy_bytes':
          metrics.nativeToDartCopiedBytesTotal,
      'client_process_plaintext_staging_copy_bytes':
          metrics.plaintextStagingCopyBytesTotal ?? unavailable(),
      'client_process_ciphertext_staging_copy_bytes':
          metrics.ciphertextStagingCopyBytesTotal ?? unavailable(),
      'client_worker_isolate_portable_provider':
          portableMetrics?.toJson() ??
          <String, Object?>{
            'status': 'not_measured',
            'reason': 'portable provider copy window was not collected',
          },
      'coverage': 'known_staging_only',
      'excludes': [
        'nonce/tag construction',
        'cipher computation',
        'serializer/framing',
        'crypto dependency internals',
        'native provider ciphertext coercion',
        'other isolate portable provider copies',
        'other isolate Dart bridges',
      ],
    },
  };
}

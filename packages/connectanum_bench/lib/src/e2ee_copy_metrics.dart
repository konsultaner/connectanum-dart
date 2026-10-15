// The VM benchmark reads runtime instrumentation rather than a client API.
// ignore: implementation_imports
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:connectanum_core/connectanum_core.dart';
// The worker also collects explicit portable-provider copy boundaries.
// ignore: implementation_imports
import 'package:connectanum_core/src/message/e2ee_copy_metrics.dart';
// Observe explicit copies inside the providers' PPT serializers.
// ignore: implementation_imports
import 'package:connectanum_core/src/message/ppt_copy_metrics.dart';

import 'wamp_workload_runner.dart';

/// Provider and PPT copies are measured separately from outer WAMP framing.
/// A staging lower bound cannot certify complete E2EE pipeline coverage.
Map<String, Object?> e2eeCopyMetricsFor(
  WampScenario scenario,
  NativeE2eeCopyMetrics metrics, {
  PortableE2eeCopyMetricsSnapshot? portableMetrics,
  PptCopyMetricsSnapshot? pptMetrics,
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
          'Connectanum outer WAMP serializer/framing copies are not fully measured',
    },
    'known_e2ee_staging_copy_bytes':
        metrics.dartToNativeCopiedBytesTotal +
        metrics.nativeToDartCopiedBytesTotal +
        metrics.ciphertextCoercionCopyBytesTotal +
        (metrics.plaintextStagingCopyBytesTotal ?? 0) +
        (metrics.ciphertextStagingCopyBytesTotal ?? 0) +
        (metrics.nonceTagCopyBytesTotal ?? 0) +
        (metrics.plaintextFramingCopyBytesTotal ?? 0) +
        (portableMetrics?.knownOwnCopyBytes ?? 0) +
        (pptMetrics?.knownOwnCopyBytes ?? 0),
    'e2ee_copy_breakdown': {
      'client_worker_isolate_dart_to_native_copy_bytes':
          metrics.dartToNativeCopiedBytesTotal,
      'client_worker_isolate_native_to_dart_copy_bytes':
          metrics.nativeToDartCopiedBytesTotal,
      'client_worker_isolate_native_provider_ciphertext_coercion_copy_bytes':
          metrics.ciphertextCoercionCopyBytesTotal,
      'client_process_plaintext_staging_copy_bytes':
          metrics.plaintextStagingCopyBytesTotal ?? unavailable(),
      'client_process_plaintext_framing_copy_bytes':
          metrics.plaintextFramingCopyBytesTotal ??
          {
            'status': 'not_measured',
            'reason': 'native plaintext framing scalar is unavailable',
          },
      'client_process_nonce_tag_copy_bytes':
          metrics.nonceTagCopyBytesTotal ??
          {
            'status': 'not_measured',
            'reason': 'native nonce/tag copy scalar is unavailable',
          },
      'client_process_ciphertext_staging_copy_bytes':
          metrics.ciphertextStagingCopyBytesTotal ?? unavailable(),
      'client_worker_isolate_portable_provider':
          portableMetrics?.toJson() ??
          <String, Object?>{
            'status': 'not_measured',
            'reason': 'portable provider copy window was not collected',
          },
      'client_worker_isolate_ppt_serializer':
          pptMetrics?.toJson() ??
          <String, Object?>{
            'status': 'not_measured',
            'reason': 'PPT serializer copy window was not collected',
          },
      'coverage': 'known_staging_only',
      'excludes': [
        'cipher computation',
        'outer WAMP serializer/framing',
        'serializer dependency internals',
        'crypto dependency internals',
        'other isolate native provider ciphertext coercion',
        'other isolate portable provider copies',
        'other isolate PPT serializer copies',
        'other isolate Dart bridges',
      ],
    },
  };
}

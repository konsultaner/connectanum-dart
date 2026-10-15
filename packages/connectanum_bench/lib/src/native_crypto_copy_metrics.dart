// Benchmark-only cumulative observations; the provider API remains unchanged.
// ignore: implementation_imports
import 'package:connectanum_client/src/transport/native/runtime.dart';

const nativeCryptoCopyFields = [
  'dart_to_native_copy_bytes',
  'native_to_dart_copy_bytes',
  'ciphertext_coercion_copy_bytes',
  'plaintext_staging_copy_bytes',
  'ciphertext_staging_copy_bytes',
  'nonce_tag_copy_bytes',
  'plaintext_framing_copy_bytes',
];

Map<String, int?> _fields(NativeE2eeCopyMetrics value) => {
  'dart_to_native_copy_bytes': value.dartToNativeCopiedBytesTotal,
  'native_to_dart_copy_bytes': value.nativeToDartCopiedBytesTotal,
  'ciphertext_coercion_copy_bytes': value.ciphertextCoercionCopyBytesTotal,
  'plaintext_staging_copy_bytes': value.plaintextStagingCopyBytesTotal,
  'ciphertext_staging_copy_bytes': value.ciphertextStagingCopyBytesTotal,
  'nonce_tag_copy_bytes': value.nonceTagCopyBytesTotal,
  'plaintext_framing_copy_bytes': value.plaintextFramingCopyBytesTotal,
};

/// An unused native provider needs no optional ABI. Observed unexpected activity
/// still fails closed, and counter resets cannot masquerade as small deltas.
Map<String, Object?> nativeCryptoCopyMetricsDelta(
  NativeE2eeCopyMetrics before,
  NativeE2eeCopyMetrics after, {
  required bool active,
}) {
  final earlier = _fields(before);
  final later = _fields(after);
  final delta = <String, int?>{};
  for (final field in nativeCryptoCopyFields) {
    final start = earlier[field];
    final end = later[field];
    if (!active && start == null && end == null) {
      delta[field] = null;
      continue;
    }
    if (start == null || end == null || start < 0 || end < start) {
      return {
        'status': 'not_measured',
        'active': active,
        'reason': 'native crypto counter $field is missing, invalid or rewound',
      };
    }
    delta[field] = end - start;
  }
  if (!active && delta.values.any((value) => value != null && value != 0)) {
    return {
      'status': 'not_measured',
      'active': false,
      'reason': 'an inactive native provider performed copies',
      'observed_deltas': delta,
    };
  }
  return {
    'status': 'measured',
    'active': active,
    ...delta,
    'known_copy_bytes': delta.values.fold<int>(
      0,
      (sum, value) => sum + (value ?? 0),
    ),
  };
}

/// Isolate-local copy counters at explicit portable E2EE provider boundaries.
/// Collection is disabled except during a benchmark window. Cipher output
/// computation, nonce/tag construction, serializer work and dependency-internal
/// copies are outside this measurement; zero here is not a zero-copy claim.
class PortableE2eeCopyMetrics {
  PortableE2eeCopyMetrics._();

  static bool _recording = false;
  static int _plaintextWrappingCopyBytes = 0;
  static int _ciphertextWrappingCopyBytes = 0;
  static int _ciphertextAssemblyCopyBytes = 0;
  static int _ciphertextCoercionCopyBytes = 0;

  static void beginWindow() {
    if (_recording) {
      throw StateError('A portable E2EE copy-metrics window is already open.');
    }
    _plaintextWrappingCopyBytes = 0;
    _ciphertextWrappingCopyBytes = 0;
    _ciphertextAssemblyCopyBytes = 0;
    _ciphertextCoercionCopyBytes = 0;
    _recording = true;
  }

  /// Stop collection and return the current immutable snapshot. Repeated calls
  /// return the same counts until the next window begins.
  static PortableE2eeCopyMetricsSnapshot endWindow() {
    _recording = false;
    return PortableE2eeCopyMetricsSnapshot(
      plaintextWrappingCopyBytes: _plaintextWrappingCopyBytes,
      ciphertextWrappingCopyBytes: _ciphertextWrappingCopyBytes,
      ciphertextAssemblyCopyBytes: _ciphertextAssemblyCopyBytes,
      ciphertextCoercionCopyBytes: _ciphertextCoercionCopyBytes,
    );
  }

  static void recordPlaintextWrappingCopy(int bytes) {
    if (_recording) _plaintextWrappingCopyBytes += bytes;
  }

  static void recordCiphertextWrappingCopy(int bytes) {
    if (_recording) _ciphertextWrappingCopyBytes += bytes;
  }

  static void recordCiphertextAssemblyCopy(int bytes) {
    if (_recording) _ciphertextAssemblyCopyBytes += bytes;
  }

  static void recordCiphertextCoercionCopy(int bytes) {
    if (_recording) _ciphertextCoercionCopyBytes += bytes;
  }
}

class PortableE2eeCopyMetricsSnapshot {
  const PortableE2eeCopyMetricsSnapshot({
    required this.plaintextWrappingCopyBytes,
    required this.ciphertextWrappingCopyBytes,
    required this.ciphertextAssemblyCopyBytes,
    required this.ciphertextCoercionCopyBytes,
  });

  final int plaintextWrappingCopyBytes;
  final int ciphertextWrappingCopyBytes;
  final int ciphertextAssemblyCopyBytes;
  final int ciphertextCoercionCopyBytes;

  int get knownOwnCopyBytes =>
      plaintextWrappingCopyBytes +
      ciphertextWrappingCopyBytes +
      ciphertextAssemblyCopyBytes +
      ciphertextCoercionCopyBytes;

  Map<String, int> toJson() => {
    'plaintext_wrapping_copy_bytes': plaintextWrappingCopyBytes,
    'ciphertext_wrapping_copy_bytes': ciphertextWrappingCopyBytes,
    'ciphertext_assembly_copy_bytes': ciphertextAssemblyCopyBytes,
    'ciphertext_coercion_copy_bytes': ciphertextCoercionCopyBytes,
  };
}

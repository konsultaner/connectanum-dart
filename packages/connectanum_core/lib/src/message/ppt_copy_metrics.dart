/// Explicit byte-buffer copies performed by Connectanum's PPT serializers.
/// The synchronous scope excludes ordinary outer WAMP encoding. Cipher work
/// and serializer-dependency internals are separate from these owned copies.
class PptCopyMetrics {
  PptCopyMetrics._();

  static bool _recording = false;
  static int _scopeDepth = 0;
  static int _encodeWrapping = 0;
  static int _decodedBinary = 0;
  static int _coalescing = 0;
  static int _metadataSetup = 0;

  static void beginWindow() {
    if (_recording) {
      throw StateError('A PPT copy-metrics window is already open.');
    }
    _encodeWrapping = 0;
    _decodedBinary = 0;
    _coalescing = 0;
    _metadataSetup = 0;
    _recording = true;
  }

  static PptCopyMetricsSnapshot endWindow() {
    _recording = false;
    return PptCopyMetricsSnapshot(
      encodeWrappingCopyBytes: _encodeWrapping,
      decodedBinaryCopyBytes: _decodedBinary,
      coalescingCopyBytes: _coalescing,
      metadataSetupCopyBytes: _metadataSetup,
    );
  }

  /// Called only around synchronous serializer operations in E2EE providers.
  static T measure<T>(T Function() operation) {
    if (!_recording) return operation();
    _scopeDepth++;
    try {
      return operation();
    } finally {
      _scopeDepth--;
    }
  }

  static void recordEncodeWrappingCopy(int bytes) {
    if (_recording && _scopeDepth > 0) _encodeWrapping += bytes;
  }

  static void recordDecodedBinaryCopy(int bytes) {
    if (_recording && _scopeDepth > 0) _decodedBinary += bytes;
  }

  static void recordMetadataSetupCopy(int bytes) {
    if (_recording && _scopeDepth > 0) _metadataSetup += bytes;
  }

  static void recordCoalescingCopy(int bytes) {
    if (_recording && _scopeDepth > 0) _coalescing += bytes;
  }
}

class PptCopyMetricsSnapshot {
  const PptCopyMetricsSnapshot({
    required this.encodeWrappingCopyBytes,
    required this.decodedBinaryCopyBytes,
    required this.coalescingCopyBytes,
    this.metadataSetupCopyBytes = 0,
  });

  final int encodeWrappingCopyBytes;
  final int decodedBinaryCopyBytes;
  final int coalescingCopyBytes;
  final int metadataSetupCopyBytes;

  int get knownOwnCopyBytes =>
      encodeWrappingCopyBytes +
      decodedBinaryCopyBytes +
      coalescingCopyBytes +
      metadataSetupCopyBytes;

  Map<String, int> toJson() => {
    'encode_wrapping_copy_bytes': encodeWrappingCopyBytes,
    'decoded_binary_copy_bytes': decodedBinaryCopyBytes,
    'coalescing_copy_bytes': coalescingCopyBytes,
    'metadata_setup_copy_bytes': metadataSetupCopyBytes,
  };
}

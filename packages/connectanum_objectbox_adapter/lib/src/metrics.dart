/// Reasons a write could not borrow the original immutable native range.
enum ObjectBoxCopyReason {
  unavailableNativeLease,
  padding,
  idAssignment,
}

/// Adapter-owned byte copies. ObjectBox, SDK and storage-engine internals are
/// outside these counters and are not claimed to be zero-copy.
final class ObjectBoxCopyMetrics {
  const ObjectBoxCopyMetrics({
    required this.stagingCopyBytes,
    required this.snapshotCopyBytes,
    required this.borrowedInputBytes,
    required this.paddingBytes,
    required this.successfulWrites,
    required this.failedWrites,
  });

  final int stagingCopyBytes;
  final int snapshotCopyBytes;
  final int borrowedInputBytes;
  final int paddingBytes;
  final int successfulWrites;
  final int failedWrites;

  int get knownCopyBytes => stagingCopyBytes + snapshotCopyBytes;
}

/// Result of a successful synchronous C API put. A new ID may differ from the immutable
/// input's zero ID; the caller's bytes are never patched. An enclosing native
/// transaction still controls its final commit or rollback.
final class ObjectBoxPutResult {
  ObjectBoxPutResult({
    required this.id,
    required this.copiedBytes,
    required Iterable<ObjectBoxCopyReason> copyReasons,
  }) : copyReasons = List.unmodifiable(copyReasons);

  final int id;
  final int copiedBytes;
  final List<ObjectBoxCopyReason> copyReasons;
  bool get borrowed => copyReasons.isEmpty;
}

/// A native ObjectBox operation failed. [code] is the original C error code.
final class ObjectBoxAdapterException implements Exception {
  const ObjectBoxAdapterException(this.operation, this.code, this.message);
  final String operation;
  final int code;
  final String message;

  @override
  String toString() => 'ObjectBoxAdapterException($operation, $code): $message';
}

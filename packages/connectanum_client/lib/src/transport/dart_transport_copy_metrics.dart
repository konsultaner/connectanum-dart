/// Isolate-local counters for copy operations performed directly by the Dart
/// transports.
///
/// The benchmark worker enables collection only for one workload window. These
/// values cover Connectanum-owned operations and do not infer copy behavior
/// inside `dart:io` or the platform socket/TLS implementation.
class DartTransportCopyMetrics {
  DartTransportCopyMetrics._();

  static bool _recording = false;
  static int _rawSocketFramePayloadCopiedBytes = 0;
  static int _rawSocketFrameHeaderCopiedBytes = 0;
  static int _rawSocketInputCopiedBytes = 0;
  static int _rawSocketFragmentCoalesceCopiedBytes = 0;
  static int _rawSocketPreHandshakeQueueCopiedBytes = 0;
  static int _webSocketFragmentCoalesceCopiedBytes = 0;

  static void beginWindow() {
    if (_recording) {
      throw StateError('A Dart transport copy-metrics window is already open.');
    }
    _rawSocketFramePayloadCopiedBytes = 0;
    _rawSocketFrameHeaderCopiedBytes = 0;
    _rawSocketInputCopiedBytes = 0;
    _rawSocketFragmentCoalesceCopiedBytes = 0;
    _rawSocketPreHandshakeQueueCopiedBytes = 0;
    _webSocketFragmentCoalesceCopiedBytes = 0;
    _recording = true;
  }

  static DartTransportCopyMetricsSnapshot endWindow() {
    _recording = false;
    return DartTransportCopyMetricsSnapshot(
      rawSocketFramePayloadCopiedBytes: _rawSocketFramePayloadCopiedBytes,
      rawSocketFrameHeaderCopiedBytes: _rawSocketFrameHeaderCopiedBytes,
      rawSocketInputCopiedBytes: _rawSocketInputCopiedBytes,
      rawSocketFragmentCoalesceCopiedBytes:
          _rawSocketFragmentCoalesceCopiedBytes,
      rawSocketPreHandshakeQueueCopiedBytes:
          _rawSocketPreHandshakeQueueCopiedBytes,
      webSocketFragmentCoalesceCopiedBytes:
          _webSocketFragmentCoalesceCopiedBytes,
    );
  }

  static void recordRawSocketFramePayloadCopy(int bytes) {
    if (_recording) _rawSocketFramePayloadCopiedBytes += bytes;
  }

  static void recordRawSocketFrameHeaderCopy(int bytes) {
    if (_recording) _rawSocketFrameHeaderCopiedBytes += bytes;
  }

  static void recordRawSocketInputCopy(int bytes) {
    if (_recording) _rawSocketInputCopiedBytes += bytes;
  }

  static void recordRawSocketFragmentCoalesceCopy(int bytes) {
    if (_recording) _rawSocketFragmentCoalesceCopiedBytes += bytes;
  }

  static void recordRawSocketPreHandshakeQueueCopy(int bytes) {
    if (_recording) _rawSocketPreHandshakeQueueCopiedBytes += bytes;
  }

  static void recordWebSocketFragmentCoalesceCopy(int bytes) {
    if (_recording) _webSocketFragmentCoalesceCopiedBytes += bytes;
  }
}

class DartTransportCopyMetricsSnapshot {
  const DartTransportCopyMetricsSnapshot({
    required this.rawSocketFramePayloadCopiedBytes,
    this.rawSocketFrameHeaderCopiedBytes = 0,
    this.rawSocketInputCopiedBytes = 0,
    required this.rawSocketFragmentCoalesceCopiedBytes,
    required this.rawSocketPreHandshakeQueueCopiedBytes,
    required this.webSocketFragmentCoalesceCopiedBytes,
  });

  final int rawSocketFramePayloadCopiedBytes;
  final int rawSocketFrameHeaderCopiedBytes;
  final int rawSocketInputCopiedBytes;
  final int rawSocketFragmentCoalesceCopiedBytes;
  final int rawSocketPreHandshakeQueueCopiedBytes;
  final int webSocketFragmentCoalesceCopiedBytes;

  int get knownOwnCopyBytes =>
      rawSocketFramePayloadCopiedBytes +
      rawSocketFrameHeaderCopiedBytes +
      rawSocketInputCopiedBytes +
      rawSocketFragmentCoalesceCopiedBytes +
      rawSocketPreHandshakeQueueCopiedBytes +
      webSocketFragmentCoalesceCopiedBytes;

  Map<String, int> toJson() => {
    'rawsocket_frame_payload_copy_bytes': rawSocketFramePayloadCopiedBytes,
    'rawsocket_frame_header_copy_bytes': rawSocketFrameHeaderCopiedBytes,
    'rawsocket_input_copy_bytes': rawSocketInputCopiedBytes,
    'rawsocket_fragment_coalesce_copy_bytes':
        rawSocketFragmentCoalesceCopiedBytes,
    'rawsocket_pre_handshake_queue_copy_bytes':
        rawSocketPreHandshakeQueueCopiedBytes,
    'websocket_fragment_coalesce_copy_bytes':
        webSocketFragmentCoalesceCopiedBytes,
  };
}

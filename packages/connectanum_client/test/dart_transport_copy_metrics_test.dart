import 'package:connectanum_client/src/transport/dart_transport_copy_metrics.dart';
import 'package:test/test.dart';

void main() {
  group('DartTransportCopyMetrics', () {
    test('collects Connectanum-owned copies and resets each window', () {
      DartTransportCopyMetrics.beginWindow();
      DartTransportCopyMetrics.recordRawSocketFramePayloadCopy(7);
      DartTransportCopyMetrics.recordRawSocketFragmentCoalesceCopy(11);
      DartTransportCopyMetrics.recordRawSocketPreHandshakeQueueCopy(13);
      DartTransportCopyMetrics.recordWebSocketFragmentCoalesceCopy(17);

      final first = DartTransportCopyMetrics.endWindow();

      expect(first.knownOwnCopyBytes, 48);
      expect(first.toJson(), {
        'rawsocket_frame_payload_copy_bytes': 7,
        'rawsocket_fragment_coalesce_copy_bytes': 11,
        'rawsocket_pre_handshake_queue_copy_bytes': 13,
        'websocket_fragment_coalesce_copy_bytes': 17,
      });

      DartTransportCopyMetrics.recordRawSocketFramePayloadCopy(19);
      DartTransportCopyMetrics.beginWindow();
      final second = DartTransportCopyMetrics.endWindow();

      expect(second.knownOwnCopyBytes, 0);
    });

    test('rejects overlapping measurement windows', () {
      DartTransportCopyMetrics.beginWindow();
      expect(DartTransportCopyMetrics.beginWindow, throwsStateError);
      DartTransportCopyMetrics.endWindow();
    });
  });
}

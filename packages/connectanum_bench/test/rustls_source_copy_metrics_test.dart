import 'package:connectanum_client/src/transport/native/runtime.dart' as client;
import 'package:connectanum_router/src/native/runtime.dart' as router;
import 'package:test/test.dart';

void main() {
  for (final name in ['client', 'router']) {
    for (final values in [
      (before: 11, after: 17, expected: 6),
      (before: 11, after: 11, expected: 0),
      (before: 11, after: 2, expected: 2),
      (before: null, after: 17, expected: null),
      (before: 11, after: null, expected: null),
      (before: null, after: null, expected: null),
    ]) {
      test('$name partial source counters $values', () {
        if (name == 'client') {
          final before = _client(values.before);
          final after = _client(values.after);
          final delta = after.deltaFrom(before);
          expect(
            delta.rustlsOutboundChunkCopyBytesTotal,
            values.expected == null ? null : values.expected! * 1,
          );
          expect(
            delta.rustlsQueueReadCopyBytesTotal,
            values.expected == null ? null : values.expected! * 2,
          );
          expect(
            delta.rustlsDeframerAppendCopyBytesTotal,
            values.expected == null ? null : values.expected! * 3,
          );
          expect(
            delta.rustlsDeframerMoveCopyBytesTotal,
            values.expected == null ? null : values.expected! * 4,
          );
          expect(
            delta.rustlsRecordBufferCopyBytesTotal,
            values.expected == null ? null : values.expected! * 5,
          );
          expect(
            delta.rustlsRecordAppendCopyBytesTotal,
            values.expected == null ? null : values.expected! * 6,
          );
        } else {
          final before = _router(values.before);
          final after = _router(values.after);
          final delta = after.deltaFrom(before);
          expect(
            delta.rustlsOutboundChunkCopyBytesTotal,
            values.expected == null ? null : values.expected! * 1,
          );
          expect(
            delta.rustlsQueueReadCopyBytesTotal,
            values.expected == null ? null : values.expected! * 2,
          );
          expect(
            delta.rustlsDeframerAppendCopyBytesTotal,
            values.expected == null ? null : values.expected! * 3,
          );
          expect(
            delta.rustlsDeframerMoveCopyBytesTotal,
            values.expected == null ? null : values.expected! * 4,
          );
          expect(
            delta.rustlsRecordBufferCopyBytesTotal,
            values.expected == null ? null : values.expected! * 5,
          );
          expect(
            delta.rustlsRecordAppendCopyBytesTotal,
            values.expected == null ? null : values.expected! * 6,
          );
        }
      });
    }
  }
}

client.NativeTransportCopyMetrics _client(int? value) =>
    client.NativeTransportCopyMetrics(
      dartToNativeCopiedBytesTotal: 0,
      websocketMaskCopyBytesTotal: 0,
      websocketCoalesceCopyBytesTotal: 0,
      tlsPlaintextAcceptedBytesTotal: 0,
      rustlsOutboundChunkCopyBytesTotal: value == null ? null : value * 1,
      rustlsQueueReadCopyBytesTotal: value == null ? null : value * 2,
      rustlsDeframerAppendCopyBytesTotal: value == null ? null : value * 3,
      rustlsDeframerMoveCopyBytesTotal: value == null ? null : value * 4,
      rustlsRecordBufferCopyBytesTotal: value == null ? null : value * 5,
      rustlsRecordAppendCopyBytesTotal: value == null ? null : value * 6,
    );

router.NativeRouterTransportCopyMetrics _router(int? value) =>
    router.NativeRouterTransportCopyMetrics(
      dartToNativeCopiedBytesTotal: 0,
      websocketMaskCopyBytesTotal: 0,
      websocketCoalesceCopyBytesTotal: 0,
      tlsPlaintextAcceptedBytesTotal: 0,
      rustlsOutboundChunkCopyBytesTotal: value == null ? null : value * 1,
      rustlsQueueReadCopyBytesTotal: value == null ? null : value * 2,
      rustlsDeframerAppendCopyBytesTotal: value == null ? null : value * 3,
      rustlsDeframerMoveCopyBytesTotal: value == null ? null : value * 4,
      rustlsRecordBufferCopyBytesTotal: value == null ? null : value * 5,
      rustlsRecordAppendCopyBytesTotal: value == null ? null : value * 6,
    );

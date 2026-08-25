import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/call_media.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test(
    'description payloads roundtrip only under the matching signal kind',
    () {
      final payload = CallDescriptionSignalPayload(
        CallSessionDescription(type: 'offer', sdp: 'v=0\r\ns=test\r\n'),
      );

      final encoded = CallSignalPayloadCodec.encode(
        CallSignalKind.offer,
        payload,
      );
      final decoded = CallSignalPayloadCodec.decode(
        CallSignalKind.offer,
        encoded,
      ) as CallDescriptionSignalPayload;

      expect(decoded.description.type, 'offer');
      expect(decoded.description.sdp, 'v=0\r\ns=test\r\n');
      expect(
        () => CallSignalPayloadCodec.encode(CallSignalKind.answer, payload),
        throwsFormatException,
      );
      expect(
        () => CallSignalPayloadCodec.decode(CallSignalKind.answer, encoded),
        throwsFormatException,
      );
    },
  );

  test('ICE payload preserves optional routing metadata', () {
    final encoded = CallSignalPayloadCodec.encode(
      CallSignalKind.iceCandidate,
      CallCandidateSignalPayload(
        CallIceCandidate(
          candidate: 'candidate:1 1 UDP 1 127.0.0.1 9999 typ host',
          sdpMid: 'audio',
          sdpMLineIndex: 2,
        ),
      ),
    );

    final decoded = CallSignalPayloadCodec.decode(
      CallSignalKind.iceCandidate,
      encoded,
    ) as CallCandidateSignalPayload;
    expect(decoded.candidate.candidate, contains('typ host'));
    expect(decoded.candidate.sdpMid, 'audio');
    expect(decoded.candidate.sdpMLineIndex, 2);
  });

  test(
    'control payload cannot be relabeled or decoded from malformed JSON',
    () {
      final encoded = CallSignalPayloadCodec.encode(
        CallSignalKind.hangup,
        const CallControlSignalPayload(),
      );

      expect(
        () => CallSignalPayloadCodec.decode(CallSignalKind.decline, encoded),
        throwsFormatException,
      );
      expect(
        () => CallSignalPayloadCodec.decode(
          CallSignalKind.hangup,
          Uint8List.fromList([0, 1, 2]),
        ),
        throwsA(anything),
      );
    },
  );

  test('models reject oversized or invalid media data', () {
    expect(
      () => CallSessionDescription(type: 'rollback', sdp: 'v=0'),
      throwsFormatException,
    );
    expect(() => CallIceCandidate(candidate: ''), throwsFormatException);
    expect(
      () => CallIceCandidate(candidate: 'candidate', sdpMLineIndex: -1),
      throwsFormatException,
    );
  });
}

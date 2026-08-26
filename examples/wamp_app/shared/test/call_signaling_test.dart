import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('encrypted signals use binary WAMP payloads and defensive copies', () {
    final payload = Uint8List(WampAppCallLimits.sealedBoxOverheadBytes + 1)
      ..fillRange(0, WampAppCallLimits.sealedBoxOverheadBytes + 1, 7);
    final signal = _signal(payload: payload);
    payload.fillRange(0, payload.length, 99);

    final wire = signal.toWampKeywords();
    expect(wire['sealed_payload'], isA<Uint8List>());
    final restored = EncryptedCallSignal.fromWampKeywords(wire);
    expect(restored.sealedPayload, everyElement(7));
    (wire['sealed_payload'] as Uint8List).fillRange(0, payload.length, 42);
    expect(restored.sealedPayload, everyElement(7));

    final stored = EncryptedCallSignal.fromJson(signal.toJson());
    expect(stored.sealedPayload, everyElement(7));
    expect(stored.signaturePayload(), signal.signaturePayload());
  });

  test('call start requires complete unique per-device offers', () {
    final first = _signal(recipientDeviceSeed: 4);
    final second = _signal(signalSeed: 8, recipientDeviceSeed: 5);
    final request = CallStartRequest(
      media: CallMediaKind.video,
      calleeUsername: 'Bob',
      offers: [first, second],
    );

    final restored = CallStartRequest.fromWampKeywords(
      request.toWampKeywords(),
    );
    expect(restored.calleeUsername, 'bob');
    expect(restored.media, CallMediaKind.video);
    expect(restored.offers, hasLength(2));
    expect(
      () => CallStartRequest(
        media: CallMediaKind.voice,
        calleeUsername: 'bob',
        offers: [first, first],
      ),
      throwsFormatException,
    );
    expect(
      () => CallStartRequest(
        media: CallMediaKind.voice,
        calleeUsername: 'carol',
        offers: [first],
      ),
      throwsFormatException,
    );
  });

  test('call records enforce valid state transitions metadata', () {
    final created = DateTime.utc(2026, 8, 25, 10);
    final ringing = CallRecord(
      callId: _token(16, 1),
      callerUsername: 'alice',
      callerDeviceId: _token(32, 2),
      calleeUsername: 'bob',
      media: CallMediaKind.voice,
      state: CallState.ringing,
      createdAt: created,
    );
    expect(CallRecord.fromJson(ringing.toJson()).state, CallState.ringing);

    final active = CallRecord(
      callId: ringing.callId,
      callerUsername: 'alice',
      callerDeviceId: ringing.callerDeviceId,
      calleeUsername: 'bob',
      media: CallMediaKind.voice,
      state: CallState.active,
      acceptedDeviceId: _token(32, 3),
      createdAt: created,
      answeredAt: created.add(const Duration(seconds: 2)),
    );
    expect(
      CallRecord.fromWampKeywords(active.toWampKeywords()).acceptedDeviceId,
      active.acceptedDeviceId,
    );
    expect(
      () => CallRecord(
        callId: ringing.callId,
        callerUsername: 'alice',
        callerDeviceId: ringing.callerDeviceId,
        calleeUsername: 'bob',
        media: CallMediaKind.voice,
        state: CallState.active,
        createdAt: created,
      ),
      throwsFormatException,
    );
  });

  test('call batches preserve cursors and filterable encrypted updates', () {
    final signal = _signal();
    final record = CallRecord(
      callId: signal.callId,
      callerUsername: signal.senderUsername,
      callerDeviceId: signal.senderDeviceId,
      calleeUsername: signal.recipientUsername,
      media: CallMediaKind.video,
      state: CallState.ringing,
      createdAt: signal.createdAt,
    );
    final batch = CallBatch(
      nextCursor: 4,
      updates: [
        CallUpdate(cursor: 4, call: record, signals: [signal]),
      ],
    );

    final restored = CallBatch.fromWampKeywords(batch.toWampKeywords());
    expect(restored.nextCursor, 4);
    expect(restored.updates.single.call.media, CallMediaKind.video);
    expect(restored.updates.single.signals.single.signalId, signal.signalId);
  });

  test('ICE configuration accepts STUN and expiring TURN credentials', () {
    final configuration = CallConfiguration(
      iceServers: [
        CallIceServer(urls: const ['stun:stun.example.net:3478']),
        CallIceServer(
          urls: const ['turns:turn.example.net:5349?transport=tcp'],
          username: '1700000000:alice',
          credential: 'temporary-secret',
        ),
      ],
      expiresAt: DateTime.utc(2026, 8, 25, 11),
    );

    final restored = CallConfiguration.fromWampKeywords(
      configuration.toWampKeywords(),
    );
    expect(restored.iceServers, hasLength(2));
    expect(restored.iceServers.last.credential, 'temporary-secret');
    expect(
      () => CallIceServer(urls: const ['https://example.net/ice']),
      throwsFormatException,
    );
  });

  test('oversized or cross-account signal envelopes fail closed', () {
    expect(
      () => _signal(
        payload: Uint8List(WampAppCallLimits.maximumSignalCiphertextBytes + 1),
      ),
      throwsFormatException,
    );
    expect(() => _signal(recipientUsername: 'alice'), throwsFormatException);
  });
}

EncryptedCallSignal _signal({
  int signalSeed = 3,
  int recipientDeviceSeed = 4,
  String recipientUsername = 'bob',
  Uint8List? payload,
}) => EncryptedCallSignal(
  callId: _token(16, 1),
  signalId: _token(16, signalSeed),
  kind: CallSignalKind.offer,
  senderUsername: 'Alice',
  senderDeviceId: _token(32, 2),
  recipientUsername: recipientUsername,
  recipientDeviceId: _token(32, recipientDeviceSeed),
  sealedPayload:
      payload ?? Uint8List(WampAppCallLimits.sealedBoxOverheadBytes + 1),
  signature: _token(64, 6),
  createdAt: DateTime.utc(2026, 8, 25, 10),
);

String _token(int bytes, int seed) => base64Url
    .encode(List<int>.generate(bytes, (index) => (index + seed) % 256))
    .replaceAll('=', '');

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test(
    'signal ciphertext allows 256 KiB plus sealed-box overhead, not more',
    () {
      for (final size in [49, 262192]) {
        final signal = _signal(payload: Uint8List(size));
        final decoded = EncryptedCallSignal.fromWampKeywords(
          signal.toWampKeywords(),
        );
        expect(decoded.sealedPayload, hasLength(size));
      }
      for (final size in [48, 262193]) {
        expect(() => _signal(payload: Uint8List(size)), throwsFormatException);
        final wire = _signal().toWampKeywords()
          ..['sealed_payload'] = Uint8List(size);
        expect(
          () => EncryptedCallSignal.fromWampKeywords(wire),
          throwsFormatException,
        );
      }
    },
  );

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
    expect(restored.callId, _token(16, 1));
    expect(restored.callerUsername, 'alice');
    expect(restored.callerDeviceId, _token(32, 2));
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

  test('call updates preserve persisted JSON and completed state metadata', () {
    final signal = _signal();
    final ended = CallRecord(
      callId: signal.callId,
      callerUsername: 'alice',
      callerDeviceId: signal.senderDeviceId,
      calleeUsername: 'bob',
      media: CallMediaKind.video,
      state: CallState.ended,
      acceptedDeviceId: signal.recipientDeviceId,
      createdAt: signal.createdAt,
      answeredAt: signal.createdAt.add(const Duration(seconds: 1)),
      endedAt: signal.createdAt.add(const Duration(seconds: 3)),
    );
    final update = CallUpdate(cursor: 7, call: ended, signals: [signal]);
    final restored = CallUpdate.fromJson(update.toJson());
    expect(restored.cursor, 7);
    expect(restored.call.isTerminal, isTrue);
    expect(restored.call.endedAt, DateTime.utc(2026, 8, 25, 10, 0, 3));
    expect(restored.call.answeredAt, DateTime.utc(2026, 8, 25, 10, 0, 1));
    expect(restored.signals.single.toWampKeywords(), signal.toWampKeywords());
    expect(restored.toWampKeywords(), update.toWampKeywords());
    expect(() => restored.signals.clear(), throwsUnsupportedError);
    expect(
      () => CallRecord.fromJson({
        ...ended.toJson(),
        'ended_at': '2026-08-25T09:00:00Z',
      }),
      throwsFormatException,
    );
    expect(() => CallRecord.fromWampKeywords(null), throwsFormatException);
    for (final factory in [CallUpdate.fromJson, CallUpdate.fromWampKeywords]) {
      for (final value in <Map<String, dynamic>?>[
        null,
        {...update.toJson(), 'signals': {}},
        {
          ...update.toJson(),
          'signals': [42],
        },
        {...update.toJson(), 'call': 42},
      ]) {
        expect(() => factory(value), throwsFormatException);
      }
    }
  });

  test('call wakeups and batches reject malformed cursors and envelopes', () {
    expect(CallWakeup.fromWampKeywords({'cursor': 1}).toWampKeywords(), {
      'cursor': 1,
    });
    for (final cursor in <Object?>[null, 0, -1, '1']) {
      expect(
        () => CallWakeup.fromWampKeywords({'cursor': cursor}),
        throwsFormatException,
      );
    }
    expect(() => CallWakeup.fromWampKeywords(null), throwsFormatException);
    for (final value in <Map<String, dynamic>?>[
      null,
      {'next_cursor': 1, 'updates': {}},
      {
        'next_cursor': 1,
        'updates': [42],
      },
      {'next_cursor': -1, 'updates': []},
    ]) {
      expect(() => CallBatch.fromWampKeywords(value), throwsFormatException);
    }
    expect(
      CallBatch.fromWampKeywords({
        'next_cursor': 0,
        'updates': [],
      }).toWampKeywords(),
      {'next_cursor': 0, 'updates': []},
    );
  });

  test('signal wire parsing rejects malformed types and encodings', () {
    final wire = _signal().toWampKeywords();
    for (final invalid in <Map<String, dynamic>>[
      {'kind': 42},
      {'kind': 'unknown'},
      {'sender_username': '!'},
      {'signal_id': 'x'},
      {'signal_id': 'a' * 25},
      {'signature': ''},
      {'signature': 'a'},
      {'signature': _token(63, 6)},
      {'sealed_payload': 'not binary'},
      {'sender_device_id': 42},
      {'created_at': 'invalid'},
    ]) {
      expect(
        () => EncryptedCallSignal.fromWampKeywords({...wire, ...invalid}),
        throwsFormatException,
      );
    }
    final bytes = List<int>.of(wire['sealed_payload'] as Uint8List);
    final restored = EncryptedCallSignal.fromWampKeywords({
      ...wire,
      'sealed_payload': bytes,
    });
    bytes[0] = 255;
    expect(restored.sealedPayload, everyElement(0));
    expect(
      () => EncryptedCallSignal.fromJson({
        ..._signal().toJson(),
        'sealed_payload': '!',
      }),
      throwsFormatException,
    );
  });

  test('ICE input types, credential pairing and expiry fail closed', () {
    for (final invalid in <Map<String, dynamic>>[
      {'urls': 'stun:example.test'},
      {
        'urls': [42],
      },
      {'urls': []},
      {'urls': List.filled(9, 'stun:example.test')},
      {
        'urls': ['stun:${'x' * 2048}'],
      },
      {
        'urls': ['turn:example.test'],
        'username': 'alice',
      },
      {
        'urls': ['turn:example.test'],
        'credential': 'secret',
      },
      {
        'urls': ['turn:example.test'],
        'username': '',
        'credential': 'secret',
      },
      {
        'urls': ['turn:example.test'],
        'username': 'alice',
        'credential': '',
      },
      {
        'urls': ['turn:example.test'],
        'username': 42,
        'credential': 'secret',
      },
    ]) {
      expect(
        () => CallIceServer.fromWampKeywords(invalid),
        throwsFormatException,
      );
    }
    final urls = List.filled(8, 'stun:example.test', growable: true);
    final server = CallIceServer(urls: urls);
    urls.clear();
    expect(server.urls, hasLength(8));
    expect(() => server.urls.clear(), throwsUnsupportedError);
    for (final value in <Map<String, dynamic>?>[
      null,
      {'ice_servers': {}, 'expires_at': '2026-09-15T12:30:00Z'},
      {
        'ice_servers': [42],
        'expires_at': '2026-09-15T12:30:00Z',
      },
      {'ice_servers': [], 'expires_at': 'invalid'},
      {'ice_servers': [], 'expires_at': '2026-09-15T12:30:00'},
    ]) {
      expect(
        () => CallConfiguration.fromWampKeywords(value),
        throwsFormatException,
      );
    }
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

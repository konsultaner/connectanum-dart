import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/connectanum.dart' as wamp;
import 'package:crypto/crypto.dart';
import 'package:pinenacl/ed25519.dart';
import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  late _Peer alice;
  late _Peer bob;
  late _Peer charlie;
  late File callFile;

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('wamp-call-rpc-');
    addTearDown(() => directory.delete(recursive: true));
    callFile = File('${directory.path}/calls.json');
    final server = await WampAppServer.start(
      WampAppServerConfig(
        host: '127.0.0.1',
        port: 0,
        websocketPath: '/ws',
        accountStorePath: '${directory.path}/accounts.json',
        messageStorePath: '${directory.path}/messages.json',
        callStorePath: callFile.path,
        stunUrls: const ['stun:localhost:3478'],
        argonIterations: 2,
        argonMemoryKiB: 8192,
      ),
    );
    addTearDown(server.close);
    final registration = wamp.Client(
      transport: wamp.WebSocketTransport.withCborSerializer(
        server.websocketUri.toString(),
      ),
      realm: WampAppProtocol.registrationRealm,
    );
    addTearDown(registration.disconnect);
    final session = await registration
        .connect(options: _singleAttempt)
        .first
        .timeout(const Duration(seconds: 15));
    for (final username in ['alice', 'bob', 'charlie']) {
      await session.callSingle(
        WampAppProtocol.accountRegister,
        argumentsKeywords: AccountRegistration(
          username: username,
          displayName: username,
          password: _password,
        ).toWampKeywords(),
      );
    }
    await session.close(timeout: Duration.zero);
    await registration.disconnect();
    alice = await _connect(server.websocketUri, 'alice', 1);
    bob = await _connect(server.websocketUri, 'bob', 2);
    charlie = await _connect(server.websocketUri, 'charlie', 3);
  });

  test(
    'signed call lifecycle crosses real RPC and pub/sub boundaries',
    () async {
      final configuration = CallConfiguration.fromWampKeywords(
        await alice.call(WampAppProtocol.callConfiguration),
      );
      expect(configuration.iceServers.single.urls, ['stun:localhost:3478']);
      expect(configuration.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);

      final subscription = await bob.session.subscribe(
        WampAppProtocol.callChanged,
      );
      final notification = subscription.eventStream!.first.timeout(
        const Duration(seconds: 10),
      );
      final offer = alice.signal(bob, CallSignalKind.offer, 10);
      final request = CallStartRequest(
        media: CallMediaKind.video,
        calleeUsername: 'bob',
        offers: [offer],
      ).toWampKeywords();
      final started = await alice.call(WampAppProtocol.callStart, request);
      final start = CallUpdate.fromWampKeywords(started);
      expect(started['duplicate'], isFalse);
      expect(start.cursor, 1);
      expect(start.call.state, CallState.ringing);
      expect(start.call.callerUsername, 'alice');
      expect(start.call.calleeUsername, 'bob');
      expect(start.signals.single.toWampKeywords(), offer.toWampKeywords());
      final wakeup = await notification;
      // Notifications disclose only a cursor; ciphertext is fetched by account.
      expect(wakeup.argumentsKeywords, {'cursor': 1});
      final duplicateStart = await alice.call(
        WampAppProtocol.callStart,
        request,
      );
      expect(duplicateStart['duplicate'], isTrue);
      expect(CallUpdate.fromWampKeywords(duplicateStart).cursor, 1);

      final answer = bob.signal(alice, CallSignalKind.answer, 11);
      final accepted = await bob.call(
        WampAppProtocol.callAccept,
        answer.toWampKeywords(),
      );
      final active = CallUpdate.fromWampKeywords(accepted);
      expect(accepted['duplicate'], isFalse);
      expect(active.cursor, 2);
      expect(active.call.state, CallState.active);
      expect(active.call.acceptedDeviceId, bob.deviceId);
      expect(active.call.answeredAt, isNotNull);
      expect(
        (await bob.call(
          WampAppProtocol.callAccept,
          answer.toWampKeywords(),
        ))['duplicate'],
        isTrue,
      );

      final candidate = alice.signal(bob, CallSignalKind.iceCandidate, 12);
      final signaled = await alice.call(
        WampAppProtocol.callSignal,
        candidate.toWampKeywords(),
      );
      expect(signaled['duplicate'], isFalse);
      expect(CallUpdate.fromWampKeywords(signaled).cursor, 3);
      expect(
        (await alice.call(
          WampAppProtocol.callSignal,
          candidate.toWampKeywords(),
        ))['duplicate'],
        isTrue,
      );
      final hangup = alice.signal(bob, CallSignalKind.hangup, 13);
      final ended = await alice.call(
        WampAppProtocol.callEnd,
        hangup.toWampKeywords(),
      );
      expect(ended['duplicate'], isFalse);
      expect(CallUpdate.fromWampKeywords(ended).call.state, CallState.ended);
      expect(CallUpdate.fromWampKeywords(ended).call.endedAt, isNotNull);
      expect(
        (await alice.call(
          WampAppProtocol.callEnd,
          hangup.toWampKeywords(),
        ))['duplicate'],
        isTrue,
      );

      final firstPage = await bob.sync(limit: 2);
      expect(firstPage.nextCursor, 2);
      expect(firstPage.updates.map((update) => update.cursor), [1, 2]);
      final secondPage = await bob.sync(afterCursor: firstPage.nextCursor);
      expect(secondPage.nextCursor, 4);
      expect(secondPage.updates.map((update) => update.cursor), [3, 4]);
      expect(
        secondPage.updates.first.signals.single.sealedPayload,
        candidate.sealedPayload,
      );
      expect((await alice.sync()).updates, hasLength(4));
      expect((await charlie.sync()).updates, isEmpty);
      expect((await bob.sync(afterCursor: 4)).updates, isEmpty);
      await _expectError(
        charlie.call(WampAppProtocol.callSync, {
          'device_id': bob.deviceId,
          'after_cursor': 0,
        }),
        WampAppProtocol.errorNotAuthorized,
      );
    },
  );

  test('call errors are mapped without corrupting durable state', () async {
    for (final procedure in [
      WampAppProtocol.callStart,
      WampAppProtocol.callAccept,
      WampAppProtocol.callSignal,
      WampAppProtocol.callEnd,
      WampAppProtocol.callSync,
    ]) {
      await _expectError(
        alice.call(procedure),
        WampAppProtocol.errorInvalidCall,
      );
    }
    for (final arguments in [
      {'device_id': alice.deviceId, 'after_cursor': '0'},
      {'device_id': 12, 'after_cursor': 0},
      {'device_id': alice.deviceId, 'after_cursor': 0, 'limit': '1'},
      {'device_id': alice.deviceId, 'after_cursor': -1},
      {'device_id': alice.deviceId, 'after_cursor': 0, 'limit': 0},
      {'device_id': alice.deviceId, 'after_cursor': 0, 'limit': 501},
    ]) {
      await _expectError(
        alice.call(WampAppProtocol.callSync, arguments),
        WampAppProtocol.errorInvalidCall,
      );
    }
    final offer = alice.signal(bob, CallSignalKind.offer, 20);
    final request = CallStartRequest(
      media: CallMediaKind.voice,
      calleeUsername: 'bob',
      offers: [offer],
    );
    await _expectError(
      charlie.call(WampAppProtocol.callStart, request.toWampKeywords()),
      WampAppProtocol.errorNotAuthorized,
    );
    final tampered = offer.toWampKeywords();
    tampered['signature'] = _encode(List<int>.filled(64, 0));
    await _expectError(
      alice.call(WampAppProtocol.callStart, {
        ...request.toWampKeywords(),
        'offers': [tampered],
      }),
      WampAppProtocol.errorInvalidCall,
    );
    expect((await bob.sync()).updates, isEmpty);
    await alice.call(WampAppProtocol.callStart, request.toWampKeywords());
    await _expectError(
      alice.call(
        WampAppProtocol.callStart,
        CallStartRequest(
          media: CallMediaKind.video,
          calleeUsername: 'bob',
          offers: [offer],
        ).toWampKeywords(),
      ),
      WampAppProtocol.errorCallConflict,
    );
    await _expectError(
      bob.call(
        WampAppProtocol.callAccept,
        bob
            .signal(alice, CallSignalKind.answer, 21, callSeed: 99)
            .toWampKeywords(),
      ),
      WampAppProtocol.errorCallNotFound,
    );
    await bob.call(
      WampAppProtocol.callAccept,
      bob.signal(alice, CallSignalKind.answer, 22).toWampKeywords(),
    );
    await _expectError(
      bob.call(
        WampAppProtocol.callAccept,
        bob.signal(alice, CallSignalKind.answer, 23).toWampKeywords(),
      ),
      WampAppProtocol.errorCallAnswered,
    );
    await alice.call(
      WampAppProtocol.callEnd,
      alice.signal(bob, CallSignalKind.hangup, 24).toWampKeywords(),
    );
    await _expectError(
      alice.call(
        WampAppProtocol.callSignal,
        alice.signal(bob, CallSignalKind.iceCandidate, 25).toWampKeywords(),
      ),
      WampAppProtocol.errorCallEnded,
    );
    final batch = await alice.sync();
    expect(batch.updates.map((update) => update.call.state), [
      CallState.ringing,
      CallState.active,
      CallState.ended,
    ]);
    expect(batch.nextCursor, 3);
  });

  test(
    'storage failures are redacted and recovery preserves the session',
    () async {
      final request = CallStartRequest(
        media: CallMediaKind.voice,
        calleeUsername: 'bob',
        offers: [alice.signal(bob, CallSignalKind.offer, 30)],
      ).toWampKeywords();
      final original = await callFile.readAsBytes();
      // A directory at the document path triggers a real filesystem failure.
      await callFile.delete();
      final obstruction = await Directory(callFile.path).create();
      try {
        await expectLater(
          alice.call(WampAppProtocol.callStart, request),
          throwsA(
            isA<wamp.Error>()
                .having(
                  (error) => error.error,
                  'URI',
                  WampAppProtocol.errorCallUnavailable,
                )
                .having((error) => error.arguments, 'redacted message', [
                  'Call signaling is temporarily unavailable.',
                ]),
          ),
        );
      } finally {
        await obstruction.delete();
        await callFile.writeAsBytes(original, flush: true);
      }
      expect((await alice.sync()).updates, isEmpty);
      final started = await alice.call(WampAppProtocol.callStart, request);
      expect(CallUpdate.fromWampKeywords(started).cursor, 1);
      expect(started['duplicate'], isFalse);
    },
  );
}

const _password = 'test-only correct horse battery';
final _singleAttempt = wamp.ClientConnectOptions(
  reconnectCount: 0,
  reconnectTime: Duration.zero,
);

Future<void> _expectError(Future<Object?> call, String uri) => expectLater(
  call,
  throwsA(
    isA<wamp.Error>()
        .having((error) => error.error, 'WAMP error URI', uri)
        .having((error) => error.arguments, 'bounded public message', [
          isA<String>().having(
            (message) => message.length,
            'length',
            inInclusiveRange(1, 200),
          ),
        ]),
  ),
);

Future<_Peer> _connect(Uri uri, String username, int seed) async {
  final authentication = wamp.ScramAuthentication(_password);
  addTearDown(authentication.dispose);
  final client = wamp.Client(
    transport: wamp.WebSocketTransport.withCborSerializer(uri.toString()),
    realm: WampAppProtocol.appRealm,
    authId: username,
    authenticationMethods: [authentication],
  );
  addTearDown(client.disconnect);
  final session = await client
      .connect(options: _singleAttempt)
      .first
      .timeout(const Duration(seconds: 45));
  addTearDown(() => session.close(timeout: Duration.zero));
  final key = SigningKey.fromSeed(
    Uint8List.fromList(List<int>.filled(32, seed)),
  );
  final signing = key.verifyKey.asTypedList;
  final exchange = List<int>.filled(32, seed + 10);
  final deviceId = _encode(sha256.convert([...signing, ...exchange]).bytes);
  final createdAt = DateTime.now().toUtc();
  final attestation = DeviceEnrollment.attestationPayloadFor(
    username: username,
    deviceId: deviceId,
    deviceName: '$username test device',
    signingPublicKey: _encode(signing),
    exchangePublicKey: _encode(exchange),
    createdAt: createdAt,
  );
  final peer = _Peer(username, session, key, deviceId);
  final enrolled = DeviceRecord.fromWampKeywords(
    await peer.call(
      WampAppProtocol.deviceEnroll,
      DeviceEnrollment(
        deviceId: deviceId,
        deviceName: '$username test device',
        signingPublicKey: _encode(signing),
        exchangePublicKey: _encode(exchange),
        attestation: _encode(
          key.sign(Uint8List.fromList(attestation)).signature.asTypedList,
        ),
        createdAt: createdAt,
      ).toWampKeywords(),
    ),
  );
  expect(enrolled.username, username);
  expect(enrolled.deviceId, deviceId);
  return peer;
}

final class _Peer {
  _Peer(this.username, this.session, this.key, this.deviceId);
  final String username;
  final wamp.Session session;
  final SigningKey key;
  final String deviceId;

  Future<Map<String, dynamic>> call(
    String procedure, [
    Map<String, dynamic>? arguments,
  ]) async =>
      (await session
              .callSingle(procedure, argumentsKeywords: arguments)
              .timeout(const Duration(seconds: 10)))
          .argumentsKeywords!;

  Future<CallBatch> sync({int afterCursor = 0, int? limit}) async =>
      CallBatch.fromWampKeywords(
        await call(WampAppProtocol.callSync, {
          'device_id': deviceId,
          'after_cursor': afterCursor,
          'limit': ?limit,
        }),
      );

  EncryptedCallSignal signal(
    _Peer recipient,
    CallSignalKind kind,
    int signalSeed, {
    int callSeed = 40,
  }) {
    // The router validates signatures but must not decrypt sealed content.
    final payload = Uint8List.fromList(
      List<int>.filled(
        WampAppCallLimits.sealedBoxOverheadBytes + 1,
        signalSeed,
      ),
    );
    final createdAt = DateTime.now().toUtc();
    final callId = _encode(List<int>.filled(16, callSeed));
    final signalId = _encode(List<int>.filled(16, signalSeed));
    final signaturePayload = EncryptedCallSignal.signaturePayloadFor(
      callId: callId,
      signalId: signalId,
      kind: kind,
      senderUsername: username,
      senderDeviceId: deviceId,
      recipientUsername: recipient.username,
      recipientDeviceId: recipient.deviceId,
      sealedPayload: payload,
      createdAt: createdAt,
    );
    return EncryptedCallSignal(
      callId: callId,
      signalId: signalId,
      kind: kind,
      senderUsername: username,
      senderDeviceId: deviceId,
      recipientUsername: recipient.username,
      recipientDeviceId: recipient.deviceId,
      sealedPayload: payload,
      createdAt: createdAt,
      signature: _encode(
        key.sign(Uint8List.fromList(signaturePayload)).signature.asTypedList,
      ),
    );
  }
}

String _encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

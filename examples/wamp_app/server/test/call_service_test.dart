import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pinenacl/ed25519.dart';
import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  late Directory directory;
  late AccountStore accounts;
  late CallStore calls;
  late CallService service;
  late _TestIdentity alice;
  late _TestIdentity bobPhone;
  late _TestIdentity bobTablet;
  final now = DateTime.utc(2026, 8, 25, 10);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wamp-call-service-');
    accounts = AccountStore('${directory.path}/accounts.json');
    calls = CallStore('${directory.path}/calls.json');
    await accounts.initialize();
    await calls.initialize();
    await accounts.create(_account('alice'));
    await accounts.create(_account('bob'));
    alice = await _enroll(accounts, 'alice', 1, now);
    bobPhone = await _enroll(accounts, 'bob', 2, now);
    bobTablet = await _enroll(accounts, 'bob', 3, now);
    service = CallService(accounts: accounts, store: calls);
  });

  tearDown(() => directory.delete(recursive: true));

  CallStartRequest request({List<_TestIdentity>? recipients}) =>
      CallStartRequest(
        media: CallMediaKind.video,
        calleeUsername: 'bob',
        offers: (recipients ?? [bobPhone, bobTablet])
            .map(
              (recipient) => alice.signal(
                recipient: recipient,
                callSeed: 10,
                signalSeed: recipient.seed + 20,
                kind: CallSignalKind.offer,
                createdAt: now,
              ),
            )
            .toList(),
      );

  test('accepts signed offers covering every active callee device', () async {
    final started = await service.start('Alice', request(), now: now);
    expect(started.update.call.state, CallState.ringing);

    final answer = bobPhone.signal(
      recipient: alice,
      callSeed: 10,
      signalSeed: 30,
      kind: CallSignalKind.answer,
      createdAt: now.add(const Duration(seconds: 2)),
    );
    final accepted = await service.accept(
      'bob',
      answer,
      now: now.add(const Duration(seconds: 2)),
    );
    expect(accepted.update.call.acceptedDeviceId, bobPhone.deviceId);

    final replay = await service.sync(
      'bob',
      bobPhone.deviceId,
      afterCursor: 0,
      now: now.add(const Duration(seconds: 2)),
    );
    expect(replay.updates, hasLength(2));
  });

  test('rejects partial offer coverage and account spoofing', () async {
    await expectLater(
      service.start('alice', request(recipients: [bobPhone]), now: now),
      throwsFormatException,
    );
    await expectLater(
      service.start('mallory', request(), now: now),
      throwsA(isA<StateError>()),
    );
    expect(
      (await calls.sync(
        'alice',
        alice.deviceId,
        afterCursor: 0,
        now: now,
      )).updates,
      isEmpty,
    );
  });

  test('tampered and stale signed signals fail before persistence', () async {
    final offer = request();
    final first = offer.offers.first;
    final tampered = EncryptedCallSignal(
      callId: first.callId,
      signalId: first.signalId,
      kind: first.kind,
      senderUsername: first.senderUsername,
      senderDeviceId: first.senderDeviceId,
      recipientUsername: first.recipientUsername,
      recipientDeviceId: first.recipientDeviceId,
      sealedPayload: Uint8List.fromList(first.sealedPayload)..[0] = 1,
      signature: first.signature,
      createdAt: first.createdAt,
    );
    await expectLater(
      service.start(
        'alice',
        CallStartRequest(
          media: offer.media,
          calleeUsername: offer.calleeUsername,
          offers: [tampered, offer.offers.last],
        ),
        now: now,
      ),
      throwsFormatException,
    );

    final stale = CallStartRequest(
      media: offer.media,
      calleeUsername: offer.calleeUsername,
      offers: offer.offers
          .map(
            (signal) => alice.signal(
              recipient: signal.recipientDeviceId == bobPhone.deviceId
                  ? bobPhone
                  : bobTablet,
              callSeed: 11,
              signalSeed: signal.recipientDeviceId == bobPhone.deviceId
                  ? 41
                  : 42,
              kind: CallSignalKind.offer,
              createdAt: now.subtract(const Duration(minutes: 6)),
            ),
          )
          .toList(),
    );
    await expectLater(
      service.start('alice', stale, now: now),
      throwsFormatException,
    );
  });

  test('revoked sender and recipient devices fail closed', () async {
    await service.start('alice', request(), now: now);
    await accounts.revokeDevice('bob', bobPhone.deviceId, now: now);
    final answer = bobPhone.signal(
      recipient: alice,
      callSeed: 10,
      signalSeed: 50,
      kind: CallSignalKind.answer,
      createdAt: now.add(const Duration(seconds: 1)),
    );
    await expectLater(
      service.accept('bob', answer, now: now.add(const Duration(seconds: 1))),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      service.sync('bob', bobPhone.deviceId, afterCursor: 0, now: now),
      throwsA(isA<StateError>()),
    );
  });
}

final class _TestIdentity {
  const _TestIdentity({
    required this.seed,
    required this.username,
    required this.signingKey,
    required this.record,
  });

  final int seed;
  final String username;
  final SigningKey signingKey;
  final DeviceRecord record;

  String get deviceId => record.deviceId;

  EncryptedCallSignal signal({
    required _TestIdentity recipient,
    required int callSeed,
    required int signalSeed,
    required CallSignalKind kind,
    required DateTime createdAt,
  }) {
    final payload = Uint8List(WampAppCallLimits.sealedBoxOverheadBytes + 1)
      ..fillRange(0, WampAppCallLimits.sealedBoxOverheadBytes + 1, signalSeed);
    final signaturePayload = EncryptedCallSignal.signaturePayloadFor(
      callId: _token(16, callSeed),
      signalId: _token(16, signalSeed),
      kind: kind,
      senderUsername: username,
      senderDeviceId: deviceId,
      recipientUsername: recipient.username,
      recipientDeviceId: recipient.deviceId,
      sealedPayload: payload,
      createdAt: createdAt,
    );
    return EncryptedCallSignal(
      callId: _token(16, callSeed),
      signalId: _token(16, signalSeed),
      kind: kind,
      senderUsername: username,
      senderDeviceId: deviceId,
      recipientUsername: recipient.username,
      recipientDeviceId: recipient.deviceId,
      sealedPayload: payload,
      signature: _encode(
        signingKey
            .sign(Uint8List.fromList(signaturePayload))
            .signature
            .asTypedList,
      ),
      createdAt: createdAt,
    );
  }
}

Future<_TestIdentity> _enroll(
  AccountStore accounts,
  String username,
  int seed,
  DateTime now,
) async {
  final signingKey = SigningKey.fromSeed(
    Uint8List.fromList(List<int>.generate(32, (index) => index + seed)),
  );
  final signingPublicKey = signingKey.verifyKey.asTypedList;
  final exchangePublicKey = Uint8List.fromList(
    List<int>.generate(32, (index) => index + seed + 40),
  );
  final deviceId = _encode(
    sha256.convert([...signingPublicKey, ...exchangePublicKey]).bytes,
  );
  final payload = DeviceEnrollment.attestationPayloadFor(
    username: username,
    deviceId: deviceId,
    deviceName: '$username device $seed',
    signingPublicKey: _encode(signingPublicKey),
    exchangePublicKey: _encode(exchangePublicKey),
    createdAt: now,
  );
  final enrollment = DeviceEnrollment(
    deviceId: deviceId,
    deviceName: '$username device $seed',
    signingPublicKey: _encode(signingPublicKey),
    exchangePublicKey: _encode(exchangePublicKey),
    attestation: _encode(
      signingKey.sign(Uint8List.fromList(payload)).signature.asTypedList,
    ),
    createdAt: now,
  );
  final record = await DeviceService(
    store: accounts,
  ).enroll(username, enrollment, now: now);
  return _TestIdentity(
    seed: seed,
    username: username,
    signingKey: signingKey,
    record: record,
  );
}

StoredAccount _account(String username) => StoredAccount(
  username: username,
  displayName: username,
  storedKey: 'stored',
  serverKey: 'server',
  salt: 'salt',
  iterations: 3,
  memoryKiB: 65536,
  kdf: 'argon2id13',
  createdAt: DateTime.utc(2026, 8, 24),
);

String _encode(List<int> value) => base64Url.encode(value).replaceAll('=', '');

String _token(int bytes, int seed) => base64Url
    .encode(List<int>.generate(bytes, (index) => (index + seed) % 256))
    .replaceAll('=', '');

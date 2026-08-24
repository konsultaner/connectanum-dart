import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pinenacl/ed25519.dart';
import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  late Directory temporary;
  late AccountStore store;
  late DeviceService service;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('wamp-app-devices-');
    store = AccountStore('${temporary.path}/accounts.json');
    await store.initialize();
    await store.create(_account('alice'));
    service = DeviceService(store: store);
  });

  tearDown(() => temporary.delete(recursive: true));

  test('accepts an account-bound Ed25519 device attestation', () async {
    final enrollment = _signedEnrollment('alice');

    final record = await service.enroll('alice', enrollment);

    expect(record.username, 'alice');
    expect(record.deviceId, enrollment.deviceId);
    expect((await service.list('alice')).devices, hasLength(1));
  });

  test('rejects an attestation replayed for another account', () async {
    final enrollment = _signedEnrollment('alice');

    await expectLater(service.enroll('bob', enrollment), throwsFormatException);
  });

  test('rejects a device identifier that does not bind both public keys', () {
    final enrollment = _signedEnrollment('alice');
    final changed = DeviceEnrollment(
      deviceId: _encode(Uint8List(32)),
      deviceName: enrollment.deviceName,
      signingPublicKey: enrollment.signingPublicKey,
      exchangePublicKey: enrollment.exchangePublicKey,
      attestation: enrollment.attestation,
      createdAt: enrollment.createdAt,
    );

    expect(() => service.enroll('alice', changed), throwsFormatException);
  });
}

DeviceEnrollment _signedEnrollment(String username) {
  final signingKey = SigningKey.generate();
  final signingPublicKey = signingKey.verifyKey.asTypedList;
  final exchangePublicKey = Uint8List.fromList(
    List<int>.generate(32, (index) => index + 1),
  );
  final deviceId = _encode(
    sha256.convert([...signingPublicKey, ...exchangePublicKey]).bytes,
  );
  final createdAt = DateTime.utc(2026, 8, 24, 12);
  final payload = DeviceEnrollment.attestationPayloadFor(
    username: username,
    deviceId: deviceId,
    deviceName: 'Alice phone',
    signingPublicKey: _encode(signingPublicKey),
    exchangePublicKey: _encode(exchangePublicKey),
    createdAt: createdAt,
  );
  final signature = signingKey.sign(Uint8List.fromList(payload)).signature;
  return DeviceEnrollment(
    deviceId: deviceId,
    deviceName: 'Alice phone',
    signingPublicKey: _encode(signingPublicKey),
    exchangePublicKey: _encode(exchangePublicKey),
    attestation: _encode(signature.asTypedList),
    createdAt: createdAt,
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

import 'dart:io';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  late Directory temporary;
  late AccountStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('wamp-app-store-');
    store = AccountStore('${temporary.path}/accounts.json');
    await store.initialize();
  });

  tearDown(() => temporary.delete(recursive: true));

  test('persists only SCRAM verifier material', () async {
    final createdAt = DateTime.utc(2026, 8, 24);
    await store.create(
      StoredAccount(
        username: 'alice',
        displayName: 'Alice',
        storedKey: 'stored',
        serverKey: 'server',
        salt: 'salt',
        iterations: 3,
        memoryKiB: 65536,
        kdf: 'argon2id13',
        createdAt: createdAt,
      ),
    );

    final account = await store.find('alice');
    final raw = await store.file.readAsString();
    expect(account?.displayName, 'Alice');
    expect(raw, contains('stored_key'));
    expect(raw, contains('server_key'));
    expect(raw, isNot(contains('password')));
  });

  test('serializes competing account writes without losing data', () async {
    StoredAccount account(String username) => StoredAccount(
      username: username,
      displayName: username,
      storedKey: 'stored-$username',
      serverKey: 'server-$username',
      salt: 'salt-$username',
      iterations: 3,
      memoryKiB: 65536,
      kdf: 'argon2id13',
      createdAt: DateTime.utc(2026, 8, 24),
    );

    await Future.wait([
      store.create(account('alice')),
      store.create(account('bob')),
    ]);

    expect(await store.find('alice'), isNotNull);
    expect(await store.find('bob'), isNotNull);
  });

  test('rejects duplicate usernames', () async {
    final account = StoredAccount(
      username: 'alice',
      displayName: 'Alice',
      storedKey: 'stored',
      serverKey: 'server',
      salt: 'salt',
      iterations: 3,
      memoryKiB: 65536,
      kdf: 'argon2id13',
      createdAt: DateTime.utc(2026, 8, 24),
    );
    await store.create(account);

    expect(() => store.create(account), throwsA(isA<AccountAlreadyExists>()));
  });

  test('reads schema-one accounts created before device directories', () async {
    final legacyAccount = _account('alice').toJson()..remove('devices');
    await store.file.writeAsString(
      jsonEncode({
        'schema': 1,
        'accounts': {'alice': legacyAccount},
      }),
      flush: true,
    );

    final account = await store.find('alice');

    expect(account?.devices, isEmpty);
  });

  test(
    'device enrollment is idempotent and conflicting material is rejected',
    () async {
      await store.create(_account('alice'));
      final enrollment = _enrollment(1);

      final created = await store.enrollDevice(
        'alice',
        enrollment,
        now: DateTime.utc(2026, 8, 24, 12),
      );
      final refreshed = await store.enrollDevice(
        'alice',
        enrollment,
        now: DateTime.utc(2026, 8, 24, 13),
      );

      expect(refreshed.enrolledAt, created.enrolledAt);
      expect(refreshed.lastSeenAt, DateTime.utc(2026, 8, 24, 13));
      await expectLater(
        store.enrollDevice(
          'alice',
          DeviceEnrollment(
            deviceId: enrollment.deviceId,
            deviceName: 'Impostor',
            signingPublicKey: enrollment.signingPublicKey,
            exchangePublicKey: enrollment.exchangePublicKey,
            attestation: enrollment.attestation,
            createdAt: enrollment.createdAt,
          ),
        ),
        throwsA(isA<DeviceConflict>()),
      );
    },
  );

  test(
    'revocation is durable, idempotent, and prevents re-enrollment',
    () async {
      await store.create(_account('alice'));
      final enrollment = _enrollment(1);
      await store.enrollDevice(
        'alice',
        enrollment,
        now: DateTime.utc(2026, 8, 24, 12),
      );

      final revoked = await store.revokeDevice(
        'alice',
        enrollment.deviceId,
        now: DateTime.utc(2026, 8, 24, 14),
      );
      final repeated = await store.revokeDevice(
        'alice',
        enrollment.deviceId,
        now: DateTime.utc(2026, 8, 24, 15),
      );

      expect(repeated.revokedAt, revoked.revokedAt);
      expect(await store.listDevices('alice'), isEmpty);
      expect(
        await store.listDevices('alice', includeRevoked: true),
        hasLength(1),
      );
      await expectLater(
        store.enrollDevice('alice', enrollment),
        throwsA(isA<DeviceRevoked>()),
      );
    },
  );

  test('serializes competing device writes without losing data', () async {
    await store.create(_account('alice'));

    await Future.wait([
      store.enrollDevice('alice', _enrollment(1)),
      store.enrollDevice('alice', _enrollment(20)),
    ]);

    expect(await store.listDevices('alice'), hasLength(2));
  });
}

StoredAccount _account(String username) => StoredAccount(
  username: username,
  displayName: username,
  storedKey: 'stored-$username',
  serverKey: 'server-$username',
  salt: 'salt-$username',
  iterations: 3,
  memoryKiB: 65536,
  kdf: 'argon2id13',
  createdAt: DateTime.utc(2026, 8, 24),
);

DeviceEnrollment _enrollment(int seed) => DeviceEnrollment(
  deviceId: _token(32, seed),
  deviceName: 'Device $seed',
  signingPublicKey: _token(32, seed + 1),
  exchangePublicKey: _token(32, seed + 2),
  attestation: _token(64, seed + 3),
  createdAt: DateTime.utc(2026, 8, 24, 12),
);

String _token(int length, int seed) => base64Url
    .encode(List<int>.generate(length, (index) => (seed + index) & 0xff))
    .replaceAll('=', '');

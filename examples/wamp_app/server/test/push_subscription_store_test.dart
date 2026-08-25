import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  late Directory temporary;
  late PlatformPushSubscriptionStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('wamp-app-push-store-');
    store = PlatformPushSubscriptionStore('${temporary.path}/push.json');
    await store.initialize();
  });

  tearDown(() => temporary.delete(recursive: true));

  test(
    'replaces a device provider token without changing registration',
    () async {
      final registeredAt = DateTime.utc(2026, 8, 24, 12);
      final first = await store.upsert(
        'Alice',
        _request(deviceSeed: 1, token: 'token-one'),
        now: registeredAt,
      );
      final replacement = await store.upsert(
        'alice',
        _request(deviceSeed: 1, token: 'token-two'),
        now: registeredAt.add(const Duration(minutes: 5)),
      );

      expect(replacement.registeredAt, first.registeredAt);
      expect(
        replacement.updatedAt,
        registeredAt.add(const Duration(minutes: 5)),
      );
      expect(replacement.token, 'token-two');
      final persisted = (await store.listForUsernames(['alice'])).single;
      expect(persisted.token, replacement.token);
      expect(persisted.registeredAt, replacement.registeredAt);
      expect(persisted.updatedAt, replacement.updatedAt);
    },
  );

  test(
    'clamps replacement time when the server clock moves backwards',
    () async {
      final registeredAt = DateTime.utc(2026, 8, 24, 12);
      await store.upsert(
        'alice',
        _request(deviceSeed: 1, token: 'token-one'),
        now: registeredAt,
      );

      final replacement = await store.upsert(
        'alice',
        _request(deviceSeed: 1, token: 'token-two'),
        now: registeredAt.subtract(const Duration(hours: 1)),
      );

      expect(replacement.registeredAt, registeredAt);
      expect(replacement.updatedAt, registeredAt);
    },
  );

  test(
    'moves an opaque provider token to its latest account binding',
    () async {
      await store.upsert(
        'alice',
        _request(deviceSeed: 1, token: 'shared-token'),
      );
      final bob = await store.upsert(
        'bob',
        _request(deviceSeed: 2, token: 'shared-token'),
      );

      expect(await store.listForUsernames(['alice']), isEmpty);
      final persisted = (await store.listForUsernames(['bob'])).single;
      expect(persisted.token, bob.token);
      expect(persisted.deviceId, bob.deviceId);
    },
  );

  test(
    'serializes concurrent registrations and enforces the account bound',
    () async {
      store = PlatformPushSubscriptionStore(
        '${temporary.path}/bounded.json',
        maxSubscriptionsPerAccount: 2,
      );
      await store.initialize();

      await Future.wait([
        store.upsert('alice', _request(deviceSeed: 1, token: 'token-one')),
        store.upsert(
          'alice',
          _request(deviceSeed: 2, provider: 'fcm', token: 'token-two'),
        ),
      ]);

      expect(await store.listForUsernames(['alice']), hasLength(2));
      await expectLater(
        store.upsert('alice', _request(deviceSeed: 3, token: 'token-three')),
        throwsA(isA<PushSubscriptionLimitExceeded>()),
      );
    },
  );

  test('reopens valid data and rejects malformed persisted fields', () async {
    await store.upsert('alice', _request(deviceSeed: 1, token: 'token-one'));
    final reopened = PlatformPushSubscriptionStore(store.file.path);
    expect(await reopened.listForUsernames(['alice']), hasLength(1));

    final decoded =
        jsonDecode(await store.file.readAsString()) as Map<String, dynamic>;
    final subscriptions = decoded['subscriptions'] as List<dynamic>;
    (subscriptions.single as Map<String, dynamic>)['registered_at'] = 42;
    await store.file.writeAsString(jsonEncode(decoded));

    await expectLater(
      reopened.listForUsernames(['alice']),
      throwsA(isA<FormatException>()),
    );
  });

  test('repairs permissive secret-store permissions on startup', () async {
    if (Platform.isWindows) return;
    await Process.run('chmod', ['644', store.file.path]);

    await store.initialize();

    final mode = (await store.file.stat()).mode & 0x1ff;
    expect(mode, 0x180, reason: 'push provider tokens require mode 0600');
  });
}

PlatformPushSubscriptionRequest _request({
  required int deviceSeed,
  required String token,
  String provider = 'apns',
}) => PlatformPushSubscriptionRequest(
  deviceId: _token(32, deviceSeed),
  provider: provider,
  token: token,
);

String _token(int length, int seed) => base64Url
    .encode(List<int>.generate(length, (index) => (seed + index) & 0xff))
    .replaceAll('=', '');

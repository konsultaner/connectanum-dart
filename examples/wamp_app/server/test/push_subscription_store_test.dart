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
    'initialization creates nested storage and preserves registered tokens',
    () async {
      final nested = PlatformPushSubscriptionStore(
        '${temporary.path}/nested/deep/push.json',
      );
      expect(await nested.listForUsernames(['alice']), isEmpty);
      await Future.wait([nested.initialize(), nested.initialize()]);
      final registered = await nested.upsert(
        'alice',
        _request(deviceSeed: 1, token: 'existing-token'),
      );
      await Future.wait([nested.initialize(), nested.initialize()]);
      expect(
        (await nested.listForUsernames(['Alice'])).single.toJson(),
        registered.toJson(),
      );
    },
  );

  test(
    'storage rejects malformed schemas and entries without rewriting them',
    () async {
      final documents = <Object?>[
        null,
        [],
        'not-an-object',
        {},
        for (final schema in <Object?>[null, 0, 2, true, '1'])
          {'schema': schema, 'subscriptions': []},
        for (final entries in <Object?>[null, {}, 'not-a-list', 1])
          {'schema': 1, 'subscriptions': entries},
        for (final entry in <Object?>[null, [], 'not-a-map', 1])
          {
            'schema': 1,
            'subscriptions': [entry],
          },
      ];
      for (final document in documents) {
        final encoded = jsonEncode(document);
        await store.file.writeAsString(encoded);
        await expectLater(
          store.listForUsernames(['alice']),
          throwsFormatException,
        );
        expect(await store.file.readAsString(), encoded);
      }
    },
  );

  test(
    'duplicate binding keys and provider tokens are rejected independently',
    () async {
      final first = (await store.upsert(
        'alice',
        _request(deviceSeed: 1, token: 'token-one'),
      )).toJson();
      for (final second in [
        {...first, 'token': 'different-token'},
        {...first, 'username': 'bob', 'device_id': _token(32, 2)},
      ]) {
        await store.file.writeAsString(
          jsonEncode({
            'schema': 1,
            'subscriptions': [first, second],
          }),
        );
        await expectLater(
          store.listForUsernames(['alice', 'bob']),
          throwsFormatException,
        );
      }
      await store.file.writeAsString(
        jsonEncode({
          'schema': 1,
          'subscriptions': [
            first,
            {...first, 'provider': 'fcm'},
          ],
        }),
      );
      expect(
        (await store.listForUsernames([
          'alice',
        ])).map((entry) => entry.provider),
        ['apns', 'fcm'],
      );
    },
  );

  test(
    'subscription capacity is per account and failed transfer is atomic',
    () async {
      store = PlatformPushSubscriptionStore(
        '${temporary.path}/one-per-account.json',
        maxSubscriptionsPerAccount: 1,
      );
      await store.initialize();
      final alice = await store.upsert(
        'alice',
        _request(deviceSeed: 1, token: 'alice-token'),
      );
      final bob = await store.upsert(
        'bob',
        _request(deviceSeed: 2, token: 'bob-token'),
      );
      await expectLater(
        store.upsert('alice', _request(deviceSeed: 3, token: 'bob-token')),
        throwsA(isA<PushSubscriptionLimitExceeded>()),
      );
      expect(
        (await store.listForUsernames(['alice'])).single.toJson(),
        alice.toJson(),
      );
      expect(
        (await store.listForUsernames(['bob'])).single.toJson(),
        bob.toJson(),
      );
      final updated = await store.upsert(
        'alice',
        _request(deviceSeed: 1, token: 'replacement-token'),
      );
      expect(updated.token, 'replacement-token');
      expect(updated.registeredAt, alice.registeredAt);
      expect(
        (await store.listForUsernames(['bob'])).single.toJson(),
        bob.toJson(),
      );
    },
  );

  test(
    'remove matches account, device and provider without crossing bindings',
    () async {
      final alice = await store.upsert(
        'alice',
        _request(deviceSeed: 1, token: 'alice-apns'),
      );
      final sameDevice = await store.upsert(
        'alice',
        _request(deviceSeed: 1, token: 'alice-fcm', provider: 'fcm'),
      );
      final otherDevice = await store.upsert(
        'alice',
        _request(deviceSeed: 2, token: 'other-device'),
      );
      final bob = await store.upsert(
        'bob',
        _request(deviceSeed: 1, token: 'bob-apns'),
      );
      final key = PlatformPushSubscriptionKey(
        deviceId: alice.deviceId,
        provider: 'apns',
      );
      expect(await store.remove('Alice', key), isTrue);
      expect(await store.remove('alice', key), isFalse);
      final remaining = await store.listForUsernames(['alice', 'bob']);
      expect(
        remaining.map((item) => item.toJson()),
        unorderedEquals([
          sameDevice.toJson(),
          otherDevice.toJson(),
          bob.toJson(),
        ]),
      );
      expect(await store.removeDevice('Alice', alice.deviceId), 1);
      expect(await store.removeDevice('alice', alice.deviceId), 0);
      expect(await store.removeDevice('alice', otherDevice.deviceId), 1);
      expect(
        (await store.listForUsernames(['bob'])).single.toJson(),
        bob.toJson(),
      );
    },
  );

  test(
    'compare-and-delete reports stale, current and absent bindings accurately',
    () async {
      final stale = await store.upsert(
        'alice',
        _request(deviceSeed: 1, token: 'old-token'),
      );
      final current = await store.upsert(
        'alice',
        _request(deviceSeed: 1, token: 'new-token'),
      );
      final bob = await store.upsert(
        'bob',
        _request(deviceSeed: 2, token: 'old-token'),
      );
      expect(await store.removeIfCurrent(stale), isFalse);
      expect(
        (await store.listForUsernames(['alice'])).single.toJson(),
        current.toJson(),
      );
      expect(
        (await store.listForUsernames(['bob'])).single.toJson(),
        bob.toJson(),
      );
      expect(await store.removeIfCurrent(current), isTrue);
      expect(await store.removeIfCurrent(current), isFalse);
      expect(await store.listForUsernames(['alice']), isEmpty);
      expect(
        (await store.listForUsernames(['bob'])).single.toJson(),
        bob.toJson(),
      );
    },
  );

  test(
    'mute-policy replacement detects same-length changes and persists them',
    () async {
      final at = DateTime.utc(2026, 9, 16);
      final first = await store.upsert(
        'alice',
        _request(
          deviceSeed: 1,
          token: 'same-token',
          mutedConversationIds: ['conversation-a', 'conversation-b'],
        ),
        now: at,
      );
      final second = await store.upsert(
        'alice',
        _request(
          deviceSeed: 1,
          token: 'same-token',
          mutedConversationIds: ['conversation-a', 'conversation-c'],
        ),
        now: at.add(const Duration(minutes: 1)),
      );
      expect(second.registeredAt, first.registeredAt);
      expect(second.updatedAt, at.add(const Duration(minutes: 1)));
      expect(second.mutedConversationIds, ['conversation-a', 'conversation-c']);
      expect(
        (await store.listForUsernames(['alice'])).single.toJson(),
        second.toJson(),
      );
    },
  );

  test(
    'stored constructors reject blank usernames and reversed timestamps',
    () {
      final now = DateTime.utc(2026, 9, 16);
      StoredPlatformPushSubscription entry(
        String username,
        DateTime updatedAt,
      ) => StoredPlatformPushSubscription(
        username: username,
        deviceId: _token(32, 1),
        provider: 'apns',
        token: 'token-one',
        registeredAt: now,
        updatedAt: updatedAt,
      );
      expect(() => entry('   ', now), throwsFormatException);
      expect(
        () => entry('alice', now.subtract(const Duration(microseconds: 1))),
        throwsFormatException,
      );
      expect(entry('Alice', now).username, 'alice');
      expect(entry('alice', now).updatedAt, now);
    },
  );

  test('permission-setting failure fails initialization closed', () async {
    final fakeBin = await Directory('${temporary.path}/fake-bin').create();
    final chmod = File('${fakeBin.path}/chmod');
    await chmod.writeAsString('#!/bin/sh\nexit 1\n');
    expect((await Process.run('chmod', ['700', chmod.path])).exitCode, 0);
    final helper = File('${temporary.path}/permission_probe.dart');
    await helper.writeAsString('''
import 'dart:io';
import 'package:wamp_app_server/src/push_subscription_store.dart';
Future<void> main(List<String> args) async {
  try {
    await PlatformPushSubscriptionStore(args.single).initialize();
    exitCode = 17;
  } on FileSystemException catch (error) {
    if (error.message != 'Could not restrict push subscription store permissions' || error.path != args.single) rethrow;
    stdout.write('permission-failure');
  }
}
''');
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        helper.path,
        store.file.path,
      ],
      environment: {'PATH': fakeBin.path},
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, 'permission-failure');
  }, skip: Platform.isWindows ? 'POSIX chmod failure path' : false);

  test('rejects invalid subscription capacity and accepts both boundaries', () {
    for (final capacity in [-1, 0, 257]) {
      expect(
        () => PlatformPushSubscriptionStore(
          store.file.path,
          maxSubscriptionsPerAccount: capacity,
        ),
        throwsArgumentError,
      );
    }
    for (final capacity in [1, 256]) {
      expect(
        PlatformPushSubscriptionStore(
          store.file.path,
          maxSubscriptionsPerAccount: capacity,
        ).maxSubscriptionsPerAccount,
        capacity,
      );
    }
  });

  test(
    'rejects malformed stored strings, mute lists and timestamps independently',
    () async {
      final original = (await store.upsert(
        'alice',
        _request(deviceSeed: 1, token: 'token-one'),
      )).toJson();
      for (final field in ['username', 'device_id', 'provider', 'token']) {
        for (final invalid in <Object?>[null, '', 7, false, <String>[]]) {
          expect(
            () => StoredPlatformPushSubscription.fromJson({
              ...original,
              field: invalid,
            }),
            throwsFormatException,
            reason: '$field must reject ${invalid.runtimeType}',
          );
        }
      }
      for (final invalid in <Object>[
        'conversation-1',
        7,
        <String, String>{},
        [null],
        [7],
        ['valid', false],
      ]) {
        expect(
          () => StoredPlatformPushSubscription.fromJson({
            ...original,
            'muted_conversation_ids': invalid,
          }),
          throwsFormatException,
        );
      }
      for (final field in ['registered_at', 'updated_at']) {
        for (final invalid in <Object?>[
          null,
          false,
          7,
          '',
          'not-a-date',
          '2026-08-24T12:00:00',
        ]) {
          expect(
            () => StoredPlatformPushSubscription.fromJson({
              ...original,
              field: invalid,
            }),
            throwsFormatException,
            reason: '$field must be a serialized UTC timestamp',
          );
        }
      }
      final roundTrip = StoredPlatformPushSubscription.fromJson(original);
      expect(roundTrip.toJson(), original);
      expect(roundTrip.receipt.deviceId, original['device_id']);
      expect(roundTrip.receipt.provider, original['provider']);
    },
  );

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

  test('updates mute policy without rotating the provider token', () async {
    final registeredAt = DateTime.utc(2026, 8, 24, 12);
    final first = await store.upsert(
      'alice',
      _request(deviceSeed: 1, token: 'token-one'),
      now: registeredAt,
    );
    final updated = await store.upsert(
      'alice',
      _request(
        deviceSeed: 1,
        token: 'token-one',
        mutedConversationIds: const ['conversation-b', 'conversation-a'],
      ),
      now: registeredAt.add(const Duration(minutes: 5)),
    );

    expect(updated.registeredAt, first.registeredAt);
    expect(updated.updatedAt, registeredAt.add(const Duration(minutes: 5)));
    expect(updated.token, first.token);
    expect(updated.mutedConversationIds, ['conversation-a', 'conversation-b']);

    final unchanged = await store.upsert(
      'alice',
      _request(
        deviceSeed: 1,
        token: 'token-one',
        mutedConversationIds: updated.mutedConversationIds,
      ),
      now: registeredAt.add(const Duration(minutes: 10)),
    );
    expect(unchanged.updatedAt, updated.updatedAt);
  });

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

  test('reopens legacy registrations without mute policy', () async {
    await store.upsert('alice', _request(deviceSeed: 1, token: 'token-one'));
    final decoded =
        jsonDecode(await store.file.readAsString()) as Map<String, dynamic>;
    final subscriptions = decoded['subscriptions'] as List<dynamic>;
    (subscriptions.single as Map<String, dynamic>).remove(
      'muted_conversation_ids',
    );
    await store.file.writeAsString(jsonEncode(decoded));

    final reopened = PlatformPushSubscriptionStore(store.file.path);
    expect(
      (await reopened.listForUsernames(['alice'])).single.mutedConversationIds,
      isEmpty,
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
  Iterable<String> mutedConversationIds = const [],
}) => PlatformPushSubscriptionRequest(
  deviceId: _token(32, deviceSeed),
  provider: provider,
  token: token,
  mutedConversationIds: mutedConversationIds,
);

String _token(int length, int seed) => base64Url
    .encode(List<int>.generate(length, (index) => (seed + index) & 0xff))
    .replaceAll('=', '');

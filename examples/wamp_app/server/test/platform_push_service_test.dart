import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  late Directory temporary;
  late AccountStore accounts;
  late PlatformPushSubscriptionStore subscriptions;
  late PlatformPushService service;
  late DeviceEnrollment aliceDevice;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('wamp-app-push-');
    accounts = AccountStore('${temporary.path}/accounts.json');
    subscriptions = PlatformPushSubscriptionStore(
      '${temporary.path}/push.json',
    );
    await accounts.initialize();
    await subscriptions.initialize();
    await accounts.create(_account('alice'));
    await accounts.create(_account('bob'));
    aliceDevice = _enrollment(1);
    await accounts.enrollDevice('alice', aliceDevice);
    service = PlatformPushService(accounts: accounts, store: subscriptions);
  });

  tearDown(() => temporary.delete(recursive: true));

  test('registration is caller and active-device bound', () async {
    final receipt = await service.register(
      'Alice',
      _request(aliceDevice, 'token-one'),
    );

    expect(receipt.deviceId, aliceDevice.deviceId);
    await expectLater(
      service.register('bob', _request(aliceDevice, 'token-two')),
      throwsA(isA<DeviceNotFound>()),
    );

    await accounts.revokeDevice('alice', aliceDevice.deviceId);
    await expectLater(
      service.register('alice', _request(aliceDevice, 'token-three')),
      throwsA(isA<DeviceRevoked>()),
    );
  });

  test('revoked subscriptions are pruned before delivery', () async {
    await service.register('alice', _request(aliceDevice, 'token-one'));
    await accounts.revokeDevice('alice', aliceDevice.deviceId);

    expect(await service.activeSubscriptions(['alice']), isEmpty);
    expect(await subscriptions.listForUsernames(['alice']), isEmpty);
  });

  test('unregister is account-bound, normalized and idempotent', () async {
    final request = _request(aliceDevice, 'alice-token');
    final key = PlatformPushSubscriptionKey(
      deviceId: aliceDevice.deviceId,
      provider: 'apns',
    );
    await service.register('alice', request);
    await expectLater(
      service.unregister('bob', key),
      throwsA(isA<DeviceNotFound>()),
    );
    expect(
      (await subscriptions.listForUsernames(['alice'])).single.token,
      'alice-token',
    );
    expect(await service.unregister('Alice', key), isTrue);
    expect(await service.unregister('alice', key), isFalse);
    expect(await subscriptions.listForUsernames(['alice']), isEmpty);
  });

  test('unregister remains available after device revocation', () async {
    await service.register('alice', _request(aliceDevice, 'alice-token'));
    await accounts.revokeDevice('alice', aliceDevice.deviceId);
    expect(
      await service.unregister(
        'alice',
        PlatformPushSubscriptionKey(
          deviceId: aliceDevice.deviceId,
          provider: 'apns',
        ),
      ),
      isTrue,
    );
    expect(await subscriptions.listForUsernames(['alice']), isEmpty);
  });

  test(
    'revocation removes every provider only for the named account/device',
    () async {
      final otherDevice = _enrollment(20);
      await accounts.enrollDevice('alice', otherDevice);
      await accounts.enrollDevice('bob', aliceDevice);
      await service.register('alice', _request(aliceDevice, 'alice-apns'));
      await service.register(
        'alice',
        PlatformPushSubscriptionRequest(
          deviceId: aliceDevice.deviceId,
          provider: 'fcm',
          token: 'alice-fcm',
        ),
      );
      await service.register('alice', _request(otherDevice, 'other-device'));
      await service.register('bob', _request(aliceDevice, 'bob-token'));
      await service.deviceRevoked('Alice', aliceDevice.deviceId);
      await service.deviceRevoked('alice', aliceDevice.deviceId);
      expect(
        (await subscriptions.listForUsernames(['alice'])).single.token,
        'other-device',
      );
      expect(
        (await subscriptions.listForUsernames(['bob'])).single.token,
        'bob-token',
      );
    },
  );

  test(
    'dispatcher delivers valid work, ignores invalid cursors and stays closed',
    () async {
      await service.register('alice', _request(aliceDevice, 'alice-token'));
      final gateway = _RecordingGateway(
        (_) async => PlatformPushDeliveryResult.accepted,
      );
      final dispatcher = PlatformPushDispatcher(
        service: service,
        gateway: gateway,
        maxPendingAccounts: 1,
      );
      dispatcher.enqueue(0, ['alice']);
      dispatcher.enqueue(-1, ['alice']);
      dispatcher.enqueue(1, ['  ', 'Alice', 'alice']);
      await dispatcher.close();
      expect(gateway.deliveries, [
        const _Delivery(provider: 'apns', token: 'alice-token', cursor: 1),
      ]);
      dispatcher.enqueue(2, ['alice']);
      await dispatcher.close();
      expect(gateway.deliveries, hasLength(1));
    },
  );

  test(
    'dispatcher rejects nonpositive queue, presentation and time bounds',
    () {
      final gateway = _RecordingGateway(
        (_) async => PlatformPushDeliveryResult.accepted,
      );
      for (final limit in [0, -1]) {
        expect(
          () => PlatformPushDispatcher(
            service: service,
            gateway: gateway,
            maxPendingAccounts: limit,
          ),
          throwsArgumentError,
        );
        expect(
          () => PlatformPushDispatcher(
            service: service,
            gateway: gateway,
            maxPendingPresentationConversationsPerAccount: limit,
          ),
          throwsArgumentError,
        );
        expect(
          () => PlatformPushDispatcher(
            service: service,
            gateway: gateway,
            deliveryTimeout: Duration(microseconds: limit),
          ),
          throwsArgumentError,
        );
      }
      expect(gateway.deliveries, isEmpty);
    },
  );

  test(
    'presentation IDs accept the exact maximum and reject empty or oversized values',
    () async {
      await service.register('alice', _request(aliceDevice, 'alice-token'));
      for (final conversation in <String?>[
        null,
        '',
        'x' * 199,
        'x' * 200,
        'x' * 201,
      ]) {
        final gateway = _RecordingGateway(
          (_) async => PlatformPushDeliveryResult.accepted,
        );
        final dispatcher = PlatformPushDispatcher(
          service: service,
          gateway: gateway,
        );
        dispatcher.enqueue(
          1,
          ['alice'],
          presentationConversationId: conversation,
          presentationUsernames: ['Alice'],
        );
        await dispatcher.close();
        expect(
          gateway.deliveries.single.present,
          conversation != null &&
              (conversation.length == 199 || conversation.length == 200),
        );
      }
    },
  );

  for (final limit in [1, 2]) {
    test(
      'presentation queue honors the $limit-conversation cap at its boundary',
      () async {
        await service.register(
          'alice',
          _request(
            aliceDevice,
            'alice-token',
            mutedConversationIds: ['muted-0', 'muted-1'],
          ),
        );
        final gateway = _RecordingGateway(
          (_) async => PlatformPushDeliveryResult.accepted,
        );
        final dispatcher = PlatformPushDispatcher(
          service: service,
          gateway: gateway,
          maxPendingPresentationConversationsPerAccount: limit,
        );
        // The first batch is awaiting subscription lookup while the next batch fills.
        dispatcher.enqueue(1, ['alice']);
        for (var index = 0; index < limit; index++) {
          dispatcher.enqueue(
            index + 2,
            ['alice'],
            presentationConversationId: 'muted-$index',
            presentationUsernames: ['alice'],
          );
        }
        dispatcher.enqueue(
          10,
          ['alice'],
          presentationConversationId: 'unmuted-overflow',
          presentationUsernames: ['alice'],
        );
        await dispatcher.close();
        expect(gateway.deliveries, [
          const _Delivery(provider: 'apns', token: 'alice-token', cursor: 1),
          const _Delivery(provider: 'apns', token: 'alice-token', cursor: 10),
        ]);
      },
    );
  }

  test(
    'older queued cursors cannot lower delivery but still contribute presentation',
    () async {
      await service.register('alice', _request(aliceDevice, 'alice-token'));
      final gateway = _RecordingGateway(
        (_) async => PlatformPushDeliveryResult.accepted,
      );
      final dispatcher = PlatformPushDispatcher(
        service: service,
        gateway: gateway,
      );
      dispatcher.enqueue(100, ['alice']);
      dispatcher.enqueue(200, ['alice']);
      dispatcher.enqueue(
        150,
        ['alice'],
        presentationConversationId: 'conversation-1',
        presentationUsernames: ['alice'],
      );
      await dispatcher.close();
      expect(gateway.deliveries, [
        const _Delivery(provider: 'apns', token: 'alice-token', cursor: 100),
        const _Delivery(
          provider: 'apns',
          token: 'alice-token',
          cursor: 200,
          present: true,
        ),
      ]);
    },
  );

  test(
    'subscription read failure is redacted and does not prevent recovery',
    () async {
      await service.register('alice', _request(aliceDevice, 'alice-token'));
      final original = await subscriptions.file.readAsBytes();
      await subscriptions.file.writeAsString('private-corrupt-content');
      final failures = <PlatformPushDispatchFailure>[];
      final reported = Completer<void>();
      final gateway = _RecordingGateway(
        (_) async => PlatformPushDeliveryResult.accepted,
      );
      final dispatcher = PlatformPushDispatcher(
        service: service,
        gateway: gateway,
        onBackgroundFailure: (failure) {
          failures.add(failure);
          if (!reported.isCompleted) reported.complete();
        },
      );
      addTearDown(dispatcher.close);
      dispatcher.enqueue(1, ['alice']);
      await reported.future;
      expect(gateway.deliveries, isEmpty);
      await subscriptions.file.writeAsBytes(original);
      dispatcher.enqueue(2, ['alice']);
      await dispatcher.close();
      expect(failures, [PlatformPushDispatchFailure.subscriptionLookup]);
      expect(gateway.deliveries.single.cursor, 2);
    },
  );

  test(
    'token retirement read failure does not prevent the next account delivery',
    () async {
      final bobDevice = _enrollment(20);
      await accounts.enrollDevice('bob', bobDevice);
      await service.register('alice', _request(aliceDevice, 'alice-token'));
      await service.register('bob', _request(bobDevice, 'bob-token'));
      final failures = <PlatformPushDispatchFailure>[];
      final gateway = _RecordingGateway((delivery) async {
        if (delivery.token == 'alice-token') {
          // A readable but invalid document forces the retirement transaction to fail.
          await subscriptions.file.writeAsString('private-retirement-failure');
          return PlatformPushDeliveryResult.invalidToken;
        }
        return PlatformPushDeliveryResult.accepted;
      });
      final original = await subscriptions.file.readAsBytes();
      final dispatcher = PlatformPushDispatcher(
        service: service,
        gateway: gateway,
        onBackgroundFailure: failures.add,
      );
      dispatcher.enqueue(3, ['alice', 'bob']);
      await dispatcher.close();
      expect(failures, [PlatformPushDispatchFailure.tokenRetirement]);
      expect(gateway.deliveries.map((delivery) => delivery.token), [
        'alice-token',
        'bob-token',
      ]);
      expect(
        await subscriptions.file.readAsString(),
        'private-retirement-failure',
      );
      await subscriptions.file.writeAsBytes(original);
      expect(
        await subscriptions.listForUsernames(['alice', 'bob']),
        hasLength(2),
      );
    },
  );

  test(
    'dispatch exposes only provider token and highest pending cursor',
    () async {
      await service.register('alice', _request(aliceDevice, 'token-one'));
      final blocked = Completer<void>();
      final firstDelivery = Completer<void>();
      final gateway = _RecordingGateway((delivery) async {
        if (!firstDelivery.isCompleted) firstDelivery.complete();
        await blocked.future;
        return PlatformPushDeliveryResult.accepted;
      });
      final dispatcher = PlatformPushDispatcher(
        service: service,
        gateway: gateway,
      );

      dispatcher.enqueue(4, ['alice']);
      await firstDelivery.future;
      dispatcher.enqueue(5, ['alice']);
      dispatcher.enqueue(9, ['alice']);
      blocked.complete();
      await dispatcher.close();

      expect(gateway.deliveries, [
        const _Delivery(provider: 'apns', token: 'token-one', cursor: 4),
        const _Delivery(provider: 'apns', token: 'token-one', cursor: 9),
      ]);
    },
  );

  test('presentation is evaluated independently for each device', () async {
    final secondDevice = _enrollment(20);
    await accounts.enrollDevice('alice', secondDevice);
    await service.register(
      'alice',
      _request(
        aliceDevice,
        'muted-token',
        mutedConversationIds: const ['conversation-1'],
      ),
    );
    await service.register('alice', _request(secondDevice, 'unmuted-token'));
    final gateway = _RecordingGateway(
      (_) async => PlatformPushDeliveryResult.accepted,
    );
    final dispatcher = PlatformPushDispatcher(
      service: service,
      gateway: gateway,
    );

    dispatcher.enqueue(
      11,
      ['alice'],
      presentationConversationId: 'conversation-1',
      presentationUsernames: ['alice'],
    );
    await dispatcher.close();

    expect(
      gateway.deliveries.where((item) => item.token == 'muted-token').single,
      const _Delivery(provider: 'apns', token: 'muted-token', cursor: 11),
    );
    expect(
      gateway.deliveries.where((item) => item.token == 'unmuted-token').single,
      const _Delivery(
        provider: 'apns',
        token: 'unmuted-token',
        cursor: 11,
        present: true,
      ),
    );
  });

  test('non-recipient and receipt wakeups remain silent', () async {
    await service.register('alice', _request(aliceDevice, 'token-one'));
    final gateway = _RecordingGateway(
      (_) async => PlatformPushDeliveryResult.accepted,
    );
    final dispatcher = PlatformPushDispatcher(
      service: service,
      gateway: gateway,
    );

    dispatcher.enqueue(
      12,
      ['alice'],
      presentationConversationId: 'conversation-1',
      presentationUsernames: const [],
    );
    await dispatcher.close();

    expect(gateway.deliveries.single.present, isFalse);
  });

  test('invalid result cannot remove a concurrently refreshed token', () async {
    await service.register('alice', _request(aliceDevice, 'token-old'));
    final gateway = _RecordingGateway((delivery) async {
      await service.register('alice', _request(aliceDevice, 'token-new'));
      return PlatformPushDeliveryResult.invalidToken;
    });
    final dispatcher = PlatformPushDispatcher(
      service: service,
      gateway: gateway,
    );

    dispatcher.enqueue(7, ['alice']);
    await dispatcher.close();

    final remaining = await subscriptions.listForUsernames(['alice']);
    expect(remaining.single.token, 'token-new');
  });

  test('invalid current token is retired', () async {
    await service.register('alice', _request(aliceDevice, 'token-old'));
    final dispatcher = PlatformPushDispatcher(
      service: service,
      gateway: _RecordingGateway(
        (_) async => PlatformPushDeliveryResult.invalidToken,
      ),
    );

    dispatcher.enqueue(7, ['alice']);
    await dispatcher.close();

    expect(await subscriptions.listForUsernames(['alice']), isEmpty);
  });

  test('provider timeout fails closed without blocking shutdown', () async {
    await service.register('alice', _request(aliceDevice, 'token-one'));
    final dispatcher = PlatformPushDispatcher(
      service: service,
      gateway: _RecordingGateway(
        (_) => Completer<PlatformPushDeliveryResult>().future,
      ),
      deliveryTimeout: const Duration(milliseconds: 20),
    );

    dispatcher.enqueue(8, ['alice']);
    await dispatcher.close().timeout(const Duration(seconds: 1));

    expect(await subscriptions.listForUsernames(['alice']), hasLength(1));
  });

  test(
    'reports retryable delivery failures without exposing context',
    () async {
      await service.register('alice', _request(aliceDevice, 'token-one'));
      final failures = <PlatformPushDispatchFailure>[];
      final dispatcher = PlatformPushDispatcher(
        service: service,
        gateway: _RecordingGateway(
          (_) async => PlatformPushDeliveryResult.retryableFailure,
        ),
        onBackgroundFailure: failures.add,
      );

      dispatcher.enqueue(8, ['alice']);
      await dispatcher.close();

      expect(failures, [PlatformPushDispatchFailure.delivery]);
    },
  );

  test(
    'bounded queue drops excess accounts without affecting delivery',
    () async {
      final bobDevice = _enrollment(20);
      await accounts.enrollDevice('bob', bobDevice);
      await service.register('alice', _request(aliceDevice, 'alice-token'));
      await service.register('bob', _request(bobDevice, 'bob-token'));
      final blocked = Completer<void>();
      final firstDelivery = Completer<void>();
      final gateway = _RecordingGateway((delivery) async {
        if (!firstDelivery.isCompleted) firstDelivery.complete();
        await blocked.future;
        return PlatformPushDeliveryResult.accepted;
      });
      final dispatcher = PlatformPushDispatcher(
        service: service,
        gateway: gateway,
        maxPendingAccounts: 1,
      );

      dispatcher.enqueue(1, ['alice']);
      await firstDelivery.future;
      dispatcher.enqueue(2, ['alice', 'bob']);
      blocked.complete();
      await dispatcher.close();

      expect(gateway.deliveries.map((item) => item.token), [
        'alice-token',
        'alice-token',
      ]);
    },
  );
}

final class _RecordingGateway implements PlatformPushGateway {
  _RecordingGateway(this.handler);

  final Future<PlatformPushDeliveryResult> Function(_Delivery delivery) handler;
  final List<_Delivery> deliveries = <_Delivery>[];

  @override
  Set<String> get providers => const {'apns'};

  @override
  Future<void> close() async {}

  @override
  Future<PlatformPushDeliveryResult> deliver({
    required String provider,
    required String token,
    required int cursor,
    bool present = false,
  }) {
    final delivery = _Delivery(
      provider: provider,
      token: token,
      cursor: cursor,
      present: present,
    );
    deliveries.add(delivery);
    return handler(delivery);
  }
}

final class _Delivery {
  const _Delivery({
    required this.provider,
    required this.token,
    required this.cursor,
    this.present = false,
  });

  final String provider;
  final String token;
  final int cursor;
  final bool present;

  @override
  bool operator ==(Object other) =>
      other is _Delivery &&
      provider == other.provider &&
      token == other.token &&
      cursor == other.cursor &&
      present == other.present;

  @override
  int get hashCode => Object.hash(provider, token, cursor, present);
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

PlatformPushSubscriptionRequest _request(
  DeviceEnrollment device,
  String token, {
  Iterable<String> mutedConversationIds = const [],
}) => PlatformPushSubscriptionRequest(
  deviceId: device.deviceId,
  provider: 'apns',
  token: token,
  mutedConversationIds: mutedConversationIds,
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

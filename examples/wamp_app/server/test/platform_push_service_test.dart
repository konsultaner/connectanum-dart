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

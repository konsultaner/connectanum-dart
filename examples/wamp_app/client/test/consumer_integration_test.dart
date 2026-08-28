import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';
import 'package:wamp_app/src/infrastructure/device_vault.dart';
import 'package:wamp_app/src/infrastructure/local_device_identity.dart';
import 'package:wamp_app/src/infrastructure/vault_storage.dart';
import 'package:wamp_app/src/infrastructure/wamp_account_gateway.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  test(
    'consumer controller provisions SCRAM and encrypted device trust',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'wamp-app-consumer-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final accountFile = File('${temporary.path}/accounts.json');
      final server = await WampAppServer.start(
        WampAppServerConfig(
          host: '127.0.0.1',
          port: 0,
          websocketPath: '/ws',
          accountStorePath: accountFile.path,
          messageStorePath: '${temporary.path}/messages.json',
          argonIterations: 1,
          argonMemoryKiB: 8192,
        ),
      );
      addTearDown(server.close);
      final storage = _MemoryVaultStorage();
      final controller = WampAppController(
        trustStore: EncryptedDeviceVault(
          storage: storage,
          keyDeriver: const _TestKeyDeriver(),
          iterations: 1,
          memoryKiB: 64,
        ),
        deviceName: 'Consumer integration device',
      );
      addTearDown(controller.dispose);

      await controller.registerAndConnect(
        serverAddress: server.websocketUri.toString(),
        username: 'alice',
        displayName: 'Alice Example',
        password: 'correct horse battery',
      );

      expect(controller.status, WampAppStatus.connected);
      expect(controller.connection?.username, 'alice');
      expect(controller.localDevice?.username, 'alice');
      expect(
        controller.localDevice?.enrollment.deviceName,
        'Consumer integration device',
      );
      expect(controller.safetyNumber, isNotEmpty);
      expect(storage.values.values.single, contains('ciphertext'));

      await expectLater(
        controller.connection!.registerPlatformPush(
          PlatformPushSubscriptionRequest(
            deviceId: controller.localDevice!.enrollment.deviceId,
            provider: 'test-provider',
            token: 'unconfigured-provider-token',
          ),
        ),
        throwsA(
          isA<PlatformPushSubscriptionException>().having(
            (error) => error.kind,
            'kind',
            PlatformPushSubscriptionFailureKind.retryable,
          ),
        ),
      );

      final accountDocument = await accountFile.readAsString();
      expect(accountDocument, contains('signing_public_key'));
      expect(accountDocument, contains('exchange_public_key'));
      expect(accountDocument, isNot(contains('correct horse battery')));
      expect(accountDocument, isNot(contains('signing_seed')));
      expect(accountDocument, isNot(contains('exchange_private_key')));

      await controller.signOut();
      expect(controller.status, WampAppStatus.signedOut);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'participants receive durable wakeups while unrelated users are excluded',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'wamp-app-message-consumer-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final server = await WampAppServer.start(
        WampAppServerConfig(
          host: '127.0.0.1',
          port: 0,
          websocketPath: '/ws',
          accountStorePath: '${temporary.path}/accounts.json',
          messageStorePath: '${temporary.path}/messages.json',
          argonIterations: 1,
          argonMemoryKiB: 8192,
        ),
      );
      addTearDown(server.close);
      final aliceStorage = _MemoryVaultStorage();
      final bobStorage = _MemoryVaultStorage();
      final carolStorage = _MemoryVaultStorage();
      final malloryStorage = _MemoryVaultStorage();
      final alice = _controller(aliceStorage, 'Alice phone');
      var bob = _controller(bobStorage, 'Bob phone');
      final carol = _controller(carolStorage, 'Carol phone');
      final mallory = _controller(malloryStorage, 'Mallory phone');
      addTearDown(alice.dispose);
      addTearDown(() => bob.dispose());
      addTearDown(carol.dispose);
      addTearDown(mallory.dispose);

      await alice.registerAndConnect(
        serverAddress: server.websocketUri.toString(),
        username: 'alice',
        displayName: 'Alice Example',
        password: 'alice secret phrase',
      );
      await bob.registerAndConnect(
        serverAddress: server.websocketUri.toString(),
        username: 'bob',
        displayName: 'Bob Example',
        password: 'bob secret phrase',
      );
      await carol.registerAndConnect(
        serverAddress: server.websocketUri.toString(),
        username: 'carol',
        displayName: 'Carol Example',
        password: 'carol secret phrase',
      );
      await mallory.registerAndConnect(
        serverAddress: server.websocketUri.toString(),
        username: 'mallory',
        displayName: 'Mallory Example',
        password: 'mallory secret phrase',
      );
      var unrelatedWakeups = 0;
      final unrelatedSubscription = mallory.connection!.mailboxWakeups.listen(
        (_) => unrelatedWakeups += 1,
      );
      addTearDown(unrelatedSubscription.cancel);

      const plaintext = 'Meet at the encrypted mailbox.';
      await alice.sendMessage(recipientUsername: 'bob', text: plaintext);
      expect(alice.messageError, isNull);
      expect(alice.messages.single.text, plaintext);
      expect(alice.messages.single.outgoing, isTrue);

      await _waitFor(() => bob.messages.isNotEmpty && !bob.messageBusy);
      expect(bob.messages.single.text, plaintext);
      expect(bob.messages.single.outgoing, isFalse);
      await _waitFor(
        () =>
            alice.messages.length == 1 &&
            alice.messages.single.deliveredAt != null &&
            !alice.messageBusy,
      );
      expect(alice.messages.single.deliveredAt, isNotNull);
      final durableMessageId = alice.messages.single.messageId;
      await bob.markMessageRead(durableMessageId);
      await _waitFor(
        () =>
            alice.messages
                .where((message) => message.messageId == durableMessageId)
                .single
                .readAt !=
            null,
      );

      const oneTimePlaintext = 'This message may only be opened once.';
      await alice.sendMessage(
        recipientUsername: 'bob',
        text: oneTimePlaintext,
        oneTime: true,
        expiresAfter: const Duration(hours: 1),
      );
      expect(alice.messageError, isNull);
      final oneTimeMessage = alice.messages.singleWhere(
        (message) => message.oneTime,
      );
      await _waitFor(
        () =>
            bob.messages.any(
              (message) => message.messageId == oneTimeMessage.messageId,
            ) &&
            !bob.messageBusy,
      );
      final revealed = await bob.consumeOneTimeMessage(
        oneTimeMessage.messageId,
      );
      expect(revealed, oneTimePlaintext);
      expect(
        bob.messages.any(
          (message) => message.messageId == oneTimeMessage.messageId,
        ),
        isFalse,
      );
      await _waitFor(
        () =>
            alice.messages
                .singleWhere(
                  (message) => message.messageId == oneTimeMessage.messageId,
                )
                .readAt !=
            null,
      );

      final group = await alice.createGroup(
        title: 'Launch crew',
        memberUsernames: const ['bob', 'carol'],
      );
      expect(group, isNotNull);
      const groupPlaintext = 'The whole group receives one ciphertext.';
      await alice.sendGroupMessage(
        groupId: group!.conversationId,
        text: groupPlaintext,
      );
      expect(alice.messageError, isNull);
      final groupMessage = alice.messages.singleWhere(
        (message) => message.conversationId == group.conversationId,
      );
      await _waitFor(
        () =>
            bob.messages.any(
              (message) => message.messageId == groupMessage.messageId,
            ) &&
            carol.messages.any(
              (message) => message.messageId == groupMessage.messageId,
            ) &&
            !bob.messageBusy &&
            !carol.messageBusy,
      );
      expect(bob.groups.single.hasSameDefinition(group), isTrue);
      expect(carol.groups.single.hasSameDefinition(group), isTrue);
      expect(
        bob.messages
            .singleWhere(
              (message) => message.messageId == groupMessage.messageId,
            )
            .text,
        groupPlaintext,
      );
      const groupReplyPlaintext = 'A discovered group member can reply.';
      expect(
        await bob.sendGroupMessage(
          groupId: group.conversationId,
          text: groupReplyPlaintext,
        ),
        isTrue,
        reason: '${bob.messageError}',
      );
      expect(bob.messageError, isNull);
      final groupReply = bob.messages.singleWhere(
        (message) =>
            message.conversationId == group.conversationId &&
            message.text == groupReplyPlaintext,
      );
      await _waitFor(
        () =>
            alice.messages.any(
              (message) => message.messageId == groupReply.messageId,
            ) &&
            carol.messages.any(
              (message) => message.messageId == groupReply.messageId,
            ) &&
            !alice.messageBusy &&
            !carol.messageBusy,
      );
      await _waitFor(
        () =>
            alice.messages
                .singleWhere(
                  (message) => message.messageId == groupMessage.messageId,
                )
                .deliveredAt !=
            null,
      );
      await bob.markMessageRead(groupMessage.messageId);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        alice.messages
            .singleWhere(
              (message) => message.messageId == groupMessage.messageId,
            )
            .readAt,
        isNull,
      );
      await carol.markMessageRead(groupMessage.messageId);
      await _waitFor(
        () =>
            alice.messages
                .singleWhere(
                  (message) => message.messageId == groupMessage.messageId,
                )
                .readAt !=
            null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(unrelatedWakeups, 0);
      expect(mallory.messages, isEmpty);

      final mailboxDocument = await File('${temporary.path}/messages.json')
          .readAsString();
      expect(mailboxDocument, isNot(contains(plaintext)));
      expect(mailboxDocument, isNot(contains(oneTimePlaintext)));
      expect(mailboxDocument, isNot(contains(groupPlaintext)));
      expect(mailboxDocument, isNot(contains(groupReplyPlaintext)));
      expect(mailboxDocument, isNot(contains('Launch crew')));
      expect(mailboxDocument, contains('encrypted_payload'));
      expect(mailboxDocument, contains('consumed_by_device_id'));

      await _waitFor(() => !bob.messageBusy && bob.messages.length == 3);
      await bob.signOut();
      bob.dispose();
      bob = _controller(bobStorage, 'Bob phone');
      await bob.login(
        serverAddress: server.websocketUri.toString(),
        username: 'bob',
        password: 'bob secret phrase',
      );
      expect(
        bob.status,
        WampAppStatus.connected,
        reason: '${bob.errorMessage} / ${bob.messageError}',
      );
      expect(bob.messages, hasLength(3));
      expect(
        bob.messages.any((message) => message.messageId == durableMessageId),
        isTrue,
      );
      expect(
        bob.messages.any(
          (message) =>
              message.messageId == groupMessage.messageId &&
              message.text == groupPlaintext,
        ),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'caller-bound push registration delivers cursor-only mailbox wakeups',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'wamp-app-push-consumer-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final gateway = _RecordingPushGateway();
      final server = await WampAppServer.start(
        WampAppServerConfig(
          host: '127.0.0.1',
          port: 0,
          websocketPath: '/ws',
          accountStorePath: '${temporary.path}/accounts.json',
          messageStorePath: '${temporary.path}/messages.json',
          pushStorePath: '${temporary.path}/push.json',
          argonIterations: 1,
          argonMemoryKiB: 8192,
        ),
        pushGateway: gateway,
      );
      addTearDown(server.close);
      final alice = _controller(_MemoryVaultStorage(), 'Alice phone');
      final bob = _controller(_MemoryVaultStorage(), 'Bob phone');
      addTearDown(alice.dispose);
      addTearDown(bob.dispose);

      await alice.registerAndConnect(
        serverAddress: server.websocketUri.toString(),
        username: 'alice',
        displayName: 'Alice Example',
        password: 'alice push secret',
      );
      await bob.registerAndConnect(
        serverAddress: server.websocketUri.toString(),
        username: 'bob',
        displayName: 'Bob Example',
        password: 'bob push secret',
      );
      final aliceDevice = alice.localDevice!.enrollment.deviceId;
      final bobDevice = bob.localDevice!.enrollment.deviceId;
      final aliceReceipt = await alice.connection!.registerPlatformPush(
        PlatformPushSubscriptionRequest(
          deviceId: aliceDevice,
          provider: 'test-provider',
          token: 'alice-opaque-token',
        ),
      );
      await bob.connection!.registerPlatformPush(
        PlatformPushSubscriptionRequest(
          deviceId: bobDevice,
          provider: 'test-provider',
          token: 'bob-opaque-token',
        ),
      );
      expect(aliceReceipt.deviceId, aliceDevice);
      expect(
        await alice.connection!.unregisterPlatformPush(
          PlatformPushSubscriptionKey(
            deviceId: aliceDevice,
            provider: 'test-provider',
          ),
        ),
        isTrue,
      );
      await alice.connection!.registerPlatformPush(
        PlatformPushSubscriptionRequest(
          deviceId: aliceDevice,
          provider: 'test-provider',
          token: 'alice-opaque-token',
        ),
      );

      await alice.sendMessage(recipientUsername: 'bob', text: 'push probe');
      await _waitFor(
        () =>
            gateway.deliveries.any(
              (delivery) => delivery.token == 'alice-opaque-token',
            ) &&
            gateway.deliveries.any(
              (delivery) => delivery.token == 'bob-opaque-token',
            ),
      );
      await _waitFor(
        () => bob.messages.isNotEmpty && !alice.messageBusy && !bob.messageBusy,
      );

      expect(
        gateway.deliveries.every(
          (delivery) => delivery.provider == 'test-provider',
        ),
        isTrue,
      );
      expect(
        gateway.deliveries.every((delivery) => delivery.cursor > 0),
        isTrue,
      );
      expect(
        gateway.deliveries
            .where((delivery) => delivery.token == 'alice-opaque-token')
            .every((delivery) => !delivery.present),
        isTrue,
      );
      expect(
        gateway.deliveries.any(
          (delivery) =>
              delivery.token == 'bob-opaque-token' && delivery.present,
        ),
        isTrue,
      );
      await expectLater(
        alice.connection!.registerPlatformPush(
          PlatformPushSubscriptionRequest(
            deviceId: aliceDevice,
            provider: 'unsupported-provider',
            token: 'unsupported-token',
          ),
        ),
        throwsA(
          isA<PlatformPushSubscriptionException>().having(
            (error) => error.kind,
            'kind',
            PlatformPushSubscriptionFailureKind.rejected,
          ),
        ),
      );
      var pushDocument = await File('${temporary.path}/push.json')
          .readAsString();
      expect(pushDocument, contains('alice-opaque-token'));
      expect(pushDocument, isNot(contains('push probe')));

      gateway.deliveries.clear();
      await alice.signOut();
      await alice.login(
        serverAddress: server.websocketUri.toString(),
        username: 'alice',
        password: 'alice push secret',
      );
      await alice.sendMessage(
        recipientUsername: 'bob',
        text: 'reconnect push probe',
      );
      await _waitFor(
        () => gateway.deliveries.any(
          (delivery) => delivery.token == 'alice-opaque-token',
        ),
      );
      await _waitFor(
        () =>
            bob.messages.length >= 2 && !alice.messageBusy && !bob.messageBusy,
      );

      await alice.connection!.revokeDevice(aliceDevice);
      await expectLater(
        alice.connection!.registerPlatformPush(
          PlatformPushSubscriptionRequest(
            deviceId: aliceDevice,
            provider: 'test-provider',
            token: 'replacement-token',
          ),
        ),
        throwsA(
          isA<PlatformPushSubscriptionException>().having(
            (error) => error.kind,
            'kind',
            PlatformPushSubscriptionFailureKind.rejected,
          ),
        ),
      );
      pushDocument = await File('${temporary.path}/push.json').readAsString();
      expect(pushDocument, isNot(contains('alice-opaque-token')));
      await server.close();
      expect(gateway.closed, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'typed WAMP calling signals stay encrypted and replay after reconnect',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'wamp-app-call-consumer-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final server = await WampAppServer.start(
        WampAppServerConfig(
          host: '127.0.0.1',
          port: 0,
          websocketPath: '/ws',
          accountStorePath: '${temporary.path}/accounts.json',
          messageStorePath: '${temporary.path}/messages.json',
          callStorePath: '${temporary.path}/calls.json',
          argonIterations: 1,
          argonMemoryKiB: 8192,
        ),
      );
      addTearDown(server.close);
      final endpoint = ServerEndpoint.parse(server.websocketUri.toString());
      final gateway = WampAccountGateway(
        connectionTimeout: const Duration(seconds: 15),
        derivationTimeout: const Duration(seconds: 30),
      );
      await gateway.register(
        endpoint: endpoint,
        registration: AccountRegistration(
          username: 'alice',
          displayName: 'Alice',
          password: 'alice call secret',
        ),
      );
      await gateway.register(
        endpoint: endpoint,
        registration: AccountRegistration(
          username: 'bob',
          displayName: 'Bob',
          password: 'bob call secret',
        ),
      );
      final aliceIdentity = LocalDeviceIdentity.generate(
        deviceName: 'Alice phone',
        now: DateTime.utc(2026, 8, 25, 10),
      );
      final bobIdentity = LocalDeviceIdentity.generate(
        deviceName: 'Bob phone',
        now: DateTime.utc(2026, 8, 25, 10),
      );
      addTearDown(aliceIdentity.dispose);
      addTearDown(bobIdentity.dispose);
      final alice = await gateway.login(
        endpoint: endpoint,
        username: 'alice',
        password: 'alice call secret',
      );
      var bob = await gateway.login(
        endpoint: endpoint,
        username: 'bob',
        password: 'bob call secret',
      );
      addTearDown(alice.close);
      addTearDown(() => bob.close());
      final aliceRecord = await alice.enrollDevice(
        aliceIdentity.enrollment('alice'),
      );
      final bobRecord = await bob.enrollDevice(bobIdentity.enrollment('bob'));
      expect((await alice.getCallConfiguration()).iceServers, isEmpty);

      final callId = _callToken(16, 71);
      final offerPlaintext = Uint8List.fromList(
        utf8.encode('{"type":"offer","sdp":"private offer"}'),
      );
      final offer = aliceIdentity.sealCallSignal(
        username: 'alice',
        callId: callId,
        signalId: _callToken(16, 72),
        kind: CallSignalKind.offer,
        recipient: bobRecord,
        plaintext: offerPlaintext,
      );
      final bobWakeup = bob.callWakeups.first.timeout(
        const Duration(seconds: 5),
      );
      final started = await alice.startCall(
        CallStartRequest(
          media: CallMediaKind.video,
          calleeUsername: 'bob',
          offers: [offer],
        ),
      );
      expect((await bobWakeup).cursor, started.cursor);
      final incoming = await bob.syncCalls(
        deviceId: bobRecord.deviceId,
        afterCursor: 0,
      );
      final openedOffer = bobIdentity.openCallSignal(
        username: 'bob',
        signal: incoming.updates.single.signals.single,
        sender: aliceRecord,
      );
      expect(utf8.decode(openedOffer), contains('private offer'));
      openedOffer.fillRange(0, openedOffer.length, 0);

      final answer = bobIdentity.sealCallSignal(
        username: 'bob',
        callId: callId,
        signalId: _callToken(16, 73),
        kind: CallSignalKind.answer,
        recipient: aliceRecord,
        plaintext: Uint8List.fromList(
          utf8.encode('{"type":"answer","sdp":"private answer"}'),
        ),
      );
      final accepted = await bob.acceptCall(answer);
      expect(accepted.call.state, CallState.active);
      expect(accepted.call.acceptedDeviceId, bobRecord.deviceId);

      final candidate = aliceIdentity.sealCallSignal(
        username: 'alice',
        callId: callId,
        signalId: _callToken(16, 74),
        kind: CallSignalKind.iceCandidate,
        recipient: bobRecord,
        plaintext: Uint8List.fromList(
          utf8.encode('{"candidate":"private candidate"}'),
        ),
      );
      await alice.sendCallSignal(candidate);
      await bob.close();
      bob = await gateway.login(
        endpoint: endpoint,
        username: 'bob',
        password: 'bob call secret',
      );
      final replay = await bob.syncCalls(
        deviceId: bobRecord.deviceId,
        afterCursor: 0,
      );
      expect(replay.updates, hasLength(3));
      final replayedCandidate = replay.updates.last.signals.single;
      final openedCandidate = bobIdentity.openCallSignal(
        username: 'bob',
        signal: replayedCandidate,
        sender: aliceRecord,
      );
      expect(utf8.decode(openedCandidate), contains('private candidate'));
      openedCandidate.fillRange(0, openedCandidate.length, 0);

      final hangup = bobIdentity.sealCallSignal(
        username: 'bob',
        callId: callId,
        signalId: _callToken(16, 75),
        kind: CallSignalKind.hangup,
        recipient: aliceRecord,
        plaintext: Uint8List.fromList(utf8.encode('{"reason":"local"}')),
      );
      expect((await bob.endCall(hangup)).call.state, CallState.ended);
      expect(
        await File('${temporary.path}/calls.json').readAsString(),
        isNot(contains('private offer')),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Consumer state was not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

WampAppController _controller(_MemoryVaultStorage storage, String deviceName) {
  return WampAppController(
    trustStore: EncryptedDeviceVault(
      storage: storage,
      keyDeriver: const _TestKeyDeriver(),
      iterations: 1,
      memoryKiB: 64,
    ),
    deviceName: deviceName,
  );
}

String _callToken(int bytes, int seed) => base64Url
    .encode(List<int>.generate(bytes, (index) => (index + seed) % 256))
    .replaceAll('=', '');

final class _MemoryVaultStorage implements VaultStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

final class _TestKeyDeriver implements VaultKeyDeriver {
  const _TestKeyDeriver();

  @override
  Future<Uint8List> derive({
    required String password,
    required String salt,
    required int iterations,
    required int memoryKiB,
    required Duration timeout,
  }) async {
    return Uint8List.fromList(
      sha256.convert(utf8.encode('$password\n$salt')).bytes,
    );
  }
}

final class _RecordingPushGateway implements PlatformPushGateway {
  final List<_PushDelivery> deliveries = <_PushDelivery>[];
  bool closed = false;

  @override
  Set<String> get providers => const {'test-provider'};

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<PlatformPushDeliveryResult> deliver({
    required String provider,
    required String token,
    required int cursor,
    bool present = false,
  }) async {
    deliveries.add(
      _PushDelivery(
        provider: provider,
        token: token,
        cursor: cursor,
        present: present,
      ),
    );
    return PlatformPushDeliveryResult.accepted;
  }
}

final class _PushDelivery {
  const _PushDelivery({
    required this.provider,
    required this.token,
    required this.cursor,
    required this.present,
  });

  final String provider;
  final String token;
  final int cursor;
  final bool present;
}

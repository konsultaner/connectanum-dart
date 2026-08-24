import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';
import 'package:wamp_app/src/infrastructure/device_vault.dart';
import 'package:wamp_app/src/infrastructure/vault_storage.dart';
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
      final malloryStorage = _MemoryVaultStorage();
      final alice = _controller(aliceStorage, 'Alice phone');
      var bob = _controller(bobStorage, 'Bob phone');
      final mallory = _controller(malloryStorage, 'Mallory phone');
      addTearDown(alice.dispose);
      addTearDown(() => bob.dispose());
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
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(unrelatedWakeups, 0);
      expect(mallory.messages, isEmpty);

      final mailboxDocument = await File('${temporary.path}/messages.json')
          .readAsString();
      expect(mailboxDocument, isNot(contains(plaintext)));
      expect(mailboxDocument, isNot(contains(oneTimePlaintext)));
      expect(mailboxDocument, contains('encrypted_payload'));
      expect(mailboxDocument, contains('consumed_by_device_id'));

      await bob.signOut();
      bob.dispose();
      bob = _controller(bobStorage, 'Bob phone');
      await bob.login(
        serverAddress: server.websocketUri.toString(),
        username: 'bob',
        password: 'bob secret phrase',
      );
      expect(bob.messages, hasLength(1));
      expect(bob.messages.single.messageId, durableMessageId);
      expect(bob.messages.single.text, plaintext);
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

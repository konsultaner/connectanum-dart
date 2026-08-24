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

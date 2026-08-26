import 'dart:convert';
import 'dart:math';

import 'package:connectanum_core/authentication.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'account_store.dart';

class RegistrationService {
  RegistrationService({
    required this.store,
    this.iterations = 3,
    this.memoryKiB = 65536,
    Random? random,
  }) : _random = random ?? Random.secure();

  final AccountStore store;
  final int iterations;
  final int memoryKiB;
  final Random _random;

  Future<RegistrationReceipt> register(AccountRegistration registration) async {
    registration.validate();
    if (await store.find(registration.username) != null) {
      throw AccountAlreadyExists(registration.username);
    }

    final saltBytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final salt = base64.encode(saltBytes);
    final secrets = await ScramAuthentication.deriveServerSecretsAsync(
      secret: registration.password,
      salt: salt,
      kdf: ScramAuthentication.kdfArgon,
      iterations: iterations,
      memory: memoryKiB,
      timeout: const Duration(seconds: 60),
    );
    final createdAt = DateTime.now().toUtc();
    await store.create(
      StoredAccount(
        username: registration.username,
        displayName: registration.displayName,
        storedKey: secrets.storedKey,
        serverKey: secrets.serverKey,
        salt: salt,
        iterations: iterations,
        memoryKiB: memoryKiB,
        kdf: ScramAuthentication.kdfArgon,
        createdAt: createdAt,
      ),
    );
    return RegistrationReceipt(
      username: registration.username,
      displayName: registration.displayName,
      createdAt: createdAt,
    );
  }
}

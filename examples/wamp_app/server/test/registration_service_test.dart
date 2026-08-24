import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  test(
    'derives and stores SCRAM verifier without retaining password',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'wamp-app-register-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final store = AccountStore('${temporary.path}/accounts.json');
      await store.initialize();
      final service = RegistrationService(
        store: store,
        iterations: 1,
        memoryKiB: 8192,
        random: Random(7),
      );

      final receipt = await service.register(
        AccountRegistration(
          username: 'alice',
          password: 'correct horse battery staple',
          displayName: 'Alice',
        ),
      );

      final account = await store.find('alice');
      expect(receipt.username, 'alice');
      expect(account?.kdf, 'argon2id13');
      expect(account?.memoryKiB, 8192);
      expect(account?.storedKey, isNotEmpty);
      expect(account?.serverKey, isNotEmpty);
      expect(
        await store.file.readAsString(),
        isNot(contains('correct horse battery staple')),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'concurrent registration of one username has exactly one winner',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'wamp-app-register-race-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final store = AccountStore('${temporary.path}/accounts.json');
      await store.initialize();
      final service = RegistrationService(
        store: store,
        iterations: 1,
        memoryKiB: 8192,
        random: Random(11),
      );
      final request = AccountRegistration(
        username: 'alice',
        password: 'correct horse battery staple',
        displayName: 'Alice',
      );

      Future<String> attempt() async {
        try {
          await service.register(request);
          return 'created';
        } on AccountAlreadyExists {
          return 'duplicate';
        }
      }

      final outcomes = await Future.wait([attempt(), attempt()]);

      expect(outcomes, unorderedEquals(['created', 'duplicate']));
      expect(await store.find('alice'), isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

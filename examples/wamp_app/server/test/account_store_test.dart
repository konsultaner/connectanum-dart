import 'dart:io';

import 'package:test/test.dart';
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
}

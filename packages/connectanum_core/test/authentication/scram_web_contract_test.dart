@TestOn('browser')
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

const _user = 'user';
const _clientNonce = 'rOprNGfwEbeRWgbNEkqO';
const _serverNonce = 'rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF\$k0';

Extra _challenge({String nonce = _serverNonce}) => Extra(
  iterations: 4096,
  memory: 100,
  salt: 'W22ZaJ0SNY7soEsUEjb6gQ==',
  nonce: nonce,
  kdf: ScramAuthentication.kdfArgon,
);

HashMap<String, Object?> _authExtra() => HashMap<String, Object?>.from({
  'nonce': _serverNonce,
  'channel_binding': null,
});

void main() {
  for (final (label, password, encoding, proof) in [
    (
      'ASCII',
      'pencil',
      AuthenticationStringEncoding.utf8,
      'b8qnNPK25OveSr9H7LVV1tcZqyICZe2DLammvNEDJwg=',
    ),
    (
      'UTF-8',
      'Stra\u00dfe',
      AuthenticationStringEncoding.utf8,
      'j1eU8k4NK9CglyQSc4X0ZsVj2Jr9o8AfJrD3zwR8+pg=',
    ),
    (
      'UTF-16 compatibility',
      'Stra\u00dfe',
      AuthenticationStringEncoding.utf16,
      'h1krogHvNHm3PelExNS1M+4Yf5L0yRNZyAGocLyHfUo=',
    ),
  ]) {
    test(
      'rejects synchronous Argon2 for $label without completing a key',
      () async {
        final auth = ScramAuthentication(password, stringEncoding: encoding);
        addTearDown(auth.dispose);
        var keyCompleted = false;
        unawaited(auth.clientKey.then<void>((_) => keyCompleted = true));
        expect(
          () => auth.createSignature(
            _user,
            _clientNonce,
            _challenge(),
            _authExtra(),
          ),
          throwsA(isA<UnsupportedError>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(keyCompleted, isFalse);
      },
    );

    test('worker-backed Argon2 preserves the existing $label proof', () async {
      final actual = await ScramAuthentication.generateProofAsync(
        secret: password,
        authId: _user,
        clientNonce: _clientNonce,
        authExtra: _authExtra(),
        challenge: _challenge(),
        stringEncoding: encoding,
      );
      expect(actual, proof);
    });
  }

  test(
    'worker-derived client and server keys can be reused with their binding',
    () async {
      final auth = ScramAuthentication('pencil');
      addTearDown(auth.dispose);
      await auth.hello('com.realm', Details.forHello()..authid = _user);
      final response = await auth.challenge(
        _challenge(nonce: '${auth.helloNonce!}server'),
      );
      expect(response.signature, isNotEmpty);
      final clientKey = await auth.clientKey;
      addTearDown(() => clientKey.fillRange(0, clientKey.length, 0));
      final challenge = _challenge();
      final secrets = await ScramAuthentication.deriveServerSecretsAsync(
        secret: 'pencil',
        salt: challenge.salt!,
        kdf: challenge.kdf!,
        iterations: challenge.iterations!,
        memory: challenge.memory,
      );
      final serverKey = base64.decode(secrets.serverKey);
      addTearDown(() => serverKey.fillRange(0, serverKey.length, 0));
      final cached = ScramAuthentication.fromClientKey(
        clientKey,
        serverKey: serverKey,
        binding: ScramKeyCacheBinding(
          authId: _user,
          salt: challenge.salt!,
          kdf: challenge.kdf!,
          iterations: challenge.iterations!,
          memory: challenge.memory!,
        ),
      );
      addTearDown(cached.dispose);
      expect(
        cached.createSignature(_user, _clientNonce, challenge, _authExtra()),
        'b8qnNPK25OveSr9H7LVV1tcZqyICZe2DLammvNEDJwg=',
      );
    },
  );
}

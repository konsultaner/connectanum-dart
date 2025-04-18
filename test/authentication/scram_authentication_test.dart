import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:connectanum/connectanum.dart';
import 'package:connectanum/src/authentication/scram_authentication.dart';
import 'package:test/test.dart';

void main() {
  group('SCRAM', () {
    var user = 'user';
    var secret = 'pencil';
    var helloNonce = 'rOprNGfwEbeRWgbNEkqO';
    var signature = 'dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=';
    var signatureArgon = 'b8qnNPK25OveSr9H7LVV1tcZqyICZe2DLammvNEDJwg=';
    var challengeExtra = Extra(
        iterations: 4096,
        salt: 'W22ZaJ0SNY7soEsUEjb6gQ==',
        nonce: 'rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF\$k0',
        kdf: ScramAuthentication.kdfPbkdf2);
    var challengeExtraArgon2 = Extra(
        iterations: 4096,
        memory: 100,
        salt: 'W22ZaJ0SNY7soEsUEjb6gQ==',
        nonce: 'rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF\$k0',
        kdf: ScramAuthentication.kdfArgon);
    var authExtra = HashMap<String, Object?>();
    authExtra['nonce'] = challengeExtra.nonce;
    authExtra['channel_binding'] = null;

    test('hello init', () async {
      final authMethod = ScramAuthentication(secret,
          challengeTimeout: Duration(milliseconds: 20));
      expect(authMethod.getName(), equals('wamp-scram'));
      await authMethod.hello('com.realm', Details.forHello()..authid = user);
      expect(authMethod.authid, equals(user));
      expect(authMethod.secret, equals(secret));
      expect(authMethod.challengeTimeout.inMilliseconds, equals(20));
      expect(base64.decode(authMethod.helloNonce!).length, equals(16));
      await Future.delayed(Duration(milliseconds: 30));
      expect(authMethod.helloNonce, isNull);
    });
    test('challenge', () async {
      var challengeExtra2 = Extra(
          iterations: 4096,
          salt: 'W22ZaJ0SNY7soEsUEjb6gQ==',
          nonce: 'rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF\$k0',
          kdf: ScramAuthentication.kdfPbkdf2);
      final authMethod = ScramAuthentication(secret)
        ..hello('com.realm', Details.forHello()..authid = user);
      challengeExtra2.nonce = '${authMethod.helloNonce!}nonce';
      var authenticate = await authMethod.challenge(challengeExtra2);
      expect(authenticate.signature, isNotNull);
      expect(authenticate.extra!['nonce'],
          equals(challengeExtra2.nonce = '${authMethod.helloNonce!}nonce'));
      expect(authenticate.extra!['channel_binding'], isNull);
      expect(authenticate.extra!['cbind_data'], isNull);
    });
    test('timedout challenge', () async {
      final authMethod = ScramAuthentication(secret,
          challengeTimeout: Duration(milliseconds: 1))
        ..hello('com.realm', Details.forHello()..authid = user);
      await Future.delayed(Duration(milliseconds: 2));
      expect(() async => await authMethod.challenge(challengeExtra),
          throwsA(isA<Exception>()));
      expect(
          () async => await authMethod.challenge(challengeExtra),
          throwsA(predicate((dynamic exception) =>
              exception.toString() == 'Exception: Wrong nonce')));
    });
    test('challenge wrong kdf', () async {
      final authMethod = ScramAuthentication(secret)
        ..hello('com.realm', Details.forHello()..authid = user);
      var challengeExtra2 = Extra(
          iterations: 4096,
          salt: 'W22ZaJ0SNY7soEsUEjb6gQ==',
          nonce: '${authMethod.helloNonce!}TCAfuxFIlj)hNlF\$k0',
          kdf: 'other kdf');
      expect(() async => await authMethod.challenge(challengeExtra2),
          throwsA(isA<Exception>()));
      expect(
          () async => await authMethod.challenge(challengeExtra2),
          throwsA(predicate((dynamic exception) =>
              exception.toString() ==
              'Exception: not supported key derivation function used other kdf')));
    });
    test('derive key pbkdf2', () async {
      final authenticateSignature = ScramAuthentication(secret)
          .createSignature(user, helloNonce, challengeExtra, authExtra);
      expect(authenticateSignature, equals(signature));
    });
    test('derive key argon2id', () async {
      final authenticateSignature = ScramAuthentication(secret)
          .createSignature(user, helloNonce, challengeExtraArgon2, authExtra);
      expect(authenticateSignature, equals(signatureArgon));
    });
    test('reuse client key for authentication', () async {
      final authMethod = ScramAuthentication(secret);
      var authenticateSignature = authMethod.createSignature(
          user, helloNonce, challengeExtraArgon2, authExtra);
      var clientKey = await authMethod.clientKey;
      authenticateSignature = ScramAuthentication.fromClientKey(clientKey)
          .createSignature(user, helloNonce, challengeExtraArgon2, authExtra);
      expect(authenticateSignature, equals(signatureArgon));
    });
    test('verify key', () {
      var signature = 'dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=';
      var storedKey = 'WG5d8oPm3OtcPnkdi4Uo7BkeZkBFzpcXkuLmtbsT4qY=';
      var authMessage =
          'n=user,r=rOprNGfwEbeRWgbNEkqO,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF\$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096,c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF\$k0';

      var isVerified = ScramAuthentication.verifyClientProof(
          base64.decode(signature), base64.decode(storedKey), authMessage);
      expect(isVerified, equals(true));
    });
    test('on challenge event', () async {
      var challengeExtra2 = Extra(
          iterations: 4096,
          salt: 'W22ZaJ0SNY7soEsUEjb6gQ==',
          nonce: 'rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF\$k0',
          kdf: ScramAuthentication.kdfPbkdf2);
      final authMethod = ScramAuthentication(secret)
        ..hello('com.realm', Details.forHello()..authid = user);
      challengeExtra2.nonce = '${authMethod.helloNonce!}nonce';
      final completer = Completer<Extra>();
      authMethod.onChallenge.listen(
        (event) {
          completer.complete(event);
        },
      );
      authMethod.challenge(challengeExtra2);
      var receivedExtra = await completer.future;
      expect(receivedExtra, isNotNull);
      expect(receivedExtra.nonce, equals(challengeExtra2.nonce));
    });
  });
}

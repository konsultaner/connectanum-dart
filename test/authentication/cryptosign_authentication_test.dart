import 'dart:convert';
import 'dart:io';

import 'package:connectanum/src/authentication/cryptosign_authentication.dart';
import 'package:connectanum/src/message/challenge.dart';
import 'package:connectanum/src/message/details.dart';
import 'package:pinenacl/ed25519.dart';
import 'package:test/test.dart';

void main() {
  group('CRYPTOSIGN', () {
    var testVectors = [
      {
        'privateKey':
            '4d57d97a68f555696620a6d849c0ce582568518d729eb753dc7c732de2804510',
        'challenge': 'ff' * 32,
        'signature':
            'b32675b221f08593213737bef8240e7c15228b07028e19595294678c90d11c0cae80a357331bfc5cc9fb71081464e6e75013517c2cf067ad566a6b7b728e5d03ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
      },
      {
        'privateKey':
            'd511fe78e23934b3dadb52fcd022974b80bd92bccc7c5cf404e46cc0a8a2f5cd',
        'challenge':
            'b26c1f87c13fc1da14997f1b5a71995dff8fbe0a62fae8473c7bdbd05bfb607d',
        'signature':
            'd4209ad10d5aff6bfbc009d7e924795de138a63515efc7afc6b01b7fe5201372190374886a70207b042294af5bd64ce725cd8dceb344e6d11c09d1aaaf4d660fb26c1f87c13fc1da14997f1b5a71995dff8fbe0a62fae8473c7bdbd05bfb607d'
      },
      {
        'privateKey':
            '6e1fde9cf9e2359a87420b65a87dc0c66136e66945196ba2475990d8a0c3a25b',
        'challenge':
            'b05e6b8ad4d69abf74aa3be3c0ee40ae07d66e1895b9ab09285a2f1192d562d2',
        'signature':
            '7beb282184baadd08f166f16dd683b39cab53816ed81e6955def951cb2ddad1ec184e206746fd82bda075af03711d3d5658fc84a76196b0fa8d1ebc92ef9f30bb05e6b8ad4d69abf74aa3be3c0ee40ae07d66e1895b9ab09285a2f1192d562d2'
      }
    ];

    final puttySeed = [
      141,
      73,
      118,
      119,
      135,
      33,
      122,
      2,
      181,
      240,
      18,
      204,
      171,
      163,
      81,
      33,
      160,
      138,
      171,
      176,
      50,
      73,
      106,
      3,
      203,
      14,
      219,
      151,
      10,
      35,
      60,
      212
    ];
    final openSshSeed = [
      21,
      231,
      131,
      235,
      144,
      223,
      174,
      67,
      207,
      102,
      183,
      246,
      209,
      212,
      255,
      255,
      231,
      43,
      210,
      219,
      99,
      206,
      211,
      62,
      171,
      220,
      16,
      225,
      62,
      227,
      254,
      221
    ];

    test('message handling', () async {
      testVectors.forEach((vector) async {
        final authMethod =
            CryptosignAuthentication.fromHex(vector['privateKey']);
        expect(authMethod.getName(), equals('cryptosign'));

        var details = Details();
        await authMethod.hello('some.realm', details);

        expect(details.authextra!['pubkey'],
            equals(authMethod.privateKey.publicKey.encode(HexCoder.instance)));
        expect(details.authextra!['channel_binding'], equals(null));

        var extra =
            Extra(challenge: vector['challenge'], channel_binding: null);
        final authenticate = await authMethod.challenge(extra);
        expect(authenticate.signature, equals(vector['signature']));

        extra =
            Extra(challenge: vector['challenge'], channel_binding: 'sadjakf');
        expect(() => authMethod.challenge(extra), throwsA(isA<Exception>()));

        try {
          await authMethod.challenge(extra);
        } on Exception catch (error) {
          expect(error.toString(),
              equals('Exception: Channel Binding does not match'));
        }

        extra = Extra(
            challenge: vector['challenge']!.substring(3), channel_binding: null);
        expect(() => authMethod.challenge(extra), throwsA(isA<Exception>()));

        try {
          await authMethod.challenge(extra);
        } on Exception catch (error) {
          expect(error.toString(), equals('Exception: Wrong challenge length'));
        }
      });
    });

    test('load putty private key file', () async {
      var ppk = File('./test/authentication/ed25519.ppk');
      var ppkEncrypted = File('./test/authentication/ed25519_password.ppk');
      var ppkEncrypted2 = File('./test/authentication/ed25519_password2.ppk');
      final unencryptedPpkKey = CryptosignAuthentication.loadPrivateKeyFromPpk(
          await ppk.readAsString());
      final decryptedPpkKey = CryptosignAuthentication.loadPrivateKeyFromPpk(
          await ppkEncrypted.readAsString(),
          password: 'password');
      final decryptedPpkKey2 = CryptosignAuthentication.loadPrivateKeyFromPpk(
          await ppkEncrypted2.readAsString(),
          password: 'password2');
      expect(unencryptedPpkKey, equals(puttySeed));
      expect(decryptedPpkKey, equals(puttySeed));
      expect(decryptedPpkKey2, equals(puttySeed));

      var ppkOpenSsh = File('./test/authentication/ed25519_openssh.ppk');
      final unencryptedOpenSshPpkKey =
          CryptosignAuthentication.loadPrivateKeyFromPpk(
              await ppkOpenSsh.readAsString());
      expect(unencryptedOpenSshPpkKey, equals(openSshSeed));
    });

    test('putty key file errors', () async {
      var ppk = File('./test/authentication/ed25519.ppk');
      var ppkEncrypted = File('./test/authentication/ed25519_password.ppk');
      var puttyContent = await ppk.readAsString();
      var encryptedPuttyContent = await ppkEncrypted.readAsString();
      var emptyPrivateKey =
          'PuTTY-User-Key-File-2: ssh-ed25519\r\nEncryption: none\r\nComment: ed25519-key-20210211\r\nPublic-Lines: 0\r\nPrivate-Lines: 0';
      expect(() => CryptosignAuthentication.loadPrivateKeyFromPpk(''),
          throwsA(isA<Exception>()));
      expect(
          () => CryptosignAuthentication.loadPrivateKeyFromPpk(
              'PuTTY-User-Key-File-3'),
          throwsA(isA<Exception>()));
      expect(
          () => CryptosignAuthentication.loadPrivateKeyFromPpk(
              'PuTTY-User-Key-File-2: ssh-key'),
          throwsA(isA<Exception>()));
      expect(
          () => CryptosignAuthentication.loadPrivateKeyFromPpk(
              'PuTTY-User-Key-File-2: ssh-ed25519\r\nEncryption: ssh-ed25519-2'),
          throwsA(isA<Exception>()));
      expect(
          () => CryptosignAuthentication.loadPrivateKeyFromPpk(
              encryptedPuttyContent),
          throwsA(isA<Exception>()));
      expect(
          () => CryptosignAuthentication.loadPrivateKeyFromPpk(
              encryptedPuttyContent,
              password: ''),
          throwsA(isA<Exception>()));
      expect(
          () => CryptosignAuthentication.loadPrivateKeyFromPpk(
              encryptedPuttyContent,
              password: 'wrongPassword'),
          throwsA(isA<Exception>()));
      expect(
          () => CryptosignAuthentication.loadPrivateKeyFromPpk(
              puttyContent.replaceAll(RegExp(r'20210211'), '')),
          throwsA(isA<Exception>()));
      expect(
          () => CryptosignAuthentication.loadPrivateKeyFromPpk(emptyPrivateKey),
          throwsA(isA<Exception>()));
      expect(() => CryptosignAuthentication.loadPrivateKeyFromPpk(null),
          throwsA(isA<Exception>()));

      try {
        CryptosignAuthentication.loadPrivateKeyFromPpk('');
      } on Exception catch (error) {
        expect(error.toString(),
            equals('Exception: File is no valid putty ssh-2 key file!'));
      }

      try {
        CryptosignAuthentication.loadPrivateKeyFromPpk('PuTTY-User-Key-File-3');
      } on Exception catch (error) {
        expect(error.toString(),
            equals('Exception: Unsupported ssh-2 key file version!'));
      }

      try {
        CryptosignAuthentication.loadPrivateKeyFromPpk(
            'PuTTY-User-Key-File-2: ssh-key');
      } on Exception catch (error) {
        expect(
            error.toString(),
            equals(
                'Exception: The putty key has the wrong encryption method, use ssh-ed25519!'));
      }

      try {
        CryptosignAuthentication.loadPrivateKeyFromPpk(
            'PuTTY-User-Key-File-2: ssh-ed25519\r\nEncryption: ssh-ed25519-2');
      } on Exception catch (error) {
        expect(
            error.toString(),
            equals(
                'Exception: Unknown or unsupported putty file encryption! Supported values are "none" and "aes256-cbc"'));
      }

      try {
        CryptosignAuthentication.loadPrivateKeyFromPpk(encryptedPuttyContent);
      } on Exception catch (error) {
        expect(error.toString(),
            equals('Exception: No or empty password provided!'));
      }

      try {
        CryptosignAuthentication.loadPrivateKeyFromPpk(encryptedPuttyContent,
            password: '');
      } on Exception catch (error) {
        expect(error.toString(),
            equals('Exception: No or empty password provided!'));
      }

      try {
        CryptosignAuthentication.loadPrivateKeyFromPpk(encryptedPuttyContent,
            password: 'wrongPassword');
      } on Exception catch (error) {
        expect(error.toString(), equals('Exception: Wrong password!'));
      }

      try {
        CryptosignAuthentication.loadPrivateKeyFromPpk(
            puttyContent.replaceAll(RegExp(r'20210211'), ''));
      } on Exception catch (error) {
        expect(error.toString(),
            equals('Exception: Mac check failed, file is corrupt!'));
      }

      try {
        CryptosignAuthentication.loadPrivateKeyFromPpk(emptyPrivateKey);
      } on Exception catch (error) {
        expect(
            error.toString(),
            equals(
                'Exception: Wrong file format. Could not extract a private key'));
      }

      try {
        CryptosignAuthentication.loadPrivateKeyFromPpk(null);
      } on Exception catch (error) {
        expect(
            error.toString(),
            equals(
                'Exception: There is no file content provided to load a private key from!'));
      }
    });

    test('load open ssh private key', () async {
      var openSshKey = File('./test/authentication/ed25519.key');
      final unencryptedOpenSshKey =
          CryptosignAuthentication.loadPrivateKeyFromOpenSSHPem(
              await openSshKey.readAsString());
      expect(unencryptedOpenSshKey, equals(openSshSeed));

      var openSshPemFromPutty = File('./test/authentication/ed25519.pem');
      final unencryptedOpenSshKeyFromPutty =
          CryptosignAuthentication.loadPrivateKeyFromOpenSSHPem(
              await openSshPemFromPutty.readAsString());
      expect(unencryptedOpenSshKeyFromPutty, equals(puttySeed));

      var openSshPemFromPuttyWithPassword =
          File('./test/authentication/ed25519_password.pem');
      final unencryptedOpenSshKeyFromPuttyWithPassword =
          CryptosignAuthentication.loadPrivateKeyFromOpenSSHPem(
              await openSshPemFromPuttyWithPassword.readAsString(),
              password: 'password');
      expect(unencryptedOpenSshKeyFromPuttyWithPassword, equals(puttySeed));
    });

    test('constructors', () async {
      expect(
          () => CryptosignAuthentication(
              SigningKey.fromSeed(Uint8List.fromList([])), 'some other then null'),
          throwsA(isA<Exception>()));

      var ppkEncrypted = File('./test/authentication/ed25519_password.ppk');
      var ppkKey = CryptosignAuthentication.fromPuttyPrivateKey(
          await ppkEncrypted.readAsString(),
          password: 'password');

      expect(ppkKey.privateKey.sublist(0, 32).toString(),
          equals(puttySeed.toString()));

      var openSshPemFromPuttyWithPassword =
          File('./test/authentication/ed25519_password.pem');
      var opensshKey = CryptosignAuthentication.fromOpenSshPrivateKey(
          await openSshPemFromPuttyWithPassword.readAsString(),
          password: 'password');

      expect(opensshKey.privateKey.sublist(0, 32).toString(),
          equals(puttySeed.toString()));

      var base64Key =
          CryptosignAuthentication.fromBase64(base64.encode(puttySeed));
      expect(base64Key.privateKey.sublist(0, 32).toString(),
          equals(puttySeed.toString()));
    });
  });
}

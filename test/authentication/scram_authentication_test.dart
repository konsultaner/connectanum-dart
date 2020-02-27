import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum/src/authentication/cra_authentication.dart';
import 'package:connectanum/src/authentication/scram_authentication.dart';
import 'package:connectanum/src/message/authenticate.dart';
import 'package:connectanum/src/message/challenge.dart';
import 'package:test/test.dart';

void main() {
  group('SCRAM', () {
    String user = "user";
    String secret = "pencil";
    String helloNonce = "rOprNGfwEbeRWgbNEkqO";
    String signature = "dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=";
    Extra challengeExtra = Extra(
        iterations: 4096,
        salt: "W22ZaJ0SNY7soEsUEjb6gQ==",
        nonce: 'rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF\$k0',
        kdf: ScramAuthentication.KDF_PBKDF2);
    HashMap<String, Object> authExtra = HashMap();
    authExtra['nonce'] = challengeExtra.nonce;
    authExtra['channel_binding'] = null;

    test("derive key pbkdf2", () async {
      final authenticateSignature = ScramAuthentication(secret)
          .challengePBKDF2(user, helloNonce, challengeExtra, authExtra);
      expect(authenticateSignature, equals(signature));
    });
  });
}

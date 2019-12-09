import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_dart/src/authentication/abstract_authentication.dart';
import 'package:connectanum_dart/src/message/authenticate.dart';
import 'package:connectanum_dart/src/message/challenge.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/pointycastle.dart';

import '../message/challenge.dart';

class CraAuthentication extends AbstractAuthentication {
  static final Uint8List DEFAULT_KEY_SALT = new Uint8List(0);

  @override
  Future<Authenticate> challenge(Extra extra) {
    String secret;
    Authenticate authenticate = new Authenticate();
    if (extra == null || extra.challenge == null || secret == null) {
      // error
    }

    Uint8List key;
    if (extra.iterations != null && extra.iterations > 0) {
      key = deriveKey(
          secret, extra.salt == null ? DEFAULT_KEY_SALT : extra.salt,
          iterations: extra.iterations, keylen: extra.keylen);
    } else {
      key =
          deriveKey(secret, extra.salt == null ? DEFAULT_KEY_SALT : extra.salt);
    }

    authenticate.signature = encodeHmac(
        key, extra.keylen, Uint8List.fromList(extra.challenge.codeUnits));
    return Future.value(authenticate);
  }

  static Uint8List deriveKey(String secret, String salt,
      {int iterations: 1000, int keylen: 32}) {
    var derivator = new PBKDF2KeyDerivator(new HMac(new SHA256Digest(), 64))
      ..init(new Pbkdf2Parameters(
          Uint8List.fromList(salt.codeUnits), iterations, keylen));
    return derivator.process(Uint8List.fromList(secret.codeUnits));
  }

  static String encodeHmac(Uint8List key, int keylen, Uint8List challenge) {
    HMac mac = new HMac(new SHA256Digest(), 64);
    mac.init(new KeyParameter(key));
    mac.update(challenge, 0, challenge.length);
    Uint8List out = new Uint8List(keylen);
    mac.doFinal(out, 0);
    return base64.encode(out);
  }
}

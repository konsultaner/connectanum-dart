import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/pointycastle.dart';

import '../message/challenge.dart';
import '../authentication/abstract_authentication.dart';
import '../message/authenticate.dart';
import '../message/message_types.dart';
import '../message/error.dart';

/// This is the WAMPCRA authentication implementation for this package.
/// Use it with the [Client].
class CraAuthentication extends AbstractAuthentication {
  static final Uint8List DEFAULT_KEY_SALT = Uint8List(0);
  final String secret;

  CraAuthentication(this.secret);

  @override
  Future<Authenticate> challenge(Extra extra) {
    Authenticate authenticate = Authenticate();
    if (extra == null || extra.challenge == null || secret == null) {
      final error = Error(MessageTypes.CODE_CHALLENGE, -1,
          HashMap<String, Object>(), Error.AUTHORIZATION_FAILED);
      error.details["reason"] =
          "No challenge or secret given, wrong router response";
      return Future.error(error);
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
        Uint8List.fromList(base64.encode(key).codeUnits),
        extra.keylen,
        Uint8List.fromList(extra.challenge.codeUnits));
    return Future.value(authenticate);
  }

  static Uint8List deriveKey(String secret, String salt,
      {int iterations: 1000, int keylen: 32}) {
    var derivator = PBKDF2KeyDerivator(new HMac(new SHA256Digest(), 64))
      ..init(new Pbkdf2Parameters(
          Uint8List.fromList(salt.codeUnits), iterations, keylen));
    return derivator.process(Uint8List.fromList(secret.codeUnits));
  }

  static String encodeHmac(Uint8List key, int keylen, Uint8List challenge) {
    HMac mac = HMac(new SHA256Digest(), 64);
    mac.init(new KeyParameter(key));
    mac.update(challenge, 0, challenge.length);
    Uint8List out = Uint8List(keylen);
    mac.doFinal(out, 0);
    return base64.encode(out);
  }

  @override
  getName() {
    return "wampcra";
  }
}

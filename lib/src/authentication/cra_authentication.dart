import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/pointycastle.dart';

import '../message/details.dart';
import '../message/challenge.dart';
import '../authentication/abstract_authentication.dart';
import '../message/authenticate.dart';
import '../message/message_types.dart';
import '../message/error.dart';

/// This is the WAMPCRA authentication implementation for this package.
/// Use it with the [Client].
class CraAuthentication extends AbstractAuthentication {
  static final List<int> DEFAULT_KEY_SALT = [];
  final String secret;

  /// Initializes the authentication method with the [secret] aka password
  CraAuthentication(this.secret);

  /// This method is called by the session to modify the hello [details] for
  /// a given [realm]. Since CRA does not need to modify it. This method returns
  /// a completed future
  @override
  Future<void> hello(String realm, Details details) {
    return Future.value();
  }

  /// This method is called by the session if the router returns the challenge or
  /// the challenges [extra] respectively. This method proceeds the cra
  /// authentication process and creates an authentication message according to
  /// the wamp specification
  @override
  Future<Authenticate> challenge(Extra extra) {
    var authenticate = Authenticate();
    if (extra == null || extra.challenge == null || secret == null) {
      final error = Error(MessageTypes.CODE_CHALLENGE, -1,
          HashMap<String, Object>(), Error.AUTHORIZATION_FAILED);
      error.details['reason'] =
          'No challenge or secret given, wrong router response';
      return Future.error(error);
    }

    Uint8List key;
    if (extra.iterations != null && extra.iterations > 0) {
      key = deriveKey(
          secret, extra.salt == null ? DEFAULT_KEY_SALT : extra.salt.codeUnits,
          iterations: extra.iterations, keylen: extra.keylen);
    } else {
      key = deriveKey(
          secret, extra.salt == null ? DEFAULT_KEY_SALT : extra.salt.codeUnits);
    }

    authenticate.signature = encodeHmac(
        Uint8List.fromList(base64.encode(key).codeUnits),
        extra.keylen,
        Uint8List.fromList(extra.challenge.codeUnits));
    return Future.value(authenticate);
  }

  /// Creates an derived key from a [secret], [salt], [iterations], [keylen] and
  /// [hmacLength].
  static Uint8List deriveKey(String secret, List<int> salt,
      {int iterations = 1000, int keylen = 32, hmacLength = 64}) {
    var derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), hmacLength))
      ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, keylen));
    return derivator.process(Uint8List.fromList(secret.codeUnits));
  }

  /// Creates an base 64 encoded hmac from a [key] that usually is the derived
  /// key, [keylen], [challenge] and [hmacLength].
  static String encodeHmac(Uint8List key, int keylen, List<int> challenge,
      {hmacLength = 64}) {
    return base64
        .encode(encodeByteHmac(key, keylen, challenge, hmacLength: hmacLength));
  }

  /// Creates a hmac from a [key] that usually is the derived key, [keylen],
  /// [challenge] and [hmacLength].
  static Uint8List encodeByteHmac(
      Uint8List key, int keylen, List<int> challenge,
      {hmacLength = 64}) {
    var mac = HMac(SHA256Digest(), hmacLength);
    mac.init(KeyParameter(key));
    mac.update(Uint8List.fromList(challenge), 0, challenge.length);
    var out = Uint8List(keylen);
    mac.doFinal(out, 0);
    return out;
  }

  /// This method is called by the session to identify the authentication name.
  @override
  String getName() {
    return 'wampcra';
  }
}

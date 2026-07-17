import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/src/message/authenticate.dart';
import 'package:connectanum_core/src/message/challenge.dart';
import 'package:connectanum_core/src/message/details.dart';
import 'package:connectanum_core/src/message/error.dart';
import 'package:connectanum_core/src/message/message_types.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/pointycastle.dart';

import 'abstract_authentication.dart';

/// Controls how authentication strings are converted to bytes.
enum AuthenticationStringEncoding {
  /// UTF-8 bytes, as used by current WAMP implementations.
  utf8,

  /// Legacy UTF-16 code units for compatibility with older clients.
  utf16,
}

/// WAMP-CRA authentication implementation (client & router shared).
class CraAuthentication extends AbstractAuthentication {
  CraAuthentication(
    this.secret, {
    this.stringEncoding = AuthenticationStringEncoding.utf8,
  });

  final StreamController<Extra> _challengeStreamController =
      StreamController.broadcast();

  static const List<int> defaultKeySalt = [];
  static const int defaultIterations = 1000;
  static const int defaultKeyLength = 32;
  String secret;
  final AuthenticationStringEncoding stringEncoding;

  /// Encodes [value] using the selected authentication compatibility mode.
  static List<int> encodeString(
    String value, {
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) => switch (stringEncoding) {
    AuthenticationStringEncoding.utf8 => utf8.encode(value),
    AuthenticationStringEncoding.utf16 => value.codeUnits,
  };

  @override
  Stream<Extra> get onChallenge => _challengeStreamController.stream;

  @override
  Future<void> hello(String? realm, Details details) => Future.value();

  @override
  Future<Authenticate> challenge(Extra extra) async {
    await AbstractAuthentication.streamAddAwaited<Extra>(
      _challengeStreamController,
      extra,
    );

    final authenticate = Authenticate();
    if (extra.challenge == null) {
      final error = Error(
        MessageTypes.codeChallenge,
        -1,
        HashMap<String, Object>(),
        Error.authorizationFailed,
      );
      error.details['reason'] =
          'No challenge or secret given, wrong router response';
      return Future.error(error);
    }

    Uint8List key;
    if (extra.salt == null) {
      key = Uint8List.fromList(
        encodeString(secret, stringEncoding: stringEncoding),
      );
    } else {
      key = deriveKey(
        secret,
        encodeString(extra.salt!, stringEncoding: stringEncoding),
        iterations: extra.iterations == null || extra.iterations! <= 0
            ? defaultIterations
            : extra.iterations!,
        keylen: extra.keyLen == null || extra.keyLen! <= 0
            ? defaultKeyLength
            : extra.keyLen!,
        stringEncoding: stringEncoding,
      );
    }

    authenticate.signature = encodeHmac(
      Uint8List.fromList(base64.encode(key).codeUnits),
      extra.keyLen == null || extra.keyLen! <= 0
          ? defaultKeyLength
          : extra.keyLen!,
      Uint8List.fromList(
        encodeString(extra.challenge!, stringEncoding: stringEncoding),
      ),
    );
    return authenticate;
  }

  static Uint8List deriveKey(
    String secret,
    List<int> salt, {
    int iterations = defaultIterations,
    int keylen = defaultKeyLength,
    int hmacLength = 64,
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), hmacLength))
      ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, keylen));
    return derivator.process(
      Uint8List.fromList(encodeString(secret, stringEncoding: stringEncoding)),
    );
  }

  static String encodeHmac(
    Uint8List key,
    int keylen,
    List<int> challenge, {
    int hmacLength = 64,
  }) {
    return base64.encode(
      encodeByteHmac(key, keylen, challenge, hmacLength: hmacLength),
    );
  }

  static Uint8List encodeByteHmac(
    Uint8List key,
    int keylen,
    List<int> challenge, {
    int hmacLength = 64,
  }) {
    final mac = HMac(SHA256Digest(), hmacLength);
    mac.init(KeyParameter(key));
    mac.update(Uint8List.fromList(challenge), 0, challenge.length);
    final out = Uint8List(keylen);
    mac.doFinal(out, 0);
    return out;
  }

  @override
  String getName() => 'wampcra';

  static String signChallenge({
    required String secret,
    required Extra challenge,
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) {
    if (challenge.challenge == null) {
      throw ArgumentError('challenge.challenge is required');
    }

    Uint8List key;
    if (challenge.salt == null) {
      key = Uint8List.fromList(
        encodeString(secret, stringEncoding: stringEncoding),
      );
    } else {
      key = deriveKey(
        secret,
        encodeString(challenge.salt!, stringEncoding: stringEncoding),
        iterations: challenge.iterations == null || challenge.iterations! <= 0
            ? defaultIterations
            : challenge.iterations!,
        keylen: challenge.keyLen == null || challenge.keyLen! <= 0
            ? defaultKeyLength
            : challenge.keyLen!,
        stringEncoding: stringEncoding,
      );
    }

    final keyLen = challenge.keyLen == null || challenge.keyLen! <= 0
        ? defaultKeyLength
        : challenge.keyLen!;

    return encodeHmac(
      Uint8List.fromList(base64.encode(key).codeUnits),
      keyLen,
      Uint8List.fromList(
        encodeString(challenge.challenge!, stringEncoding: stringEncoding),
      ),
    );
  }

  static bool verifySignature({
    required String secret,
    required Extra challenge,
    required String signature,
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) =>
      signChallenge(
        secret: secret,
        challenge: challenge,
        stringEncoding: stringEncoding,
      ) ==
      signature;
}

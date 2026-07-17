import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../message/authenticate.dart';
import '../message/challenge.dart';
import '../message/details.dart';
import 'abstract_authentication.dart';
import 'cra_authentication.dart';
import 'package:pointycastle/export.dart';
import 'package:saslprep/saslprep.dart';

/// This class enables SCRAM authentication process with PBKDF2 as key derivation function
class ScramAuthentication extends AbstractAuthentication {
  static const String kdfPbkdf2 = 'pbkdf2';
  static const String kdfArgon = 'argon2id13';
  static final int defaultKeyLength = 32;

  final Completer<Uint8List> _firstClientKeyCompleter = Completer<Uint8List>();
  final StreamController<Extra> _challengeStreamController =
      StreamController.broadcast();
  late final bool _reuseClientKey;
  final AuthenticationStringEncoding stringEncoding;

  String? _secret;
  String? _authid;
  String? _helloNonce;
  Uint8List? _clientKey;
  Duration _challengeTimeout = Duration(seconds: 5);

  String? get secret => _secret;
  String? get authid => _authid;
  String? get helloNonce => _helloNonce;
  Duration get challengeTimeout => _challengeTimeout;

  @override
  Stream<Extra> get onChallenge => _challengeStreamController.stream;

  Future<Uint8List> get clientKey {
    if (_clientKey != null) {
      return Future<Uint8List>.sync(() => _clientKey!);
    } else {
      return _firstClientKeyCompleter.future;
    }
  }

  ScramAuthentication(
    String secret, {
    Duration? challengeTimeout,
    bool reuseClientKey = false,
    this.stringEncoding = AuthenticationStringEncoding.utf8,
  }) {
    if (challengeTimeout != null) {
      _challengeTimeout = challengeTimeout;
    }
    _reuseClientKey = reuseClientKey;
    _secret = Saslprep.saslprep(secret);
  }

  ScramAuthentication.fromClientKey(
    Uint8List clientKey, {
    Duration? challengeTimeout,
    this.stringEncoding = AuthenticationStringEncoding.utf8,
  }) {
    if (challengeTimeout != null) {
      _challengeTimeout = challengeTimeout;
    }
    _reuseClientKey = true;
    _clientKey = clientKey;
    _firstClientKeyCompleter.complete(_clientKey);
  }

  @override
  Future<void> hello(String? realm, Details details) {
    final random = Random.secure();
    final nonceBytes = [for (var i = 0; i < 16; i++) random.nextInt(256)];
    if (details.authid != null) {
      details.authid = Saslprep.saslprep(details.authid!);
      _authid = details.authid;
    }
    details.authextra ??= <String, dynamic>{};
    details.authextra!['nonce'] = base64.encode(nonceBytes);
    details.authextra!['channel_binding'] = null;
    _helloNonce = details.authextra!['nonce'];
    Future.delayed(_challengeTimeout, () => _helloNonce = null);
    return Future.value();
  }

  @override
  Future<Authenticate> challenge(Extra extra) async {
    await AbstractAuthentication.streamAddAwaited<Extra>(
      _challengeStreamController,
      extra,
    );

    if (extra.nonce == null ||
        _helloNonce == null ||
        !_helloNonce!.contains(
          extra.nonce!.substring(0, _helloNonce!.length),
        )) {
      return Future.error(Exception('Wrong nonce'));
    }

    if (extra.kdf != kdfArgon && extra.kdf != kdfPbkdf2) {
      return Future.error(
        Exception('not supported key derivation function used ${extra.kdf!}'),
      );
    }

    final authenticate = Authenticate();

    authenticate.extra = HashMap<String, Object?>();
    authenticate.extra!['nonce'] = extra.nonce;
    authenticate.extra!['channel_binding'] = null;
    authenticate.extra!['cbind_data'] = null;

    authenticate.signature = createSignature(
      _authid!,
      _helloNonce!,
      extra,
      authenticate.extra as HashMap<String, Object?>,
    );
    return authenticate;
  }

  String createSignature(
    String authId,
    String helloNonce,
    Extra extra,
    HashMap<String, Object?> authExtra,
  ) {
    if (!_reuseClientKey || _clientKey == null) {
      late Uint8List saltedPassword;
      if (extra.kdf == kdfPbkdf2) {
        saltedPassword = CraAuthentication.deriveKey(
          _secret!,
          extra.salt == null
              ? CraAuthentication.defaultKeySalt
              : base64.decode(extra.salt!),
          iterations: extra.iterations!,
          keylen: defaultKeyLength,
          stringEncoding: stringEncoding,
        );
      } else if (extra.kdf == kdfArgon) {
        saltedPassword = Uint8List(defaultKeyLength);
        Argon2BytesGenerator()
          ..init(
            Argon2Parameters(
              Argon2Parameters.ARGON2_id,
              Uint8List.fromList(base64.decode(extra.salt!)),
              desiredKeyLength: defaultKeyLength,
              iterations: extra.iterations ?? 1000,
              memory: extra.memory ?? 100,
              version: Argon2Parameters.ARGON2_VERSION_13,
            ),
          )
          ..deriveKey(
            Uint8List.fromList(
              CraAuthentication.encodeString(
                _secret!,
                stringEncoding: stringEncoding,
              ),
            ),
            0,
            saltedPassword,
            0,
          );
      }
      _clientKey = CraAuthentication.encodeByteHmac(
        saltedPassword,
        defaultKeyLength,
        utf8.encode('Client Key'),
      );
      if (!_firstClientKeyCompleter.isCompleted) {
        _firstClientKeyCompleter.complete(_clientKey);
      }
    }

    final storedKey = SHA256Digest().process(Uint8List.fromList(_clientKey!));
    final clientSignature = CraAuthentication.encodeByteHmac(
      storedKey,
      defaultKeyLength,
      CraAuthentication.encodeString(
        createAuthMessage(authId, helloNonce, authExtra, extra),
        stringEncoding: stringEncoding,
      ),
    );
    final signature = [
      for (var i = 0; i < _clientKey!.length; i++)
        _clientKey![i] ^ clientSignature[i],
    ];
    return base64.encode(signature);
  }

  static String createAuthMessage(
    String authId,
    String helloNonce,
    HashMap authExtra,
    Extra challengeExtra,
  ) {
    final clientFirstBare = 'n=${Saslprep.saslprep(authId)},r=$helloNonce';
    final serverFirst =
        'r=${challengeExtra.nonce!},s=${challengeExtra.salt!},i=${challengeExtra.iterations}';
    final cBindName = authExtra['channel_binding'];
    final cBindData = authExtra['cbind_data'];
    final cBindFlag = cBindName == null ? 'n' : 'p=$cBindName';
    final cBindInput = <int>[
      ...utf8.encode('$cBindFlag,,'),
      if (cBindData != null) ...base64.decode(cBindData as String),
    ];
    final clientFinalNoProof =
        'c=${base64.encode(cBindInput)},r=${authExtra['nonce']}';
    return '$clientFirstBare,$serverFirst,$clientFinalNoProof';
  }

  static bool verifyClientProof(
    List<int> clientProof,
    Uint8List storedKey,
    String authMessage, {
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) {
    final clientSignature = base64
        .decode(
          CraAuthentication.encodeHmac(
            storedKey,
            defaultKeyLength,
            CraAuthentication.encodeString(
              authMessage,
              stringEncoding: stringEncoding,
            ),
          ),
        )
        .toList();
    final recoveredClientKey = [
      for (var i = 0; i < defaultKeyLength; ++i)
        clientProof[i] ^ clientSignature[i],
    ];
    final recoveredStoredKey = SHA256Digest()
        .process(Uint8List.fromList(recoveredClientKey))
        .toList();
    for (var j = 0; j < storedKey.length; j++) {
      if (recoveredStoredKey[j] != storedKey[j]) {
        return false;
      }
    }
    return true;
  }

  @override
  String getName() => 'wamp-scram';

  static Uint8List deriveSaltedPassword({
    required String secret,
    required String salt,
    required String kdf,
    required int iterations,
    int? memory,
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) {
    final secretBytes = Uint8List.fromList(
      CraAuthentication.encodeString(secret, stringEncoding: stringEncoding),
    );
    final saltBytes = Uint8List.fromList(base64.decode(salt));
    if (kdf == kdfArgon) {
      final generator = Argon2BytesGenerator()
        ..init(
          Argon2Parameters(
            Argon2Parameters.ARGON2_id,
            saltBytes,
            desiredKeyLength: defaultKeyLength,
            iterations: iterations,
            memory: memory ?? 100,
            version: Argon2Parameters.ARGON2_VERSION_13,
          ),
        );
      final output = Uint8List(defaultKeyLength);
      generator.deriveKey(secretBytes, 0, output, 0);
      return output;
    }

    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(saltBytes, iterations, defaultKeyLength));
    return derivator.process(secretBytes);
  }

  static String generateProof({
    required String secret,
    required String authId,
    required String clientNonce,
    required Map<String, Object?> authExtra,
    required Extra challenge,
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) {
    if (challenge.salt == null) {
      throw ArgumentError('challenge.salt is required');
    }
    final saltedPassword = deriveSaltedPassword(
      secret: secret,
      salt: challenge.salt!,
      kdf: challenge.kdf ?? kdfPbkdf2,
      iterations: challenge.iterations ?? CraAuthentication.defaultIterations,
      memory: challenge.memory,
      stringEncoding: stringEncoding,
    );
    final clientKey = CraAuthentication.encodeByteHmac(
      saltedPassword,
      defaultKeyLength,
      utf8.encode('Client Key'),
    );
    final storedKey = SHA256Digest().process(Uint8List.fromList(clientKey));
    final authMessage = createAuthMessage(
      authId,
      clientNonce,
      HashMap<String, Object?>.from(authExtra),
      challenge,
    );
    final clientSignature = CraAuthentication.encodeByteHmac(
      storedKey,
      defaultKeyLength,
      CraAuthentication.encodeString(
        authMessage,
        stringEncoding: stringEncoding,
      ),
    );
    final proof = List<int>.generate(
      clientKey.length,
      (i) => clientKey[i] ^ clientSignature[i],
    );
    return base64.encode(proof);
  }

  static ScramServerSecrets deriveServerSecrets({
    required String secret,
    required String salt,
    String kdf = kdfPbkdf2,
    int iterations = CraAuthentication.defaultIterations,
    int? memory,
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) {
    final saltedPassword = deriveSaltedPassword(
      secret: secret,
      salt: salt,
      kdf: kdf,
      iterations: iterations,
      memory: memory,
      stringEncoding: stringEncoding,
    );
    final clientKey = CraAuthentication.encodeByteHmac(
      saltedPassword,
      defaultKeyLength,
      utf8.encode('Client Key'),
    );
    final storedKeyBytes = SHA256Digest().process(
      Uint8List.fromList(clientKey),
    );
    final serverKeyBytes = CraAuthentication.encodeByteHmac(
      saltedPassword,
      defaultKeyLength,
      utf8.encode('Server Key'),
    );
    return ScramServerSecrets(
      storedKey: base64.encode(storedKeyBytes),
      serverKey: base64.encode(serverKeyBytes),
    );
  }

  static bool verifySignature({
    required String secret,
    required String authId,
    required String clientNonce,
    required Map<String, Object?> authExtra,
    required Extra challenge,
    required String clientSignature,
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) {
    final expected = generateProof(
      secret: secret,
      authId: authId,
      clientNonce: clientNonce,
      authExtra: authExtra,
      challenge: challenge,
      stringEncoding: stringEncoding,
    );
    return expected == clientSignature;
  }
}

class ScramServerSecrets {
  const ScramServerSecrets({required this.storedKey, required this.serverKey});

  final String storedKey;
  final String serverKey;
}

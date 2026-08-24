import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:saslprep/saslprep.dart';

import '../message/authenticate.dart';
import '../message/challenge.dart';
import '../message/details.dart';
import 'abstract_authentication.dart';
import 'cra_authentication.dart';
import 'scram_argon_sync.dart';
import 'scram_key_derivation.dart';

/// WAMP-SCRAM authentication with asynchronous password-key derivation.
class ScramAuthentication extends AbstractAuthentication {
  static const String kdfPbkdf2 = 'pbkdf2';
  static const String kdfArgon = 'argon2id13';
  static const int defaultKeyLength = 32;

  final Completer<Uint8List> _firstClientKeyCompleter = Completer<Uint8List>();
  final StreamController<Extra> _challengeStreamController =
      StreamController<Extra>.broadcast();
  final bool _reuseClientKey;
  final ScramKeyDeriver _keyDeriver;
  final bool _ownsKeyDeriver;
  final Duration _derivationTimeout;
  final AuthenticationStringEncoding stringEncoding;

  String? _secret;
  String? _authid;
  String? _helloNonce;
  Uint8List? _clientKey;
  Uint8List? _serverKey;
  Uint8List? _expectedServerSignature;
  String? _expectedAuthId;
  String? _keyFingerprint;
  ScramKeyDerivationTask? _pendingTask;
  Duration _challengeTimeout = const Duration(seconds: 5);
  int _attemptGeneration = 0;
  bool _disposed = false;

  String? get secret => _secret;
  String? get authid => _authid;
  String? get helloNonce => _helloNonce;
  Duration get challengeTimeout => _challengeTimeout;

  @override
  Stream<Extra> get onChallenge => _challengeStreamController.stream;

  Future<Uint8List> get clientKey {
    final clientKey = _clientKey;
    if (clientKey != null) {
      return Future<Uint8List>.value(Uint8List.fromList(clientKey));
    }
    return _firstClientKeyCompleter.future.then(Uint8List.fromList);
  }

  ScramAuthentication(
    String secret, {
    Duration? challengeTimeout,
    Duration derivationTimeout = const Duration(seconds: 30),
    bool reuseClientKey = false,
    ScramKeyDeriver? keyDeriver,
    this.stringEncoding = AuthenticationStringEncoding.utf8,
  }) : _reuseClientKey = reuseClientKey,
       _keyDeriver = keyDeriver ?? ScramKeyDeriver(),
       _ownsKeyDeriver = keyDeriver == null,
       _derivationTimeout = derivationTimeout,
       _secret = Saslprep.saslprep(secret) {
    if (challengeTimeout != null) _challengeTimeout = challengeTimeout;
  }

  ScramAuthentication.fromClientKey(
    Uint8List clientKey, {
    required Uint8List serverKey,
    required ScramKeyCacheBinding binding,
    Duration? challengeTimeout,
    Duration derivationTimeout = const Duration(seconds: 30),
    ScramKeyDeriver? keyDeriver,
  }) : stringEncoding = binding.stringEncoding,
       _reuseClientKey = true,
       _keyDeriver = keyDeriver ?? ScramKeyDeriver(),
       _ownsKeyDeriver = keyDeriver == null,
       _derivationTimeout = derivationTimeout,
       _clientKey = Uint8List.fromList(clientKey),
       _serverKey = Uint8List.fromList(serverKey),
       _keyFingerprint = binding.fingerprint {
    if (challengeTimeout != null) _challengeTimeout = challengeTimeout;
    _firstClientKeyCompleter.complete(Uint8List.fromList(_clientKey!));
  }

  @override
  Future<void> hello(String? realm, Details details) async {
    _ensureUsable();
    final cancellation = cancelPendingChallenge();
    final generation = _attemptGeneration;
    final random = Random.secure();
    final nonceBytes = Uint8List.fromList(<int>[
      for (var i = 0; i < 16; i++) random.nextInt(256),
    ]);
    if (details.authid != null) {
      details.authid = Saslprep.saslprep(details.authid!);
      _authid = details.authid;
    }
    details.authextra ??= <String, dynamic>{};
    details.authextra!['nonce'] = base64.encode(nonceBytes);
    details.authextra!['channel_binding'] = null;
    _helloNonce = details.authextra!['nonce'] as String;
    _clear(nonceBytes);
    await cancellation;
    unawaited(
      Future<void>.delayed(_challengeTimeout, () {
        if (_attemptGeneration == generation) _helloNonce = null;
      }),
    );
  }

  @override
  Future<Authenticate> challenge(Extra extra) async {
    _ensureUsable();
    final generation = ++_attemptGeneration;
    await _cancelTaskOnly();
    _clearExpectedVerifier();
    await AbstractAuthentication.streamAddAwaited<Extra>(
      _challengeStreamController,
      extra,
    );

    final helloNonce = _helloNonce;
    final authId = _authid;
    final serverNonce = extra.nonce;
    if (serverNonce == null ||
        helloNonce == null ||
        serverNonce.length < helloNonce.length ||
        !serverNonce.startsWith(helloNonce)) {
      throw Exception('Wrong nonce');
    }
    if (authId == null) throw StateError('SCRAM authid is required');
    _validateChallenge(extra);

    final authExtra = HashMap<String, Object?>()
      ..['nonce'] = serverNonce
      ..['channel_binding'] = null
      ..['cbind_data'] = null;
    final signature = await _createSignatureAsync(
      authId,
      helloNonce,
      extra,
      authExtra,
      generation,
    );
    if (_attemptGeneration != generation || _disposed) {
      throw const ScramKeyDerivationCancelledException();
    }
    return Authenticate()
      ..extra = authExtra
      ..signature = signature;
  }

  /// Synchronous compatibility helper. Argon2id13 deliberately throws on web.
  String createSignature(
    String authId,
    String helloNonce,
    Extra extra,
    HashMap<String, Object?> authExtra,
  ) {
    _ensureUsable();
    _validateChallenge(extra);
    final fingerprint = _fingerprint(authId, extra);
    if (_keyFingerprint != null && _keyFingerprint != fingerprint) {
      if (_secret == null) {
        throw StateError('Cached SCRAM key does not match this challenge');
      }
      _clearKeys();
    }
    if (_clientKey == null) {
      final secret = _secret;
      if (secret == null) throw StateError('SCRAM secret is unavailable');
      final saltedPassword = deriveSaltedPassword(
        secret: secret,
        salt: extra.salt!,
        kdf: extra.kdf!,
        iterations: extra.iterations!,
        memory: extra.memory,
        stringEncoding: stringEncoding,
      );
      _installKeys(saltedPassword, fingerprint);
      _clear(saltedPassword);
    } else {
      _keyFingerprint ??= fingerprint;
    }
    return _buildProofAndVerifier(authId, helloNonce, authExtra, extra);
  }

  Future<String> _createSignatureAsync(
    String authId,
    String helloNonce,
    Extra extra,
    HashMap<String, Object?> authExtra,
    int generation,
  ) async {
    final fingerprint = _fingerprint(authId, extra);
    if (_keyFingerprint != null && _keyFingerprint != fingerprint) {
      if (_secret == null) {
        throw StateError('Cached SCRAM key does not match this challenge');
      }
      _clearKeys();
    }
    if (_clientKey == null) {
      final secret = _secret;
      if (secret == null) throw StateError('SCRAM secret is unavailable');
      final request = ScramKeyDerivationRequest(
        password: Uint8List.fromList(
          CraAuthentication.encodeString(
            secret,
            stringEncoding: stringEncoding,
          ),
        ),
        salt: Uint8List.fromList(base64.decode(extra.salt!)),
        kdf: extra.kdf!,
        iterations: extra.iterations!,
        memory: extra.memory ?? 100,
        keyLength: defaultKeyLength,
      );
      final task = _keyDeriver.start(request, timeout: _derivationTimeout);
      _pendingTask = task;
      Uint8List? saltedPassword;
      try {
        saltedPassword = await task.result;
        if (_attemptGeneration != generation || _disposed) {
          throw const ScramKeyDerivationCancelledException();
        }
        _installKeys(saltedPassword, fingerprint);
      } finally {
        if (identical(_pendingTask, task)) _pendingTask = null;
        if (saltedPassword != null) _clear(saltedPassword);
      }
    } else {
      _keyFingerprint ??= fingerprint;
    }
    return _buildProofAndVerifier(authId, helloNonce, authExtra, extra);
  }

  void _installKeys(Uint8List saltedPassword, String fingerprint) {
    _clearKeys();
    _clientKey = CraAuthentication.encodeByteHmac(
      saltedPassword,
      defaultKeyLength,
      utf8.encode('Client Key'),
    );
    _serverKey = CraAuthentication.encodeByteHmac(
      saltedPassword,
      defaultKeyLength,
      utf8.encode('Server Key'),
    );
    _keyFingerprint = fingerprint;
    if (!_firstClientKeyCompleter.isCompleted) {
      _firstClientKeyCompleter.complete(Uint8List.fromList(_clientKey!));
    }
  }

  String _buildProofAndVerifier(
    String authId,
    String helloNonce,
    HashMap<String, Object?> authExtra,
    Extra extra,
  ) {
    final clientKey = _clientKey!;
    final serverKey = _serverKey;
    final authMessage = createAuthMessage(
      authId,
      helloNonce,
      authExtra,
      extra,
    );
    final storedKey = SHA256Digest().process(Uint8List.fromList(clientKey));
    final authMessageBytes = Uint8List.fromList(
      CraAuthentication.encodeString(
        authMessage,
        stringEncoding: stringEncoding,
      ),
    );
    final clientSignature = CraAuthentication.encodeByteHmac(
      storedKey,
      defaultKeyLength,
      authMessageBytes,
    );
    final signature = Uint8List(clientKey.length);
    for (var i = 0; i < clientKey.length; i++) {
      signature[i] = clientKey[i] ^ clientSignature[i];
    }
    _clearExpectedVerifier();
    if (serverKey != null) {
      _expectedServerSignature = CraAuthentication.encodeByteHmac(
        serverKey,
        defaultKeyLength,
        authMessageBytes,
      );
      _expectedAuthId = authId;
    }
    final encoded = base64.encode(signature);
    _clear(storedKey);
    _clear(authMessageBytes);
    _clear(clientSignature);
    _clear(signature);
    return encoded;
  }

  @override
  Future<void> verifyFinal({
    required String? authId,
    required String? authMethod,
    required Map<String, Object?>? authExtra,
  }) async {
    final expected = _expectedServerSignature;
    try {
      if (expected == null ||
          authMethod != getName() ||
          authId != _expectedAuthId) {
        throw StateError('SCRAM server identity could not be verified');
      }
      final encodedVerifier = authExtra?['verifier'];
      if (encodedVerifier is! String) {
        throw StateError('SCRAM server verifier is missing');
      }
      Uint8List actual;
      try {
        actual = Uint8List.fromList(base64.decode(encodedVerifier));
      } on FormatException {
        throw StateError('SCRAM server verifier is invalid');
      }
      final valid = _constantTimeEquals(expected, actual);
      _clear(actual);
      if (!valid) throw StateError('SCRAM server verifier is invalid');
    } finally {
      _clearExpectedVerifier();
      if (!_reuseClientKey) _clearKeys();
    }
  }

  @override
  Future<void> cancelPendingChallenge() async {
    _attemptGeneration++;
    _clearExpectedVerifier();
    _helloNonce = null;
    if (!_reuseClientKey) _clearKeys();
    await _cancelTaskOnly();
  }

  Future<void> _cancelTaskOnly() async {
    final task = _pendingTask;
    _pendingTask = null;
    if (task != null) await task.cancel();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancelPendingChallenge();
    if (_ownsKeyDeriver) await _keyDeriver.dispose();
    await _challengeStreamController.close();
    _clearKeys();
    _secret = null;
    _authid = null;
  }

  void _validateChallenge(Extra extra) {
    if (extra.kdf != kdfArgon && extra.kdf != kdfPbkdf2) {
      throw Exception(
        'not supported key derivation function used ${extra.kdf}',
      );
    }
    if (extra.salt == null) throw ArgumentError('challenge.salt is required');
    if ((extra.iterations ?? 0) <= 0) {
      throw ArgumentError('challenge.iterations must be positive');
    }
    if (extra.kdf == kdfArgon && extra.memory != null && extra.memory! <= 0) {
      throw ArgumentError('challenge.memory must be positive for Argon2id13');
    }
  }

  String _fingerprint(String authId, Extra extra) => <Object?>[
    ScramKeyCacheBinding(
      authId: authId,
      salt: extra.salt!,
      kdf: extra.kdf!,
      iterations: extra.iterations!,
      memory: extra.memory ?? 100,
      stringEncoding: stringEncoding,
    ).fingerprint,
  ].join();

  void _clearKeys() {
    final clientKey = _clientKey;
    final serverKey = _serverKey;
    if (clientKey != null) _clear(clientKey);
    if (serverKey != null) _clear(serverKey);
    _clientKey = null;
    _serverKey = null;
    _keyFingerprint = null;
  }

  void _clearExpectedVerifier() {
    final signature = _expectedServerSignature;
    if (signature != null) _clear(signature);
    _expectedServerSignature = null;
    _expectedAuthId = null;
  }

  void _ensureUsable() {
    if (_disposed) throw StateError('SCRAM authentication is disposed');
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
    if (clientProof.length != defaultKeyLength ||
        storedKey.length != defaultKeyLength) {
      return false;
    }
    final authMessageBytes = Uint8List.fromList(
      CraAuthentication.encodeString(
        authMessage,
        stringEncoding: stringEncoding,
      ),
    );
    try {
      final clientSignature = CraAuthentication.encodeByteHmac(
        storedKey,
        defaultKeyLength,
        authMessageBytes,
      );
      final recoveredClientKey = Uint8List(defaultKeyLength);
      Uint8List? recoveredStoredKey;
      try {
        for (var i = 0; i < defaultKeyLength; i++) {
          recoveredClientKey[i] = clientProof[i] ^ clientSignature[i];
        }
        recoveredStoredKey = SHA256Digest().process(recoveredClientKey);
        return _constantTimeEquals(recoveredStoredKey, storedKey);
      } finally {
        _clear(clientSignature);
        _clear(recoveredClientKey);
        if (recoveredStoredKey != null) _clear(recoveredStoredKey);
      }
    } finally {
      _clear(authMessageBytes);
    }
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
    try {
      if (kdf == kdfArgon) {
        return deriveScramArgonSynchronously(
          password: secretBytes,
          salt: saltBytes,
          iterations: iterations,
          memory: memory ?? 100,
          keyLength: defaultKeyLength,
        );
      }
      if (kdf != kdfPbkdf2) {
        throw ArgumentError.value(kdf, 'kdf', 'unsupported SCRAM KDF');
      }
      final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(saltBytes, iterations, defaultKeyLength));
      return derivator.process(secretBytes);
    } finally {
      _clear(secretBytes);
      _clear(saltBytes);
    }
  }

  static Future<Uint8List> deriveSaltedPasswordAsync({
    required String secret,
    required String salt,
    required String kdf,
    required int iterations,
    int? memory,
    Duration timeout = const Duration(seconds: 30),
    ScramKeyDeriver? keyDeriver,
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) async {
    final ownedDeriver = keyDeriver == null;
    final deriver = keyDeriver ?? ScramKeyDeriver();
    try {
      final task = deriver.start(
        ScramKeyDerivationRequest(
          password: Uint8List.fromList(
            CraAuthentication.encodeString(
              secret,
              stringEncoding: stringEncoding,
            ),
          ),
          salt: Uint8List.fromList(base64.decode(salt)),
          kdf: kdf,
          iterations: iterations,
          memory: memory ?? 100,
          keyLength: defaultKeyLength,
        ),
        timeout: timeout,
      );
      return await task.result;
    } finally {
      if (ownedDeriver) await deriver.dispose();
    }
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
    try {
      return _generateProofFromSaltedPassword(
        saltedPassword: saltedPassword,
        authId: authId,
        clientNonce: clientNonce,
        authExtra: authExtra,
        challenge: challenge,
        stringEncoding: stringEncoding,
      );
    } finally {
      _clear(saltedPassword);
    }
  }

  static Future<String> generateProofAsync({
    required String secret,
    required String authId,
    required String clientNonce,
    required Map<String, Object?> authExtra,
    required Extra challenge,
    ScramKeyDeriver? keyDeriver,
    Duration timeout = const Duration(seconds: 30),
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) async {
    final saltedPassword = await deriveSaltedPasswordAsync(
      secret: secret,
      salt: challenge.salt!,
      kdf: challenge.kdf ?? kdfPbkdf2,
      iterations: challenge.iterations ?? CraAuthentication.defaultIterations,
      memory: challenge.memory,
      timeout: timeout,
      keyDeriver: keyDeriver,
      stringEncoding: stringEncoding,
    );
    try {
      return _generateProofFromSaltedPassword(
        saltedPassword: saltedPassword,
        authId: authId,
        clientNonce: clientNonce,
        authExtra: authExtra,
        challenge: challenge,
        stringEncoding: stringEncoding,
      );
    } finally {
      _clear(saltedPassword);
    }
  }

  static String _generateProofFromSaltedPassword({
    required Uint8List saltedPassword,
    required String authId,
    required String clientNonce,
    required Map<String, Object?> authExtra,
    required Extra challenge,
    required AuthenticationStringEncoding stringEncoding,
  }) {
    final clientKey = CraAuthentication.encodeByteHmac(
      saltedPassword,
      defaultKeyLength,
      utf8.encode('Client Key'),
    );
    final storedKey = SHA256Digest().process(clientKey);
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
    final proof = Uint8List(clientKey.length);
    for (var i = 0; i < clientKey.length; i++) {
      proof[i] = clientKey[i] ^ clientSignature[i];
    }
    final encoded = base64.encode(proof);
    _clear(clientKey);
    _clear(storedKey);
    _clear(clientSignature);
    _clear(proof);
    return encoded;
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
    try {
      return _serverSecretsFromSaltedPassword(saltedPassword);
    } finally {
      _clear(saltedPassword);
    }
  }

  static Future<ScramServerSecrets> deriveServerSecretsAsync({
    required String secret,
    required String salt,
    String kdf = kdfPbkdf2,
    int iterations = CraAuthentication.defaultIterations,
    int? memory,
    Duration timeout = const Duration(seconds: 30),
    ScramKeyDeriver? keyDeriver,
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) async {
    final saltedPassword = await deriveSaltedPasswordAsync(
      secret: secret,
      salt: salt,
      kdf: kdf,
      iterations: iterations,
      memory: memory,
      timeout: timeout,
      keyDeriver: keyDeriver,
      stringEncoding: stringEncoding,
    );
    try {
      return _serverSecretsFromSaltedPassword(saltedPassword);
    } finally {
      _clear(saltedPassword);
    }
  }

  static ScramServerSecrets _serverSecretsFromSaltedPassword(
    Uint8List saltedPassword,
  ) {
    final clientKey = CraAuthentication.encodeByteHmac(
      saltedPassword,
      defaultKeyLength,
      utf8.encode('Client Key'),
    );
    final storedKeyBytes = SHA256Digest().process(clientKey);
    final serverKeyBytes = CraAuthentication.encodeByteHmac(
      saltedPassword,
      defaultKeyLength,
      utf8.encode('Server Key'),
    );
    final result = ScramServerSecrets(
      storedKey: base64.encode(storedKeyBytes),
      serverKey: base64.encode(serverKeyBytes),
    );
    _clear(clientKey);
    _clear(storedKeyBytes);
    _clear(serverKeyBytes);
    return result;
  }

  static String createServerSignature({
    required Uint8List serverKey,
    required String authMessage,
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) {
    final authMessageBytes = Uint8List.fromList(
      CraAuthentication.encodeString(
        authMessage,
        stringEncoding: stringEncoding,
      ),
    );
    Uint8List? signature;
    try {
      signature = CraAuthentication.encodeByteHmac(
        serverKey,
        defaultKeyLength,
        authMessageBytes,
      );
      return base64.encode(signature);
    } finally {
      _clear(authMessageBytes);
      if (signature != null) _clear(signature);
    }
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
  }) =>
      generateProof(
        secret: secret,
        authId: authId,
        clientNonce: clientNonce,
        authExtra: authExtra,
        challenge: challenge,
        stringEncoding: stringEncoding,
      ) ==
      clientSignature;

  static Future<bool> verifySignatureAsync({
    required String secret,
    required String authId,
    required String clientNonce,
    required Map<String, Object?> authExtra,
    required Extra challenge,
    required String clientSignature,
    ScramKeyDeriver? keyDeriver,
    Duration timeout = const Duration(seconds: 30),
    AuthenticationStringEncoding stringEncoding =
        AuthenticationStringEncoding.utf8,
  }) async =>
      await generateProofAsync(
        secret: secret,
        authId: authId,
        clientNonce: clientNonce,
        authExtra: authExtra,
        challenge: challenge,
        keyDeriver: keyDeriver,
        timeout: timeout,
        stringEncoding: stringEncoding,
      ) ==
      clientSignature;

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = min(left.length, right.length);
    for (var i = 0; i < length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }

  static void _clear(Uint8List value) {
    value.fillRange(0, value.length, 0);
  }
}

class ScramServerSecrets {
  const ScramServerSecrets({required this.storedKey, required this.serverKey});

  final String storedKey;
  final String serverKey;
}

/// Exact derivation inputs that bind a reusable SCRAM client/server key pair.
final class ScramKeyCacheBinding {
  const ScramKeyCacheBinding({
    required this.authId,
    required this.salt,
    required this.kdf,
    required this.iterations,
    required this.memory,
    this.stringEncoding = AuthenticationStringEncoding.utf8,
  });

  final String authId;
  final String salt;
  final String kdf;
  final int iterations;
  final int memory;
  final AuthenticationStringEncoding stringEncoding;

  String get fingerprint => <Object?>[
    Saslprep.saslprep(authId),
    salt,
    kdf,
    iterations,
    memory,
    stringEncoding.name,
    ScramAuthentication.defaultKeyLength,
  ].join('\u0000');
}

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
  static final String kdfPbkdf2 = 'pbkdf2';
  static final String kdfArgon = 'argon2id13';
  static final int defaultKeyLength = 32;

  final Completer<Uint8List> _firstClientKeyCompleter = Completer<Uint8List>();
  final StreamController<Extra> _challengeStreamController =
      StreamController.broadcast();
  late final bool _reuseClientKey;

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
            Uint8List.fromList(_secret!.codeUnits),
            0,
            saltedPassword,
            0,
          );
      }
      _clientKey = CraAuthentication.encodeByteHmac(
        saltedPassword,
        defaultKeyLength,
        'Client Key'.codeUnits,
      );
      if (!_firstClientKeyCompleter.isCompleted) {
        _firstClientKeyCompleter.complete(_clientKey);
      }
    }

    final storedKey = SHA256Digest().process(Uint8List.fromList(_clientKey!));
    final clientSignature = CraAuthentication.encodeByteHmac(
      storedKey,
      defaultKeyLength,
      createAuthMessage(authId, helloNonce, authExtra, extra).codeUnits,
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
    final cBindInput =
        '$cBindFlag,,${cBindData == null ? '' : base64.decode(cBindData) as String}';
    final clientFinalNoProof =
        'c=${base64.encode(cBindInput.codeUnits)},r=${authExtra['nonce']}';
    return '$clientFirstBare,$serverFirst,$clientFinalNoProof';
  }

  static bool verifyClientProof(
    List<int> clientProof,
    Uint8List storedKey,
    String authMessage,
  ) {
    final clientSignature = base64
        .decode(
          CraAuthentication.encodeHmac(
            storedKey,
            defaultKeyLength,
            authMessage.codeUnits,
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
}

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

/// This class enables SCRAM authentication process with PBKDF2 as key derivation function
class ScramAuthentication extends AbstractAuthentication {
  static final String kdfPbkdf2 = 'pbkdf2';
  static final String kdfArgon = 'argon2id13';
  static final int defaultKeyLength = 32;

  final Completer<Uint8List> _firstClientKeyCompleter = Completer<Uint8List>();
  final StreamController<Extra> _challengeStreamController = StreamController.broadcast();
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

  /// When the challenge starts the stream will provide the current [Extra] in
  /// case the client needs some additional information to challenge the server.
  @override
  Stream<Extra> get onChallenge => _challengeStreamController.stream;

  Future<Uint8List> get clientKey {
    if (_clientKey != null) {
      return Future<Uint8List>.sync(
        () => _clientKey!,
      );
    } else {
      return _firstClientKeyCompleter.future;
    }
  }

  /// Initialized the instance with the [secret] and an optional [challengeTimeout]
  /// which will cause the authentication process to fail if the server response took
  /// too long. The [reuseClientKey] option will compute the client key only for
  /// the first time. The second time stored client key is used
  ScramAuthentication(String secret,
      {Duration? challengeTimeout, bool reuseClientKey = false}) {
    if (challengeTimeout != null) {
      _challengeTimeout = challengeTimeout;
    }
    _reuseClientKey = reuseClientKey;
    _secret = Saslprep.saslprep(secret);
  }

  /// If the client key was stored, use this named constructor with the stored
  /// [clientKey] instead. This will save computation time.
  /// The optional [challengeTimeout] will cause the authentication process to
  /// fail if the server response took too long.
  ScramAuthentication.fromClientKey(Uint8List clientKey,
      {Duration? challengeTimeout}) {
    if (challengeTimeout != null) {
      _challengeTimeout = challengeTimeout;
    }
    _reuseClientKey = true;
    _clientKey = clientKey;
    _firstClientKeyCompleter.complete(_clientKey);
  }

  /// This method is called by the session to modify the hello [details] for
  /// a given [realm]. This method generates the [authExtra] 'nonce' value and
  /// starts the timeout to cancel the challenge if it took exceptionally long
  /// to receive
  @override
  Future<void> hello(String? realm, Details details) {
    var random = Random.secure();
    var nonceBytes = [for (int i = 0; i < 16; i++) random.nextInt(256)];
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

  /// This method accepts the servers challenge and responds with the according
  /// authentication method, that is to be sent to the server to authenticate the
  /// session.
  /// It calculates the client proof according to the [WAMP-SCRAM specs](https://wamp-proto.org/_static/gen/wamp_latest.html#authmessage) where
  /// [authId] is the username that has already been saslpreped with [Saslprep.saslprep(input)] and [helloNonce] is a randomly generated nonce according
  /// to the WAMP-SCRAM specs. The keylength is 32 according to the WAMP-SCRAM specs
  @override
  Future<Authenticate> challenge(Extra extra) async {
    await AbstractAuthentication.streamAddAwaited<Extra>(_challengeStreamController,extra);

    if (extra.nonce == null ||
        _helloNonce == null ||
        !_helloNonce!
            .contains(extra.nonce!.substring(0, _helloNonce!.length))) {
      return Future.error(Exception('Wrong nonce'));
    }

    if (extra.kdf != kdfArgon && extra.kdf != kdfPbkdf2) {
      return Future.error(Exception(
          'not supported key derivation function used ${extra.kdf!}'));
    }

    var authenticate = Authenticate();

    authenticate.extra = HashMap<String, Object?>();
    authenticate.extra!['nonce'] = extra.nonce;
    authenticate.extra!['channel_binding'] = null;
    authenticate.extra!['cbind_data'] = null;

    authenticate.signature = createSignature(_authid!, _helloNonce!, extra,
        authenticate.extra as HashMap<String, Object?>);
    return authenticate;
  }

  /// Calculates the client proof according to the [WAMP-SCRAM specs](https://wamp-proto.org/_static/gen/wamp_latest.html#authmessage) where
  /// [authId] is the username that has already been saslpreped with [Saslprep.saslprep(input)] and [helloNonce] is a randomly generated nonce according
  /// to the WAMP-SCRAM specs. The keylength is 32 according to the WAMP-SCRAM specs
  String createSignature(String authId, String helloNonce, Extra extra,
      HashMap<String, Object?> authExtra) {
    if (!_reuseClientKey || _clientKey == null) {
      late Uint8List saltedPassword;
      if (extra.kdf == kdfPbkdf2) {
        saltedPassword = CraAuthentication.deriveKey(
            _secret!,
            extra.salt == null
                ? CraAuthentication.defaultKeySalt
                : base64.decode(extra.salt!),
            iterations: extra.iterations!,
            keylen: defaultKeyLength);
      } else if (extra.kdf == kdfArgon) {
        saltedPassword = Uint8List(32);
        Argon2BytesGenerator()
          ..init(Argon2Parameters(Argon2Parameters.ARGON2_id,
              Uint8List.fromList(base64.decode(extra.salt!)),
              desiredKeyLength: defaultKeyLength,
              iterations: extra.iterations ?? 1000,
              memory: extra.memory ?? 100,
              version: Argon2Parameters.ARGON2_VERSION_13))
          ..deriveKey(
              Uint8List.fromList(_secret!.codeUnits), 0, saltedPassword, 0);
      }
      _clientKey = CraAuthentication.encodeByteHmac(
          saltedPassword, defaultKeyLength, 'Client Key'.codeUnits);
      if (!_firstClientKeyCompleter.isCompleted) {
        _firstClientKeyCompleter.complete(_clientKey);
      }
    }

    var storedKey = SHA256Digest().process(Uint8List.fromList(_clientKey!));
    var clientSignature = CraAuthentication.encodeByteHmac(
        storedKey,
        defaultKeyLength,
        createAuthMessage(authId, helloNonce, authExtra, extra).codeUnits);
    var signature = [
      for (int i = 0; i < _clientKey!.length; i++)
        _clientKey![i] ^ clientSignature[i]
    ];
    return base64.encode(signature);
  }

  /// This creates the SCRAM authmessage according to the [WAMP-SCRAM specs](https://wamp-proto.org/_static/gen/wamp_latest.html#authmessage)
  static String createAuthMessage(String authId, String helloNonce,
      HashMap authExtra, Extra challengeExtra) {
    var clientFirstBare = 'n=${Saslprep.saslprep(authId)},r=$helloNonce';
    var serverFirst =
        'r=${challengeExtra.nonce!},s=${challengeExtra.salt!},i=${challengeExtra.iterations}';
    String? cBindName = authExtra['channel_binding'];
    String? cBindData = authExtra['cbind_data'];
    var cBindFlag = cBindName == null ? 'n' : 'p=$cBindName';
    var cBindInput =
        '$cBindFlag,,${cBindData == null ? '' : base64.decode(cBindData) as String}';
    var clientFinalNoProof =
        'c=${base64.encode(cBindInput.codeUnits)},r=${authExtra['nonce']}';
    return '$clientFirstBare,$serverFirst,$clientFinalNoProof';
  }

  /// this is a scrum authentication verifier that will used to run the
  /// integration test for scrum authentication. This method is used on the
  /// router side to validate the challenge result.
  static bool verifyClientProof(
      List<int> clientProof, Uint8List storedKey, String authMessage) {
    var clientSignature = base64
        .decode(CraAuthentication.encodeHmac(
            storedKey, defaultKeyLength, authMessage.codeUnits))
        .toList();
    var recoveredClientKey = [
      for (var i = 0; i < defaultKeyLength; ++i)
        clientProof[i] ^ clientSignature[i]
    ];
    var recoveredStoredKey =
        SHA256Digest().process(Uint8List.fromList(recoveredClientKey)).toList();
    for (var j = 0; j < storedKey.length; j++) {
      if (recoveredStoredKey[j] != storedKey[j]) {
        return false;
      }
    }
    return true;
  }

  /// The official name of the authentication method used in the opening handshake of wamp
  @override
  String getName() {
    return 'wamp-scram';
  }
}

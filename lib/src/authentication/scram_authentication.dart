import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:saslprep/saslprep.dart';

import '../message/authenticate.dart';
import '../message/challenge.dart';
import '../message/details.dart';
import 'abstract_authentication.dart';
import 'cra_authentication.dart';

/// This class enables SCRAM authentication process with PBKDF2 as key derivation function
class ScramAuthentication extends AbstractAuthentication {
  static final String KDF_PBKDF2 = 'pbkdf2';
  static final int DEFAULT_KEY_LENGTH = 32;

  String _secret;
  String _authid;
  String _helloNonce;
  Duration _challengeTimeout = Duration(seconds: 5);

  String get secret => _secret;
  String get authid => _authid;
  String get helloNonce => _helloNonce;
  Duration get challengeTimeout => _challengeTimeout;

  /// Initialized the instance with the [secret] and an optional [challengeTimeout]
  /// which will cause the authentication process to fail if the server responce took
  /// too long
  ScramAuthentication(String secret, {challengeTimeout}) {
    if (challengeTimeout != null) {
      _challengeTimeout = challengeTimeout;
    }
    _secret = Saslprep.saslprep(secret);
  }

  /// This method is called by the session to modify the hello [details] for
  /// a given [realm]. This method generates the [authExtra] 'nonce' value and
  /// starts the timeout to cancel the challenge if it took exceptionally long
  /// to receive
  @override
  Future<void> hello(String realm, Details details) {
    var random = Random.secure();
    var nonceBytes = [for (int i = 0; i < 16; i++) random.nextInt(256)];
    if (details.authid != null) {
      details.authid = Saslprep.saslprep(details.authid);
      _authid = details.authid;
    }
    details.authextra ??= HashMap<String, String>();
    details.authextra['nonce'] = base64.encode(nonceBytes);
    details.authextra['channel_binding'] = null;
    _helloNonce = details.authextra['nonce'];
    Future.delayed(_challengeTimeout, () => _helloNonce = null);
    return Future.value();
  }

  /// This method accepts the servers challenge and responds with the according
  /// authentication method, that is to be sent to the server to authenticate the
  /// session
  @override
  Future<Authenticate> challenge(Extra extra) {
    if (extra.nonce == null ||
        _helloNonce == null ||
        !_helloNonce.contains(extra.nonce.substring(0, _helloNonce.length))) {
      return Future.error(Exception('Wrong nonce'));
    }
    var authenticate = Authenticate();

    authenticate.extra = HashMap<String, Object>();
    authenticate.extra['nonce'] = extra.nonce;
    authenticate.extra['channel_binding'] = null;
    authenticate.extra['cbind_data'] = null;
    if (extra.kdf == KDF_PBKDF2) {
      authenticate.signature =
          challengePBKDF2(_authid, _helloNonce, extra, authenticate.extra);
    }
    if (authenticate.signature == null) {
      return Future.error(
          Exception('not supported key derivation function used ' + extra.kdf));
    }
    return Future.value(authenticate);
  }

  /// Calculates the client proof according to the [WAMP-SCRAM specs](https://wamp-proto.org/_static/gen/wamp_latest.html#authmessage) where
  /// [authId] is the username that has already been saslpreped with [Saslprep.saslprep(input)] and [helloNonce] is a randomly generated nonce according
  /// to the WAMP-SCRAM specs. The keylength is 32 according to the WAMP-SCRAM specs
  String challengePBKDF2(String authId, String helloNonce, Extra challengeExtra,
      HashMap<String, Object> authExtra) {
    var saltedPassword = CraAuthentication.deriveKey(
        _secret,
        challengeExtra.salt == null
            ? CraAuthentication.DEFAULT_KEY_SALT
            : base64.decode(challengeExtra.salt),
        iterations: challengeExtra.iterations,
        keylen: DEFAULT_KEY_LENGTH);
    var clientKey = CraAuthentication.encodeByteHmac(
        saltedPassword, DEFAULT_KEY_LENGTH, 'Client Key'.codeUnits);
    var storedKey = SHA256Digest().process(Uint8List.fromList(clientKey));
    var clientSignature = CraAuthentication.encodeByteHmac(
        storedKey,
        DEFAULT_KEY_LENGTH,
        createAuthMessage(authId, helloNonce, authExtra, challengeExtra)
            .codeUnits);
    var signature = [
      for (int i = 0; i < clientKey.length; i++)
        clientKey[i] ^ clientSignature[i]
    ];
    return base64.encode(signature);
  }

  /// This creates the SCRAM authmessage according to the [WAMP-SCRAM specs](https://wamp-proto.org/_static/gen/wamp_latest.html#authmessage)
  static String createAuthMessage(String authId, String helloNonce,
      HashMap authExtra, Extra challengeExtra) {
    var clientFirstBare =
        'n=' + Saslprep.saslprep(authId) + ',' + 'r=' + helloNonce;
    var serverFirst = 'r=' +
        challengeExtra.nonce +
        ',s=' +
        challengeExtra.salt +
        ',i=' +
        challengeExtra.iterations.toString();
    String cBindName = authExtra['channel_binding'];
    String cBindData = authExtra['cbind_data'];
    var cBindFlag = cBindName == null ? 'n' : 'p=' + cBindName;
    var cBindInput =
        cBindFlag + ',,' + (cBindData == null ? '' : base64.decode(cBindData));
    var clientFinalNoProof =
        'c=' + base64.encode(cBindInput.codeUnits) + ',r=' + authExtra['nonce'];
    return clientFirstBare + ',' + serverFirst + ',' + clientFinalNoProof;
  }

  /// this is a scrum authentication verifier that will used to run the
  /// integration test for scrum authentication. This method is used on the
  /// router side to validate the challenge result.
  static bool verifyClientProof(
      List<int> clientProof, Uint8List storedKey, String authMessage) {
    var clientSignature = base64
        .decode(CraAuthentication.encodeHmac(
            storedKey, DEFAULT_KEY_LENGTH, authMessage.codeUnits))
        .toList();
    var recoveredClientKey = [
      for (var i = 0; i < DEFAULT_KEY_LENGTH; ++i)
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

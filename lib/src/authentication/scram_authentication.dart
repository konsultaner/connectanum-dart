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

class ScramAuthentication extends AbstractAuthentication {

  static final String KDF_PBKDF2 = 'pbkdf2';

  String _secret;
  String _authid;
  String _helloNonce;
  Duration _challengeTimeout = new Duration(seconds: 5);

  ScramAuthentication(String secret, {challengeTimeout}) {
    if (challengeTimeout != null) {
      this._challengeTimeout = challengeTimeout;
    }
    this._secret = Saslprep.saslprep(secret);
  }

  /// This method generates the [authExtra] 'nonce' value and starts the timeout
  /// to cancel the challenge if it took exceptionally long to receive
  @override
  Future<void> hello(String realm, Details details) {
    var random = Random.secure();
    List<int> noneBytes = [for (int i = 0; i < 16; i++) random.nextInt(256)];
    if (details.authid != null) {
      details.authid = Saslprep.saslprep(details.authid);
      this._authid = details.authid;
    }
    if (details.authextra == null) {
      details.authextra = HashMap();
    }
    details.authextra['nonce'] = base64.encode(noneBytes);
    details.authextra['channel_binding'] = null;
    _helloNonce = details.authextra['nonce'];
    Future.delayed(_challengeTimeout, () => _helloNonce = null);
    return Future.value();
  }

  @override
  Future<Authenticate> challenge(Extra extra) {
    if (extra.nonce == null || !_helloNonce.contains(extra.nonce.substring(0,12))){
      return Future.error(Exception("Wrong nonce"));
    }
    Authenticate authenticate = Authenticate();

    authenticate.extra = HashMap();
    authenticate.extra["nonce"] = extra.nonce;
    authenticate.extra["channel_binding"] = null;
    authenticate.extra["cbind_data"] = null;
    if (extra.kdf == KDF_PBKDF2) {
      authenticate.signature = challengePBKDF2(_authid, _helloNonce, extra, authenticate.extra);
    }
    if (authenticate.signature == null) {
      throw Exception("not supported key derivation function used " + extra.kdf);
    }
    return Future.value(authenticate);
  }

  /// Calculates the client proof according to the [WAMP-SCRAM specs](https://wamp-proto.org/_static/gen/wamp_latest.html#authmessage) where
  /// [authId] is the username that has already been saslpreped with [Saslprep.saslprep(input)] and [helloNonce] is a randomly generated nonce according
  /// to the WAMP-SCRAM specs.
  String challengePBKDF2(String authId, String helloNonce, Extra challengeExtra, HashMap<String, Object> authExtra) {
    Uint8List saltedPassword = CraAuthentication.deriveKey(_secret, challengeExtra.salt == null ? CraAuthentication.DEFAULT_KEY_SALT : challengeExtra.salt, iterations: challengeExtra.iterations, keylen: challengeExtra.keylen);
    Uint8List clientKey = CraAuthentication.encodeHmac(saltedPassword, challengeExtra.keylen, "Client Key".codeUnits).codeUnits;
    Uint8List StoredKey = SHA256Digest().process(clientKey);
    Uint8List clientSignature = CraAuthentication.encodeHmac(StoredKey, challengeExtra.keylen, _createAuthMessage(authId, helloNonce, authExtra, challengeExtra).codeUnits).codeUnits;
    return base64.encode([for (int i = 0; i < clientKey.length; i++) clientKey[i]^clientSignature[i]]);
  }

  /// This creates the SCRAM authmessage according to the [WAMP-SCRAM specs](https://wamp-proto.org/_static/gen/wamp_latest.html#authmessage)
  String _createAuthMessage(String authId, String helloNonce, HashMap authExtra, Extra challengeExtra) {
    String ClientFirstBare = "n=" + Saslprep.saslprep(authId) + "," + "r=" + helloNonce;
    String ServerFirst = "r=" + challengeExtra.nonce + "," + "s=" + challengeExtra.salt + "," + "i=" + challengeExtra.iterations.toString();
    String CBindName = authExtra['channel_binding'];
    String CBindData = authExtra['cbind_data'];
    String CBindFlag = CBindName == null ?"n":"p=" + CBindName;
    String CBindInput = CBindFlag + ",," + (CBindData == null ?"":base64.decode(CBindData));
    String ClientFinalNoProof = "c=" + base64.encode(CBindInput.codeUnits) + "," + "r=" + authExtra['nonce'];
    return ClientFirstBare + "," + ServerFirst + "," + ClientFinalNoProof;
  }

  @override
  getName() {
    return "wamp-scram";
  }
}

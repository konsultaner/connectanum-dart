import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:saslprep/saslprep.dart';

import '../message/authenticate.dart';
import '../message/challenge.dart';
import '../message/details.dart';
import 'abstract_authentication.dart';

class ScramAuthentication extends AbstractAuthentication {

  static final KDF_PBKDF2 = 'pbkdf2';

  List<String> _clientFirstMessageNonces = [];
  Duration _challengeTimeout = new Duration(seconds: 5);

  ScramAuthentication({challengeTimeout}) {
    if (challengeTimeout != null) {
      this._challengeTimeout = challengeTimeout;
    }
  }

  /// This method generates the [authExtra] 'nonce' value and starts the timeout
  /// to cancel the challenge if it took exceptionally long to receive
  @override
  Future<void> hello(String realm, Details details) {
    var random = Random.secure();
    List<int> noneBytes = [for (int i = 0; i < 16; i++) random.nextInt(256)];
    if (details.authid != null) {
      details.authid = Saslprep.saslprep(details.authid);
    }
    if (details.authextra == null) {
      details.authextra = HashMap();
    }
    details.authextra['nonce'] = base64.encode(noneBytes);
    details.authextra['channel_binding'] = null;
    _clientFirstMessageNonces.add(details.authextra['nonce']);
    Future.delayed(_challengeTimeout, () => _clientFirstMessageNonces.remove(details.authextra['nonce']));
    return Future.value();
  }

  @override
  Future<Authenticate> challenge(Extra extra) {
    if (extra.nonce == null || !_clientFirstMessageNonces.contains(extra.nonce.substring(0,12))){
      return Future.error(Exception("Wrong nonce"));
    }
    Authenticate authenticate = Authenticate();
    if (extra.kdf == KDF_PBKDF2) {

    }
    authenticate.extra = HashMap();
    authenticate.extra["nonce"] = extra.nonce;
    authenticate.extra["channel_binding"] = null;
    authenticate.extra["cbind_data"] = null;
    throw UnimplementedError("Not implemented yet");
  }

  @override
  getName() {
    return "wamp-scram";
  }

}

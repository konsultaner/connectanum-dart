import 'dart:collection';
import 'dart:convert';
import '../message/authenticate.dart';
import '../message/challenge.dart';
import '../message/details.dart';
import 'abstract_authentication.dart';

import 'package:pinenacl/api.dart' show SigningKey;

class CryptosignAuthentication extends AbstractAuthentication {

  final SigningKey privateKey;
  final String channelBinding;

  CryptosignAuthentication(this.privateKey, this.channelBinding): assert (privateKey != null);

  factory CryptosignAuthentication.fromRawBase64(String base64PrivateKey) {
    return CryptosignAuthentication(
        SigningKey.fromSeed(base64.decode(base64PrivateKey).toList()),
        null
    );
  }

  /// This method is called by the session if the router returns the challenge or
  /// the challenges [extra] respectively. This method uses the passed hex
  /// encoded challenge and signs it with the given private key
  @override
  Future<Authenticate> challenge(Extra extra) {
    if (extra.channel_binding != channelBinding) {
      return Future.error(Exception('Channel Binding does not match'));
    }
    if (extra.challenge.length % 2 != 0) {
      return Future.error(Exception('Wrong challenge length'));
    }
    var authenticate = Authenticate();

    authenticate.extra = HashMap<String, Object>();
    authenticate.extra['channel_binding'] = channelBinding;
    var binaryChallenge = [
      for (var i = 0; i < extra.challenge.length; i+=2)
        int.parse(extra.challenge[i]+extra.challenge[i+1], radix: 16)
    ];
    authenticate.signature = privateKey.sign(binaryChallenge).encode();
  }

  /// This method is called by the session to modify the hello [details] for
  /// a given [realm]. Cryptosign will add a 'pubkey' and a 'channel_binding'
  /// to the authextra
  @override
  Future<void> hello(String realm, Details details) {
    details.authextra['pubkey'] = privateKey.publicKey.encode();
    details.authextra['channel_binding'] = channelBinding ?? 'null';
    return Future.value();
  }

  /// This method is called by the session to identify the authentication name.
  @override
  String getName() {
    return 'cryptosign';
  }

}
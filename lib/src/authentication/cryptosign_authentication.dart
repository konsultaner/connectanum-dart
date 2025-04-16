import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:connectanum/src/authentication/cryptosign/pkcs8.dart';
import 'package:pinenacl/ed25519.dart';

import '../message/authenticate.dart';
import '../message/challenge.dart';
import '../message/details.dart';
import 'abstract_authentication.dart';

import 'cryptosign/pem.dart';
import 'cryptosign/ppk.dart';

class CryptosignAuthentication extends AbstractAuthentication {
  static final String channelBindingTlsUnique = 'tls-unique';
  final StreamController<Extra> _challengeStreamController =
      StreamController.broadcast();

  final SigningKey privateKey;
  final String? channelBinding;

  /// This is the default constructor that will take an already gathered [privateKey]
  /// integer list to initialize the cryptosign authentication method.
  CryptosignAuthentication(this.privateKey, this.channelBinding) {
    if (channelBinding != null) {
      throw UnimplementedError('Channel binding is not supported yet!');
    }
  }

  /// When the challenge starts the stream will provide the current [Extra] in
  /// case the client needs some additional information to challenge the server.
  @override
  Stream<Extra> get onChallenge => _challengeStreamController.stream;

  /// This method takes a [ppkFileContent] and reads its private key to make
  /// the authentication process possible with crypto sign. The [ppkFileContent]
  /// must have a ed25519 key file. If the file was password protected, the
  /// optional [password] will decrypt the private key.
  factory CryptosignAuthentication.fromPuttyPrivateKey(String ppkFileContent,
      {String? password}) {
    return CryptosignAuthentication(
        SigningKey.fromSeed(
            Ppk.loadPrivateKeyFromPpk(ppkFileContent, password: password)),
        null);
  }

  /// This method takes a [openSshFileContent] and reads its private key to make
  /// the authentication process possible with crypto sign. The [openSshFileContent]
  /// must have a ed25519 key file. If the file was password protected, the
  /// optional [password] will decrypt the private key.
  factory CryptosignAuthentication.fromOpenSshPrivateKey(
      String openSshFileContent,
      {String? password}) {
    return CryptosignAuthentication(
        SigningKey.fromSeed(Pem.loadPrivateKeyFromOpenSSHPem(openSshFileContent,
            password: password)),
        null);
  }

  /// This method takes a [pkcs8FileContent] and reads its private key to make
  /// the authentication process possible with crypto sign. The
  /// [pkcs8FileContent] must have a ed25519 key file. If the file was password
  /// protected, you may convert it into a unprotected file first. Password
  /// protection is not supported yet.
  factory CryptosignAuthentication.fromPkcs8PrivateKey(
      String pkcs8FileContent) {
    return CryptosignAuthentication(
        SigningKey.fromSeed(
            Pkcs8.loadPrivateKeyFromPKCS8Ed25519(pkcs8FileContent)),
        null);
  }

  /// This method takes a given [base64PrivateKey] to make crypto sign
  /// possible. This key needs to generated to be used with the ed25519 algorithm
  factory CryptosignAuthentication.fromBase64(String base64PrivateKey) {
    return CryptosignAuthentication(
        SigningKey.fromSeed(base64.decode(base64PrivateKey)), null);
  }

  /// This method takes a given [hexPrivateKey] to make crypto sign
  /// possible. This key needs to generated to be used with the ed25519 algorithm
  factory CryptosignAuthentication.fromHex(String? hexPrivateKey) {
    return CryptosignAuthentication(
        SigningKey.fromSeed(hexToBin(hexPrivateKey)), null);
  }

  /// This method is called by the session if the router returns the challenge or
  /// the challenges [extra] respectively. This method uses the passed hex
  /// encoded challenge and signs it with the given private key
  @override
  Future<Authenticate> challenge(Extra extra) async {
    await AbstractAuthentication.streamAddAwaited<Extra>(
        _challengeStreamController, extra);

    if (extra.channelBinding != channelBinding) {
      return Future.error(Exception('Channel Binding does not match'));
    }
    if (extra.challenge!.length % 2 != 0) {
      return Future.error(Exception('Wrong challenge length'));
    }
    var authenticate = Authenticate();

    authenticate.extra = HashMap<String, Object?>();
    authenticate.extra!['channel_binding'] = channelBinding;
    var binaryChallenge = hexToBin(extra.challenge);
    authenticate.signature =
        privateKey.sign(binaryChallenge).encode(Base16Encoder.instance);
    return authenticate;
  }

  /// This method converts a given [hexString] to its byte representation.
  static Uint8List hexToBin(String? hexString) {
    if (hexString == null || hexString.length % 2 != 0) {
      throw Exception('odd hex string length');
    }

    return Uint8List.fromList([
      for (var i = 0; i < hexString.length; i += 2)
        int.parse(hexString[i] + hexString[i + 1], radix: 16)
    ]);
  }

  /// This method is called by the session to modify the hello [details] for
  /// a given [realm]. Cryptosign will add a 'pubkey' and a 'channel_binding'
  /// to the authextra
  @override
  Future<void> hello(String? realm, Details details) {
    details.authextra ??= <String, String?>{};
    details.authextra!['pubkey'] =
        privateKey.publicKey.encode(Base16Encoder.instance);
    details.authextra!['channel_binding'] = channelBinding;
    return Future.value();
  }

  /// This method is called by the session to identify the authentication name.
  @override
  String getName() {
    return 'cryptosign';
  }
}

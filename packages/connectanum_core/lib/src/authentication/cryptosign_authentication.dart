import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:connectanum_core/src/message/authenticate.dart';
import 'package:connectanum_core/src/message/challenge.dart';
import 'package:connectanum_core/src/message/details.dart';
import 'package:pinenacl/ed25519.dart';

import 'abstract_authentication.dart';
import 'cryptosign/pem.dart';
import 'cryptosign/pkcs8.dart';
import 'cryptosign/ppk.dart';

class CryptosignAuthentication extends AbstractAuthentication {
  CryptosignAuthentication(this.privateKey, this.channelBinding) {
    if (channelBinding != null) {
      throw UnimplementedError('Channel binding is not supported yet!');
    }
  }

  final StreamController<Extra> _challengeStreamController =
      StreamController.broadcast();

  final SigningKey privateKey;
  final String? channelBinding;

  factory CryptosignAuthentication.fromPuttyPrivateKey(
    String ppkFileContent, {
    String? password,
  }) {
    return CryptosignAuthentication(
      SigningKey.fromSeed(
        Ppk.loadPrivateKeyFromPpk(ppkFileContent, password: password),
      ),
      null,
    );
  }

  factory CryptosignAuthentication.fromOpenSshPrivateKey(
    String openSshFileContent, {
    String? password,
  }) {
    return CryptosignAuthentication(
      SigningKey.fromSeed(
        Pem.loadPrivateKeyFromOpenSSHPem(
          openSshFileContent,
          password: password,
        ),
      ),
      null,
    );
  }

  factory CryptosignAuthentication.fromPkcs8PrivateKey(
    String pkcs8FileContent,
  ) {
    return CryptosignAuthentication(
      SigningKey.fromSeed(
        Pkcs8.loadPrivateKeyFromPKCS8Ed25519(pkcs8FileContent),
      ),
      null,
    );
  }

  factory CryptosignAuthentication.fromBase64(String base64PrivateKey) {
    return CryptosignAuthentication(
      SigningKey.fromSeed(base64.decode(base64PrivateKey)),
      null,
    );
  }

  factory CryptosignAuthentication.fromHex(String? hexPrivateKey) {
    return CryptosignAuthentication(
      SigningKey.fromSeed(hexToBin(hexPrivateKey)),
      null,
    );
  }

  @override
  Stream<Extra> get onChallenge => _challengeStreamController.stream;

  @override
  Future<void> hello(String? realm, Details details) {
    details.authextra ??= <String, String?>{};
    details.authextra!['pubkey'] = privateKey.publicKey.encode(
      Base16Encoder.instance,
    );
    details.authextra!['channel_binding'] = channelBinding;
    return Future.value();
  }

  @override
  Future<Authenticate> challenge(Extra extra) async {
    await AbstractAuthentication.streamAddAwaited<Extra>(
      _challengeStreamController,
      extra,
    );

    if (extra.channelBinding != channelBinding) {
      return Future.error(Exception('Channel Binding does not match'));
    }
    if (extra.challenge == null || extra.challenge!.length % 2 != 0) {
      return Future.error(Exception('Wrong challenge length'));
    }
    final authenticate = Authenticate();

    authenticate.extra = HashMap<String, Object?>();
    authenticate.extra!['channel_binding'] = channelBinding;
    final binaryChallenge = hexToBin(extra.challenge);
    authenticate.signature = privateKey
        .sign(binaryChallenge)
        .encode(Base16Encoder.instance);
    return authenticate;
  }

  static Uint8List hexToBin(String? hexString) {
    if (hexString == null || hexString.length % 2 != 0) {
      throw Exception('odd hex string length');
    }

    return Uint8List.fromList([
      for (var i = 0; i < hexString.length; i += 2)
        int.parse(hexString[i] + hexString[i + 1], radix: 16),
    ]);
  }

  @override
  String getName() => 'cryptosign';
}

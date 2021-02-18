import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes_fast.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/macs/hmac.dart';

import '../message/authenticate.dart';
import '../message/challenge.dart';
import '../message/details.dart';
import 'abstract_authentication.dart';

import 'package:pinenacl/encoding.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pinenacl/api.dart' show SigningKey;

class CryptosignAuthentication extends AbstractAuthentication {

  static final String CHANNEL_BINDUNG_TLS_UNIQUE = 'tls-unique';

  final SigningKey privateKey;
  final String channelBinding;

  CryptosignAuthentication(this.privateKey, this.channelBinding): assert (privateKey != null) {
    if (channelBinding != null) {
      throw UnimplementedError('Channel binding is not supported yet!');
    }
  }

  factory CryptosignAuthentication.fromPuttyPrivateKey(String ppkFileContent, {String password}) {
    return CryptosignAuthentication(
        SigningKey.fromSeed(extractPrivateKeyFromPpk(ppkFileContent, password: password)),
        null
    );
  }

  factory CryptosignAuthentication.fromBase64(String base64PrivateKey) {
    return CryptosignAuthentication(
        SigningKey.fromSeed(base64.decode(base64PrivateKey).toList()),
        null
    );
  }

  factory CryptosignAuthentication.fromHex(String hexPrivateKey) {
    return CryptosignAuthentication(
        SigningKey.fromSeed(hexToBin(hexPrivateKey)),
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
    var binaryChallenge = hexToBin(extra.challenge);
    authenticate.signature = privateKey.sign(binaryChallenge).encode(HexEncoder());
    return Future.value(authenticate);
  }

  static List<int> hexToBin(String hexString) {
    if (hexString == null || hexString.length % 2 != 0) {
      throw Exception('odd hex string length');
    }

    return [
      for (var i = 0; i < hexString.length; i+=2)
        int.parse(hexString[i]+hexString[i+1], radix: 16)
    ];
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
  
  /// This helper method takes a [ppkFileContent] and its [password] and 
  /// extracts the private key into a list. 
  static List<int> extractPrivateKeyFromPpk(String ppkFileContent, {String password}) {
    if(ppkFileContent == null) {
      throw Exception('There is no file content provided to load a private key from!');
    }
    
    var encrypted = false;
    var endOfHeader = false;
    var publicKeyIndex = 0;
    var privateKeyIndex = 0;
    var publicKey = '';
    var privateKey = '';
    List<int> privateMac;
    var lines = ppkFileContent.split('\n');
    var macData = '';
    lines.forEach((element) {
      if (!endOfHeader) {
        if (lines.indexOf(element) == 0 && !element.startsWith('PuTTY-User-Key-File-')) {
          throw Exception('File is no valid putty ssh-2 key file!');
        }
        if (element.startsWith('PuTTY-User-Key-File-')) {
          if (!element.startsWith('PuTTY-User-Key-File-')) {
            throw Exception('Unsupported ssh-2 key file version!');
          }
          if (!element.contains('ssh-ed25519')) {
            throw Exception('The putty key has the wrong encryption method, use ssh-ed25519!');
          }
          macData += 'ssh-ed25519';
        }
        if (element.startsWith('Encryption')) {
          if (!element.contains('none')) {
            if (!element.contains('aes256-cbc')) {
              throw Exception('Unknown or unsupported putty file encryption! Supported values are "none" and "aes256-cbc"');
            }
            encrypted = true;
          }
          macData += element.split(': ')[1].trimRight();
        }
        if (element.startsWith('Comment')) {
          macData += element.split(': ')[1].trimRight();
        }
        if (element.startsWith('Public-Lines')) {
          endOfHeader = true;
          publicKeyIndex = int.parse(element.split(': ')[1].trimRight());
          return;
        }
      } else if (element.startsWith('Private-Lines')) {
        privateKeyIndex = int.parse(element.split(': ')[1].trimRight());
      } else if (publicKeyIndex > 0) {
        publicKey += element.trimRight();
        publicKeyIndex--;
      } else if (privateKeyIndex > 0) {
        privateKey += element.trimRight();
        privateKeyIndex--;
      } else if (element.startsWith('Private-MAC')) {
        privateMac = hexToBin(element.split(': ')[1].trimRight());
      }
    });
    macData += publicKey + privateKey;
    if (privateKey.isNotEmpty) {
      Uint8List privateKeyDecrypted;
      if (encrypted) {
        if (password == null || password.isEmpty) {
          throw Exception('No or empty password provided!');
        }
        privateKeyDecrypted = decodePpkPrivateKey(base64.decode(privateKey), password);
      } else {
        privateKeyDecrypted = base64.decode(privateKey);
      }
      //macCheck(privateMac, macData, password);
      return privateKeyDecrypted.length > 32 ? privateKeyDecrypted.sublist(0,32) : privateKeyDecrypted;
    } else {
      throw Exception('Wrong file format. Could not extract a private key');
    }
  }

  static Uint8List decodePpkPrivateKey(List<int> encryptedPrivateKey, String password) {
    var encryptedPrivateKeyList = Uint8List.fromList(encryptedPrivateKey);
    var key = Uint8List(40);
    SHA1Digest()
      ..update(Uint8List(4), 0, 4)
      ..update(Uint8List.fromList(password.codeUnits), 0, password.codeUnits.length)
      ..doFinal(key, 0);
    SHA1Digest()
      ..update(Uint8List(4)..[3]=1, 0, 4)
      ..update(Uint8List.fromList(password.codeUnits), 0, password.codeUnits.length)
      ..doFinal(key, 20);

    final cbcBlockCipher = CBCBlockCipher(AESFastEngine())
      ..init(false, ParametersWithIV(KeyParameter(key.sublist(0,32)), Uint8List(16)));
    final paddedPlainText = Uint8List(encryptedPrivateKeyList.length);
    var offset = 0;
    while (offset < encryptedPrivateKeyList.length) {
      offset += cbcBlockCipher.processBlock(encryptedPrivateKeyList, offset, paddedPlainText, offset);
    }
    assert(offset == encryptedPrivateKeyList.length);
    return paddedPlainText;
  }

  static void macCheck(List<int> privateMac, String macData, String password) {
    var sha1Hash = SHA1Digest()
      ..update(Uint8List.fromList("putty-private-key-file-mac-key".codeUnits), 0, "putty-private-key-file-mac-key".codeUnits.length);
    if (password != null) {
      sha1Hash.update(Uint8List.fromList(password.codeUnits), 0, password.codeUnits.length);
    }
    var key = Uint8List(20);
    sha1Hash.doFinal(key, 0);

    var macResult = Uint8List(20);
    var mac = HMac(SHA1Digest(), 64);
    mac.init(KeyParameter(key));
    mac.update(Uint8List.fromList(macData.codeUnits), 0, macData.codeUnits.length);
    mac.doFinal(macResult, 0);

    if (macResult.toList() != privateMac) {
      if (password == null) {
        throw Exception('Mac check failed, file is corrupt!');
      } else {
        throw Exception('Wrong password!');
      }
    }
  }
}
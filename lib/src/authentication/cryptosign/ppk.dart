import 'dart:convert';

import 'package:pinenacl/api.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/macs/hmac.dart';

import 'ppk_mac_data.dart';

class Ppk {
  /// This helper method takes a [ppkFileContent] and its [password] and
  /// extracts the private key into a list.
  static Uint8List loadPrivateKeyFromPpk(String? ppkFileContent,
      {String? password}) {
    if (ppkFileContent == null) {
      throw Exception(
          'There is no file content provided to load a private key from!');
    }

    var encrypted = false;
    var endOfHeader = false;
    var publicKeyIndex = 0;
    var privateKeyIndex = 0;
    var publicKey = '';
    var privateKey = '';
    String? privateMac;
    var lines = ppkFileContent.split('\n');
    var macData = PpkMacData();
    for (var line in lines) {
      if (!endOfHeader) {
        if (lines.indexOf(line) == 0 &&
            !line.startsWith('PuTTY-User-Key-File-')) {
          throw Exception('File is no valid putty ssh-2 key file!');
        }
        if (line.startsWith('PuTTY-User-Key-File-')) {
          if (!line.startsWith('PuTTY-User-Key-File-2')) {
            throw Exception('Unsupported ssh-2 key file version!');
          }
          if (!line.trimRight().endsWith('ssh-ed25519')) {
            throw Exception(
                'The putty key has the wrong encryption method, use ssh-ed25519!');
          }
          macData.algorithm = 'ssh-ed25519';
        }
        if (line.startsWith('Encryption')) {
          if (!line.trimRight().endsWith('none')) {
            if (!line.trimRight().endsWith('aes256-cbc')) {
              throw Exception(
                  'Unknown or unsupported putty file encryption! Supported values are "none" and "aes256-cbc"');
            }
            encrypted = true;
          }
          macData.encryption = line.split(': ')[1].trimRight();
        }
        if (line.startsWith('Comment')) {
          macData.comment = line.split(': ')[1].trimRight();
        }
        if (line.startsWith('Public-Lines')) {
          endOfHeader = true;
          publicKeyIndex = int.parse(line.split(': ')[1].trimRight());
          continue;
        }
      } else if (line.startsWith('Private-Lines')) {
        privateKeyIndex = int.parse(line.split(': ')[1].trimRight());
      } else if (publicKeyIndex > 0) {
        publicKey += line.trimRight();
        publicKeyIndex--;
      } else if (privateKeyIndex > 0) {
        privateKey += line.trimRight();
        privateKeyIndex--;
      } else if (line.startsWith('Private-MAC')) {
        privateMac = line.split(': ')[1].trimRight();
      }
    }
    macData.publicKey = base64.decode(publicKey);
    if (privateKey.isNotEmpty) {
      Uint8List privateKeyDecrypted;
      if (encrypted) {
        if (password == null || password.isEmpty) {
          throw Exception('No or empty password provided!');
        }
        privateKeyDecrypted =
            decodePpkPrivateKey(base64.decode(privateKey), password);
      } else {
        privateKeyDecrypted = base64.decode(privateKey);
      }
      macData.privateKey = privateKeyDecrypted;
      ppkMacCheck(privateMac, macData, password);
      return privateKeyDecrypted.sublist(4, 36);
    } else {
      throw Exception('Wrong file format. Could not extract a private key');
    }
  }

  /// This method takes a [encryptedPrivateKey] and decrypts it by useing the
  /// provided [password].
  static Uint8List decodePpkPrivateKey(
      List<int> encryptedPrivateKey, String password) {
    var encryptedPrivateKeyList = Uint8List.fromList(encryptedPrivateKey);
    var key = Uint8List(40);
    SHA1Digest()
      ..update(Uint8List(4), 0, 4)
      ..update(
          Uint8List.fromList(password.codeUnits), 0, password.codeUnits.length)
      ..doFinal(key, 0);
    SHA1Digest()
      ..update(Uint8List(4)..[3] = 1, 0, 4)
      ..update(
          Uint8List.fromList(password.codeUnits), 0, password.codeUnits.length)
      ..doFinal(key, 20);

    final cbcBlockCipher = CBCBlockCipher(AESEngine())
      ..init(false,
          ParametersWithIV(KeyParameter(key.sublist(0, 32)), Uint8List(16)));
    final seed = Uint8List(encryptedPrivateKeyList.length);
    var offset = 0;
    while (offset < encryptedPrivateKeyList.length) {
      offset += cbcBlockCipher.processBlock(
          encryptedPrivateKeyList, offset, seed, offset);
    }
    assert(offset == encryptedPrivateKeyList.length);
    return seed;
  }

  /// This method performs the mac check against the [privateMac] to validate
  /// the files content. It is also capable of testing whether the [password]
  /// was wrong or not. The [macData] is data used to compute the mac and to
  /// compare it to the given [privateMac]
  static void ppkMacCheck(
      String? privateMac, PpkMacData macData, String? password) {
    var sha1Hash = SHA1Digest()
      ..update(Uint8List.fromList('putty-private-key-file-mac-key'.codeUnits),
          0, 'putty-private-key-file-mac-key'.codeUnits.length);
    if (password != null) {
      sha1Hash.update(
          Uint8List.fromList(password.codeUnits), 0, password.codeUnits.length);
    }
    var key = Uint8List(20);
    sha1Hash.doFinal(key, 0);

    var macResult = Uint8List(20);
    var mac = HMac(SHA1Digest(), 64);
    mac.init(KeyParameter(key));
    mac.update(
        Uint8List.fromList([0, 0, 0, macData.algorithm.codeUnits.length]),
        0,
        4);
    mac.update(
        utf8.encode(macData.algorithm), 0, macData.algorithm.codeUnits.length);
    mac.update(
        Uint8List.fromList([0, 0, 0, macData.encryption.codeUnits.length]),
        0,
        4);
    mac.update(utf8.encode(macData.encryption), 0, macData.encryption.length);
    mac.update(
        Uint8List.fromList([0, 0, 0, macData.comment.codeUnits.length]), 0, 4);
    mac.update(utf8.encode(macData.comment), 0, macData.comment.length);
    mac.update(Uint8List.fromList([0, 0, 0, macData.publicKey.length]), 0, 4);
    mac.update(macData.publicKey, 0, macData.publicKey.length);
    mac.update(Uint8List.fromList([0, 0, 0, macData.privateKey.length]), 0, 4);
    mac.update(macData.privateKey, 0, macData.privateKey.length);
    mac.doFinal(macResult, 0);
    if (Base16Encoder.instance.encode(ByteList(macResult)) != privateMac) {
      if (password == null) {
        throw Exception('Mac check failed, file is corrupt!');
      } else {
        throw Exception('Wrong password!');
      }
    }
  }
}

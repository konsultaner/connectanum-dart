import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/ctr.dart';
import 'package:pointycastle/stream/ctr.dart';

import 'bcrypt_pbkdf.dart';

class Pem {
  static final String openSshHeader = '-----BEGIN OPENSSH PRIVATE KEY-----';
  static final String openSshFooter = '-----END OPENSSH PRIVATE KEY-----';

  /// Loads a private key from a [pemFileContent] that has been encoded with the
  /// open ssh file format:
  ///
  /// https://github.com/openssh/openssh-portable/blob/master/PROTOCOL.key
  ///
  /// "openssh-key-v1"0x00    # NULL-terminated "Auth Magic" string
  /// 32-bit length, "none"   # ciphername length and string
  /// 32-bit length, "none"   # kdfname length and string
  /// 32-bit length, nil      # kdf (0 length, no kdf)
  /// 32-bit 0x01             # number of keys, hard-coded to 1 (no length)
  /// 32-bit length, sshpub   # public key in ssh format
  ///     32-bit length, keytype
  ///     32-bit length, pub0
  ///     32-bit length, pub1
  /// 32-bit length for rnd+prv+comment+pad
  ///     64-bit dummy checksum?  # a random 32-bit int, repeated
  ///     32-bit length, keytype  # the private key (including public)
  ///     32-bit length, pub0     # Public Key parts
  ///     32-bit length, pub1
  ///     32-bit length, prv0     # Private Key parts
  ///     ...                     # (number varies by type)
  ///     32-bit length, comment  # comment string
  ///     padding bytes 0x010203  # pad to blocksize
  static Uint8List loadPrivateKeyFromOpenSSHPem(String pemFileContent,
      {String? password}) {
    if (!pemFileContent.startsWith(openSshHeader) ||
        !pemFileContent.startsWith(openSshHeader)) {
      throw Exception('Wrong file format');
    }

    pemFileContent = pemFileContent.replaceAll(RegExp(r'[\n\r]'), '');
    pemFileContent = pemFileContent.substring(openSshHeader.length).trimLeft();
    pemFileContent = pemFileContent
        .substring(0, pemFileContent.length - openSshFooter.length)
        .trimRight();

    var binaryContent =
        base64.decode(pemFileContent.replaceAll(RegExp(r'[\n\r]'), ''));
    var header = binaryContent.sublist(0, binaryContent.indexOf(0));
    if (String.fromCharCodes(header) == 'openssh-key-v1') {
      var readerIndex = header.length + 1;
      var cypherNameLength = _readOpenSshKeyUInt32(binaryContent, readerIndex);
      readerIndex += 4;
      var cypherName =
          _readOpenSshKeyString(binaryContent, readerIndex, cypherNameLength);
      readerIndex += cypherNameLength;
      var keyDerivationFunctionNameLength =
          _readOpenSshKeyUInt32(binaryContent, readerIndex);
      readerIndex += 4;
      var keyDerivationFunctionName = _readOpenSshKeyString(
          binaryContent, readerIndex, keyDerivationFunctionNameLength);
      readerIndex += keyDerivationFunctionNameLength;
      var keyDerivationFunctionOptionsLength =
          _readOpenSshKeyUInt32(binaryContent, readerIndex);
      readerIndex += 4;
      //keyDerivationFunctionLength should be 0 for no kdf
      var keyDerivationFunctionOptions = binaryContent.sublist(
          readerIndex, readerIndex + keyDerivationFunctionOptionsLength);
      readerIndex += keyDerivationFunctionOptionsLength;
      var keyCount = _readOpenSshKeyUInt32(binaryContent, readerIndex);
      if (keyCount != 1) {
        throw Exception('Only single key files are supported for now!');
      }
      readerIndex += 4; //key count should always be 1
      var publicKeyLength = _readOpenSshKeyUInt32(binaryContent, readerIndex);
      readerIndex += 4 + publicKeyLength;
      var privateKeyLength = _readOpenSshKeyUInt32(binaryContent, readerIndex);
      readerIndex += 4;
      var privateKeyIndex = readerIndex;
      if (keyDerivationFunctionName == 'none') {
        return _readOpenSshPrivateKeySeed(binaryContent, readerIndex);
      } else if (keyDerivationFunctionName == 'bcrypt') {
        if (password == null || password.isEmpty) {
          throw Exception('No password supported for encrypted file');
        }
        var keyIv = Uint8List(48);
        var pbkdfSaltLength =
            _readOpenSshKeyUInt32(keyDerivationFunctionOptions, 0);
        BcryptPbkdf.pbkdf(
            password,
            keyDerivationFunctionOptions.sublist(4, 4 + pbkdfSaltLength),
            _readOpenSshKeyUInt32(
                keyDerivationFunctionOptions, 4 + pbkdfSaltLength),
            keyIv);
        var key = keyIv.sublist(0, 32);
        var iv = keyIv.sublist(32, 48);
        late BlockCipher cypher;
        if (cypherName == 'aes256-ctr') {
          cypher = CTRBlockCipher(32, CTRStreamCipher(AESEngine()))
            ..init(false, ParametersWithIV(KeyParameter(key), iv));
        } else if (cypherName == 'aes256-cbc') {
          cypher = CBCBlockCipher(AESEngine())
            ..init(false, ParametersWithIV(KeyParameter(key), iv));
        }

        // Decrypt the cipherText block-by-block

        final paddedPlainText = Uint8List(privateKeyLength); // allocate space
        final cipherText = binaryContent.sublist(
            privateKeyIndex, privateKeyIndex + privateKeyLength);

        var offset = 0;
        while (offset < privateKeyLength) {
          offset +=
              cypher.processBlock(cipherText, offset, paddedPlainText, offset);
        }
        assert(offset == privateKeyLength);

        return _readOpenSshPrivateKeySeed(paddedPlainText, 0);
      } else {
        throw Exception('The given cypherName $cypherName is not supported!');
      }
    } else {
      throw Exception('This is not a valid open ssh key file format!');
    }
  }

  /// reads the private key part as [binaryContent] of an open ssh key. The [readerIndex]
  /// will tell the method where to start reading the key.
  static Uint8List _readOpenSshPrivateKeySeed(
      Uint8List binaryContent, int readerIndex) {
    // var checkSum = _readOpenSshKeyUInt32(binaryContent, readerIndex);
    readerIndex += 8; // repeated 32bit
    var keyTypeLength = _readOpenSshKeyUInt32(binaryContent, readerIndex);
    readerIndex += 4;
    var keyType =
        _readOpenSshKeyString(binaryContent, readerIndex, keyTypeLength);
    readerIndex += keyTypeLength;
    readerIndex += 4 + 32; // no need for the public key part
    if (keyType != 'ssh-ed25519') {
      throw Exception(
          'Cryptosign needs a private key of type ssh-ed25519! Found $keyType');
    }
    var privateKey = binaryContent.sublist(readerIndex += 4, readerIndex += 64);
    var seed = privateKey.sublist(0, 32);
    var commentLength = _readOpenSshKeyUInt32(binaryContent, readerIndex);
    readerIndex += 4;
    // var comment = _readOpenSshKeyString(binaryContent, readerIndex, commentLength);
    readerIndex += commentLength;
    // var padding = binaryContent.sublist(readerIndex);
    return seed;
  }

  /// Extracts a Uint32 from a [bytes] list at a given [offset]
  static int _readOpenSshKeyUInt32(Uint8List bytes, int offset) {
    return Uint8List.fromList(
            bytes.sublist(offset, offset + 4).reversed.toList())
        .buffer
        .asUint32List()[0];
  }

  /// Extracts a String from a [bytes] list at a given [offset] and [length]
  static String _readOpenSshKeyString(Uint8List bytes, int offset, length) {
    return String.fromCharCodes(
        bytes.sublist(offset, offset + length as int?).toList());
  }
}

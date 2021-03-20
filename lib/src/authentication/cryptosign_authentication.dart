import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes_fast.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/ctr.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/stream/ctr.dart';

import '../message/authenticate.dart';
import '../message/challenge.dart';
import '../message/details.dart';
import 'abstract_authentication.dart';

import 'package:pointycastle/digests/sha1.dart';
import 'package:pinenacl/api.dart' show ByteList;

import 'cryptosign/bcrypt_pbkdf.dart';

class CryptosignAuthentication extends AbstractAuthentication {
  static final String CHANNEL_BINDUNG_TLS_UNIQUE = 'tls-unique';
  static final String OPEN_SSH_HEADER = '-----BEGIN OPENSSH PRIVATE KEY-----';
  static final String OPEN_SSH_FOOTER = '-----END OPENSSH PRIVATE KEY-----';

  final SigningKey privateKey;
  final String channelBinding;

  /// This is the default constructor that will take an already gathered [privateKey]
  /// integer list to initialize the cryptosign authentication method.
  CryptosignAuthentication(this.privateKey, this.channelBinding)
      : assert(privateKey != null) {
    if (channelBinding != null) {
      throw UnimplementedError('Channel binding is not supported yet!');
    }
  }

  /// This method takes a [ppkFileContent] and reads its private key to make
  /// the authentication process possible with crypto sign. The [ppkFileContent]
  /// must have a ed25519 key file. If the file was password protected, the
  /// optional [password] will decrypt the private key.
  factory CryptosignAuthentication.fromPuttyPrivateKey(String ppkFileContent,
      {String password}) {
    return CryptosignAuthentication(
        SigningKey.fromSeed(
            loadPrivateKeyFromPpk(ppkFileContent, password: password)),
        null);
  }

  /// This method takes a [openSshFileContent] and reads its private key to make
  /// the authentication process possible with crypto sign. The [openSshFileContent]
  /// must have a ed25519 key file. If the file was password protected, the
  /// optional [password] will decrypt the private key.
  factory CryptosignAuthentication.fromOpenSshPrivateKey(
      String openSshFileContent,
      {String password}) {
    return CryptosignAuthentication(
        SigningKey.fromSeed(loadPrivateKeyFromOpenSSHPem(openSshFileContent,
            password: password)),
        null);
  }

  /// This method takes a given [base64PrivateKey] to make crypto sign
  /// possible. This key needs to generated to be used with the ed25519 algorithm
  factory CryptosignAuthentication.fromBase64(String base64PrivateKey) {
    return CryptosignAuthentication(
        SigningKey.fromSeed(base64.decode(base64PrivateKey).toList()), null);
  }

  /// This method takes a given [hexPrivateKey] to make crypto sign
  /// possible. This key needs to generated to be used with the ed25519 algorithm
  factory CryptosignAuthentication.fromHex(String hexPrivateKey) {
    return CryptosignAuthentication(
        SigningKey.fromSeed(hexToBin(hexPrivateKey)), null);
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
    authenticate.signature =
        privateKey.sign(binaryChallenge).encode(HexCoder.instance);
    return Future.value(authenticate);
  }

  /// This method converts a given [hexString] to its byte representation.
  static List<int> hexToBin(String hexString) {
    if (hexString == null || hexString.length % 2 != 0) {
      throw Exception('odd hex string length');
    }

    return [
      for (var i = 0; i < hexString.length; i += 2)
        int.parse(hexString[i] + hexString[i + 1], radix: 16)
    ];
  }

  /// This method is called by the session to modify the hello [details] for
  /// a given [realm]. Cryptosign will add a 'pubkey' and a 'channel_binding'
  /// to the authextra
  @override
  Future<void> hello(String realm, Details details) {
    details.authextra ??= <String, String>{};
    details.authextra['pubkey'] =
        privateKey.publicKey.encode(HexCoder.instance);
    details.authextra['channel_binding'] = channelBinding;
    return Future.value();
  }

  /// This method is called by the session to identify the authentication name.
  @override
  String getName() {
    return 'cryptosign';
  }

  /// This helper method takes a [ppkFileContent] and its [password] and
  /// extracts the private key into a list.
  static List<int> loadPrivateKeyFromPpk(String ppkFileContent,
      {String password}) {
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
    String privateMac;
    var lines = ppkFileContent.split('\n');
    var macData = PpkMacData();
    lines.forEach((element) {
      if (!endOfHeader) {
        if (lines.indexOf(element) == 0 &&
            !element.startsWith('PuTTY-User-Key-File-')) {
          throw Exception('File is no valid putty ssh-2 key file!');
        }
        if (element.startsWith('PuTTY-User-Key-File-')) {
          if (!element.startsWith('PuTTY-User-Key-File-2')) {
            throw Exception('Unsupported ssh-2 key file version!');
          }
          if (!element.trimRight().endsWith('ssh-ed25519')) {
            throw Exception(
                'The putty key has the wrong encryption method, use ssh-ed25519!');
          }
          macData.algorithm = 'ssh-ed25519';
        }
        if (element.startsWith('Encryption')) {
          if (!element.trimRight().endsWith('none')) {
            if (!element.trimRight().endsWith('aes256-cbc')) {
              throw Exception(
                  'Unknown or unsupported putty file encryption! Supported values are "none" and "aes256-cbc"');
            }
            encrypted = true;
          }
          macData.encryption = element.split(': ')[1].trimRight();
        }
        if (element.startsWith('Comment')) {
          macData.comment = element.split(': ')[1].trimRight();
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
        privateMac = element.split(': ')[1].trimRight();
      }
    });
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

    final cbcBlockCipher = CBCBlockCipher(AESFastEngine())
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
  /// war wrong or not. The [macData] is data used to compute the mac and to
  /// compare it to the given [privateMac]
  static void ppkMacCheck(
      String privateMac, PpkMacData macData, String password) {
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
    if (HexCoder.instance.encode(ByteList.fromList(macResult)) != privateMac) {
      if (password == null) {
        throw Exception('Mac check failed, file is corrupt!');
      } else {
        throw Exception('Wrong password!');
      }
    }
  }

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
      {String password}) {
    if (!pemFileContent.startsWith(OPEN_SSH_HEADER) ||
        !pemFileContent.startsWith(OPEN_SSH_HEADER)) {
      throw Exception('Wrong file format');
    }

    pemFileContent = pemFileContent.replaceAll(RegExp(r'[\n\r]'), '');
    pemFileContent =
        pemFileContent.substring(OPEN_SSH_HEADER.length).trimLeft();
    pemFileContent = pemFileContent
        .substring(0, pemFileContent.length - OPEN_SSH_FOOTER.length)
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
        BlockCipher cypher;
        if (cypherName == 'aes256-ctr') {
          cypher = CTRBlockCipher(32, CTRStreamCipher(AESFastEngine()))
            ..init(false, ParametersWithIV(KeyParameter(key), iv));
        } else if (cypherName == 'aes256-cbc') {
          cypher = CBCBlockCipher(AESFastEngine())
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
        throw Exception(
            'The given cypherName ' + cypherName + ' is not supported!');
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
          'Cryptosign needs a private key of type ssh-ed25519! Found ' +
              keyType);
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
        bytes.sublist(offset, offset + length).toList());
  }

  static void loadPrivateKeyFromOpenPCKS1Pem(String pemFileContent) {
    throw UnimplementedError('This is not implemented yet');
    //pemFileContent.
    //ASN1Parser([111,1,1,1]);
  }

  static void loadPrivateKeyFromOpenPCKS8Pem(String pemFileContent) {
    throw UnimplementedError('This is not implemented yet');
    //pemFileContent.
    //ASN1Parser([111,1,1,1]);
  }
}

class PpkMacData {
  String algorithm;
  String encryption;
  String comment;
  Uint8List publicKey;
  Uint8List privateKey;
}

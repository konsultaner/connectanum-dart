import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/src/authentication/cryptosign/pem.dart';
import 'package:connectanum_core/src/authentication/cryptosign/pkcs8.dart';
import 'package:connectanum_core/src/authentication/cryptosign_authentication.dart';
import 'package:pointycastle/asn1.dart';
import 'package:test/test.dart';

import 'keys.dart';

void main() {
  group('OpenSSH PEM envelope validation', () {
    final original = MockKeys.ed25519Key.value;
    for (final (name, footer) in [
      ('garbage', 'x' * Pem.openSshFooter.length),
      ('wrong end marker', Pem.openSshFooter.replaceFirst('END', 'BAD')),
      ('wrong key type', Pem.openSshFooter.replaceFirst('PRIVATE', 'INVALID')),
      ('missing', ''),
    ]) {
      test('rejects $name footer', () {
        final malformed = original.replaceFirst(Pem.openSshFooter, footer);
        expect(
          () => Pem.loadPrivateKeyFromOpenSSHPem(malformed),
          throwsA(isA<Exception>()),
        );
        expect(
          () => CryptosignAuthentication.fromOpenSshPrivateKey(malformed),
          throwsA(isA<Exception>()),
        );
      });
    }
    test('rejects a wrong header even with a valid footer', () {
      expect(
        () => Pem.loadPrivateKeyFromOpenSSHPem(
          original.replaceFirst('BEGIN', 'START'),
        ),
        throwsA(isA<Exception>()),
      );
    });
    for (final newline in ['\n', '\r\n']) {
      test(
        'accepts line wrapping and a trailing ${newline.length}-byte newline',
        () {
          final expected = Pem.loadPrivateKeyFromOpenSSHPem(original);
          final wrapped = '${original.replaceAll('\n', newline)}$newline';
          final actual = Pem.loadPrivateKeyFromOpenSSHPem(wrapped);
          expect(actual, orderedEquals(expected));
          expect(actual, hasLength(32));
        },
      );
    }
    for (final password in <String?>[null, '']) {
      test('encrypted key requires a nonempty password: $password', () {
        expect(
          () => Pem.loadPrivateKeyFromOpenSSHPem(
            MockKeys.ed25519PasswordPem.value,
            password: password,
          ),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'diagnostic',
              'Exception: No password supported for encrypted file',
            ),
          ),
        );
      });
    }
    test('rejects the wrong binary key-file magic', () {
      final bytes = _openSshBytes(original)..[0] = 0x78;
      expect(
        () => Pem.loadPrivateKeyFromOpenSSHPem(_openSshPem(bytes)),
        throwsA(isA<Exception>()),
      );
    });
    for (final keyCount in [0, 2]) {
      test('rejects advertised key count $keyCount', () {
        expect(
          () => Pem.loadPrivateKeyFromOpenSSHPem(
            _rewriteOpenSshEnvelope(original, keyCount: keyCount),
          ),
          throwsA(isA<Exception>()),
        );
      });
    }
    test('rejects a different private key type', () {
      final binary = latin1.decode(_openSshBytes(original));
      final altered = latin1.encode(
        binary.replaceAll('ssh-ed25519', 'ssh-invalid'),
      );
      expect(
        () => Pem.loadPrivateKeyFromOpenSSHPem(_openSshPem(altered)),
        throwsA(isA<Exception>()),
      );
    });
    test('decrypts an independently generated AES-256-CBC key', () {
      Uint8List? seed;
      expect(() {
        seed = Pem.loadPrivateKeyFromOpenSSHPem(_cbcPem, password: 'test-only');
      }, returnsNormally);
      expect(seed, orderedEquals(_cbcSeed));
    });
    test('does not interpret an unknown KDF as bcrypt', () {
      expect(
        () => Pem.loadPrivateKeyFromOpenSSHPem(
          _rewriteOpenSshEnvelope(_cbcPem, kdf: 'unknown'),
          password: 'test-only',
        ),
        throwsA(isA<Exception>()),
      );
    });
    test('does not interpret an unknown cipher as AES-256-CBC', () {
      expect(
        () => Pem.loadPrivateKeyFromOpenSSHPem(
          _rewriteOpenSshEnvelope(_cbcPem, cipher: 'unknown'),
          password: 'test-only',
        ),
        throwsA(anything),
      );
    });
  });

  group('PKCS8 Ed25519 key boundaries', () {
    final seed = Uint8List.fromList(List.generate(32, (index) => index));
    for (final length in [0, 1, 31, 33, 64]) {
      test('writer rejects a $length-byte seed', () {
        expect(
          () => Pkcs8.fromEd25519Seed(Uint8List(length)),
          throwsArgumentError,
        );
      });
    }
    for (final marker in [
      '-----BEGIN PRIVATE KEY-----',
      '-----END PRIVATE KEY-----',
    ]) {
      test('reader rejects a missing $marker', () {
        expect(
          () => Pkcs8.loadPrivateKeyFromPKCS8Ed25519(
            Pkcs8.fromEd25519Seed(seed).replaceFirst(marker, ''),
          ),
          throwsArgumentError,
        );
      });
    }
    for (final count in [0, 1, 2]) {
      test('rejects an outer sequence with $count fields', () {
        final sequence = ASN1Sequence();
        for (var index = 0; index < count; index++) {
          sequence.add(ASN1Integer(BigInt.zero));
        }
        expect(
          () => Pkcs8.loadPrivateKeyFromPKCS8Ed25519(_pem(sequence.encode())),
          throwsStateError,
        );
      });
    }
    for (final version in [-1, 1, 2]) {
      test('rejects version $version', () {
        expect(
          () => Pkcs8.loadPrivateKeyFromPKCS8Ed25519(
            _pkcs8(seed, version: version),
          ),
          throwsStateError,
        );
      });
    }
    test('rejects an empty algorithm sequence', () {
      expect(
        () => Pkcs8.loadPrivateKeyFromPKCS8Ed25519(_pkcs8(seed, oid: null)),
        throwsStateError,
      );
    });
    for (final oid in ['1.3.101.110', '1.3.101.113', '1.2.840.113549.1.1.1']) {
      test('rejects another key algorithm $oid', () {
        expect(
          () => Pkcs8.loadPrivateKeyFromPKCS8Ed25519(_pkcs8(seed, oid: oid)),
          throwsArgumentError,
        );
      });
    }
    for (final length in [0, 1, 31, 33, 63]) {
      test('rejects a nested $length-byte key', () {
        expect(
          () => Pkcs8.loadPrivateKeyFromPKCS8Ed25519(_pkcs8(Uint8List(length))),
          throwsStateError,
        );
      });
    }
    test(
      'canonical nested seed roundtrip has independent output ownership',
      () {
        final encoded = Pkcs8.fromEd25519Seed(seed);
        final first = Pkcs8.loadPrivateKeyFromPKCS8Ed25519(encoded);
        expect(first, orderedEquals(seed));
        first.fillRange(0, first.length, 0xff);
        expect(
          Pkcs8.loadPrivateKeyFromPKCS8Ed25519(encoded),
          orderedEquals(seed),
        );
        expect(seed, orderedEquals(List.generate(32, (index) => index)));
      },
    );
    test('a parsed nested seed takes priority over legacy raw length', () {
      final nested = ASN1OctetString(octets: seed).encode();
      final padded = Uint8List(64)..setRange(0, nested.length, nested);
      expect(
        Pkcs8.loadPrivateKeyFromPKCS8Ed25519(_pkcs8(padded, nested: false)),
        orderedEquals(seed),
      );
    });
    for (final length in [32, 64]) {
      for (final prefix in [0, 0x04, 0x05, 0x30, 0x80, 0xff]) {
        test('preserves legacy raw $length-byte key with prefix $prefix', () {
          final raw = Uint8List.fromList([
            prefix,
            0,
            ...List.generate(length - 2, (index) => index + 2),
          ]);
          final actual = Pkcs8.loadPrivateKeyFromPKCS8Ed25519(
            _pkcs8(raw, nested: false),
          );
          expect(actual, orderedEquals(raw.take(32)));
          expect(actual, hasLength(32));
        });
      }
    }
    for (final length in [0, 1, 31, 33, 63, 65]) {
      test(
        'malformed inner DER cannot bypass the raw key length guard: $length',
        () {
          final raw = Uint8List(length)..fillRange(0, length, 0xff);
          expect(
            () => Pkcs8.loadPrivateKeyFromPKCS8Ed25519(
              _pkcs8(raw, nested: false),
            ),
            throwsRangeError,
          );
        },
      );
    }
    test('preserves an unsupported inner tag error outside legacy lengths', () {
      final raw = Uint8List(33)..[0] = 0xff;
      expect(
        () => Pkcs8.loadPrivateKeyFromPKCS8Ed25519(_pkcs8(raw, nested: false)),
        throwsA(isA<UnsupportedASN1TagException>()),
      );
    });
  });
}

String _pem(Uint8List bytes) =>
    '-----BEGIN PRIVATE KEY-----\n${base64Encode(bytes)}\n-----END PRIVATE KEY-----';

Uint8List _openSshBytes(String pem) => base64Decode(
  pem
      .replaceAll(Pem.openSshHeader, '')
      .replaceAll(Pem.openSshFooter, '')
      .replaceAll(RegExp(r'\s'), ''),
);

String _openSshPem(List<int> bytes) =>
    '${Pem.openSshHeader}\n${base64Encode(bytes)}\n${Pem.openSshFooter}';

String _rewriteOpenSshEnvelope(
  String pem, {
  String? cipher,
  String? kdf,
  int? keyCount,
}) {
  final bytes = _openSshBytes(pem);
  final view = ByteData.sublistView(bytes);
  var offset = bytes.indexOf(0) + 1;
  final magic = bytes.sublist(0, offset);
  Uint8List readString() {
    final length = view.getUint32(offset);
    offset += 4;
    final value = bytes.sublist(offset, offset + length);
    offset += length;
    return value;
  }

  final originalCipher = readString();
  final originalKdf = readString();
  final options = readString();
  final originalCount = view.getUint32(offset);
  offset += 4;
  final builder = BytesBuilder()..add(magic);
  void writeInt(int value) =>
      builder.add((ByteData(4)..setUint32(0, value)).buffer.asUint8List());
  void writeString(List<int> value) {
    writeInt(value.length);
    builder.add(value);
  }

  writeString(cipher == null ? originalCipher : utf8.encode(cipher));
  writeString(kdf == null ? originalKdf : utf8.encode(kdf));
  writeString(options);
  writeInt(keyCount ?? originalCount);
  builder.add(bytes.sublist(offset));
  return _openSshPem(builder.takeBytes());
}

// The existing public test key re-encrypted using ssh-keygen -p -Z aes256-cbc.
// The password is 'test-only', never a deployment secret.
const _cbcPem = '''-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jYmMAAAAGYmNyeXB0AAAAGAAAABAw6HVPl8
R9aYe7w9n9wHq1AAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIHOsd4LSZlb3xokK
jybt5q1CxL3gHmqhNmaOaCNMX43nAAAAoDLMhz0aZz3cp0TQKqSCt9+cu6w+ltZgB95K4E
D5sEow5zbjoMCWAtoRJ2PrPhHUu0Z7Z8TIu3s6j+qmAv4xsPiB6a8aMPyN2X98Z5Zcbthb
6gVTFhewOJ6/BmJDn4rBIMpqCRaaPOPsVbJgvfjqemsIZDtfTQErXL4gqIBLv44GUcy0eh
DqC/Y5IZ5mGLAlMNFuFVTk69rTJ4O95a3fczY=
-----END OPENSSH PRIVATE KEY-----''';

const _cbcSeed = <int>[
  141,
  73,
  118,
  119,
  135,
  33,
  122,
  2,
  181,
  240,
  18,
  204,
  171,
  163,
  81,
  33,
  160,
  138,
  171,
  176,
  50,
  73,
  106,
  3,
  203,
  14,
  219,
  151,
  10,
  35,
  60,
  212,
];

String _pkcs8(
  Uint8List key, {
  int version = 0,
  String? oid = '1.3.101.112',
  bool nested = true,
}) {
  final algorithm = ASN1Sequence();
  if (oid != null) {
    algorithm.add(ASN1ObjectIdentifier.fromIdentifierString(oid));
  }
  final sequence = ASN1Sequence()
    ..add(ASN1Integer(BigInt.from(version)))
    ..add(algorithm)
    ..add(
      ASN1OctetString(
        octets: nested ? ASN1OctetString(octets: key).encode() : key,
      ),
    );
  return _pem(sequence.encode());
}

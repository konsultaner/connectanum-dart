import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';

class Pkcs8 {
  /// Creates a not encrypted PKCS#8 file from a 32-Byte-Ed25519-Seed.
  ///
  /// PKCS#8 structure (RFC8410) with OID 1.3.101.112 (Ed25519):
  ///
  /// PrivateKeyInfo ::= SEQUENCE {
  ///   version                   INTEGER (0),
  ///   privateKeyAlgorithm       SEQUENCE {
  ///       algorithm               OBJECT IDENTIFIER (1.3.101.112),
  ///       parameters              (ABSENT oder NULL)
  ///   },
  ///   privateKey                OCTET STRING  -- th eseed
  /// }
  static String fromEd25519Seed(Uint8List seed) {
    if (seed.length != 32) {
      throw ArgumentError('Ed25519-Seed has to be of length 32 byte');
    }

    final offsetSeed = Uint8List(2 + seed.length);
    offsetSeed[0] = 0x04;
    offsetSeed[1] = 0x20;
    offsetSeed.setRange(2, 2 + seed.length, seed);

    final versionAsn = ASN1Integer(BigInt.zero);

    final algIdAsn = ASN1Sequence();
    final oidEd25519 = ASN1ObjectIdentifier.fromIdentifierString('1.3.101.112');
    algIdAsn.add(oidEd25519);
    final privateKeyAsn =
        ASN1OctetString(octets: Uint8List.fromList(offsetSeed.toList()));

    final topLevel = ASN1Sequence();
    topLevel.add(versionAsn);
    topLevel.add(algIdAsn);
    topLevel.add(privateKeyAsn);

    // to DER code
    final derBytes = topLevel.encode();

    final base64Text = base64.encode(derBytes.toList());
    const lineLength = 64;
    final buffer = StringBuffer('-----BEGIN PRIVATE KEY-----\n');
    for (var i = 0; i < base64Text.length; i += lineLength) {
      buffer.writeln(base64Text.substring(
          i,
          (i + lineLength < base64Text.length)
              ? i + lineLength
              : base64Text.length));
    }
    buffer.write('-----END PRIVATE KEY-----');

    return buffer.toString();
  }

  /// Reads a not encrypted PKCS#8 file and returns a 32-Byte-Ed25519-Seed.
  ///
  /// PKCS#8 structure (RFC8410) with OID 1.3.101.112 (Ed25519):
  ///
  /// PrivateKeyInfo ::= SEQUENCE {
  ///   version                   INTEGER (0),
  ///   privateKeyAlgorithm       SEQUENCE {
  ///       algorithm               OBJECT IDENTIFIER (1.3.101.112),
  ///       parameters              (ABSENT oder NULL)
  ///   },
  ///   privateKey                OCTET STRING  -- th eseed
  /// }
  static Uint8List loadPrivateKeyFromPKCS8Ed25519(String pem) {
    const header = '-----BEGIN PRIVATE KEY-----';
    const footer = '-----END PRIVATE KEY-----';

    if (!pem.contains(header) || !pem.contains(footer)) {
      throw ArgumentError(
          'Not a valid PKCS#8 PEM (BEGIN/END PRIVATE KEY missing).');
    }

    final body = pem
        .replaceAll(header, '')
        .replaceAll(footer, '')
        .replaceAll(RegExp(r'\s'), '');

    final derBytes = base64.decode(body);

    final asn1Parser = ASN1Parser(derBytes);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    if (topLevelSeq.elements == null || topLevelSeq.elements!.length < 3) {
      throw StateError('Unexpected structure in PKCS#8, to few fields');
    }

    final version = topLevelSeq.elements![0] as ASN1Integer;
    if (version.integer?.toInt() != 0) {
      throw StateError('Unexpected structure in PKCS#8, to few fields');
    }

    final algorithmSeq = topLevelSeq.elements![1] as ASN1Sequence;
    if (algorithmSeq.elements == null || algorithmSeq.elements!.isEmpty) {
      throw StateError('No algorithm identifier found');
    }
    final objectIdentifier = (algorithmSeq.elements![0] as ASN1ObjectIdentifier)
        .objectIdentifierAsString;
    if ("1.3.101.112" != objectIdentifier) {
      throw ArgumentError(
          'The key is not a Ed25519-Key (OID=$objectIdentifier)!');
    }

    final privateKeyOctetStr = topLevelSeq.elements![2] as ASN1OctetString;
    final privateKeyBytes = privateKeyOctetStr.valueBytes;

    Uint8List? ed25519Seed;
    final innerParser = ASN1Parser(privateKeyBytes);
    final possibleInner = innerParser.nextObject();

    if (possibleInner is ASN1OctetString) {
      final inner = possibleInner.valueBytes;
      if (inner?.length == 32) {
        ed25519Seed = inner;
      }
    }

    if (ed25519Seed == null) {
      if (privateKeyBytes?.length == 32) {
        ed25519Seed = privateKeyBytes;
      } else if (privateKeyBytes?.length == 64) {
        ed25519Seed = privateKeyBytes?.sublist(0, 32);
      } else {
        throw StateError(
            'PrivateKey has no valid length (32 or 64); found length: ${privateKeyBytes?.length}');
      }
    }

    return ed25519Seed ?? Uint8List(0);
  }
}

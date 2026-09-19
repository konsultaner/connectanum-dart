import 'dart:convert';
import 'dart:typed_data';

/// Test oracle for WAMP values, independent of Connectanum's codecs.
///
/// Follows https://github.com/msgpack/msgpack/blob/master/spec.md. Extensions,
/// non-string map keys and integers outside JS's exact range are rejected;
/// unsupported values must not silently lose information in comparisons.
Object? decodeReferenceMessagePack(Uint8List bytes) {
  final reader = _Reader(bytes);
  final result = reader.read(0);
  if (reader.offset != bytes.length) {
    throw const FormatException('Trailing MessagePack bytes');
  }
  return result;
}

class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  int offset = 0;
  static final _maxExactInteger = BigInt.parse('9007199254740991');

  Uint8List take(int length) {
    if (length < 0 || length > bytes.length - offset) {
      throw const FormatException('Truncated MessagePack value');
    }
    final result = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return result;
  }

  int integer(int width, {bool signed = false}) {
    final data = take(width);
    var value = BigInt.zero;
    for (final byte in data) {
      value = (value << 8) + BigInt.from(byte);
    }
    if (signed && data.first >= 128) value -= BigInt.one << (8 * width);
    if (value.abs() > _maxExactInteger) {
      throw const FormatException('Integer outside exact reference range');
    }
    return value.toInt();
  }

  String string(int length) => utf8.decode(take(length));

  List<Object?> array(int length, int depth) {
    if (length > bytes.length - offset) {
      throw const FormatException('Truncated MessagePack array');
    }
    return [for (var i = 0; i < length; i++) read(depth + 1)];
  }

  Map<String, Object?> map(int length, int depth) {
    if (length > (bytes.length - offset) ~/ 2) {
      throw const FormatException('Truncated MessagePack map');
    }
    final result = <String, Object?>{};
    for (var i = 0; i < length; i++) {
      final key = read(depth + 1);
      if (key is! String || result.containsKey(key)) {
        throw const FormatException(
          'Non-string or duplicate reference map key',
        );
      }
      result[key] = read(depth + 1);
    }
    return result;
  }

  Object? read(int depth) {
    if (depth > 64) throw const FormatException('Reference nesting limit');
    final tag = take(1).single;
    if (tag <= 0x7f) return tag;
    if (tag >= 0xe0) return tag - 256;
    if (tag >= 0xa0 && tag <= 0xbf) return string(tag - 0xa0);
    if (tag >= 0x90 && tag <= 0x9f) return array(tag - 0x90, depth);
    if (tag >= 0x80 && tag <= 0x8f) return map(tag - 0x80, depth);
    return switch (tag) {
      0xc0 => null,
      0xc2 => false,
      0xc3 => true,
      0xc4 => Uint8List.fromList(take(integer(1))),
      0xc5 => Uint8List.fromList(take(integer(2))),
      0xc6 => Uint8List.fromList(take(integer(4))),
      0xca => ByteData.sublistView(take(4)).getFloat32(0, Endian.big),
      0xcb => ByteData.sublistView(take(8)).getFloat64(0, Endian.big),
      0xcc => integer(1),
      0xcd => integer(2),
      0xce => integer(4),
      0xcf => integer(8),
      0xd0 => integer(1, signed: true),
      0xd1 => integer(2, signed: true),
      0xd2 => integer(4, signed: true),
      0xd3 => integer(8, signed: true),
      0xd9 => string(integer(1)),
      0xda => string(integer(2)),
      0xdb => string(integer(4)),
      0xdc => array(integer(2), depth),
      0xdd => array(integer(4), depth),
      0xde => map(integer(2), depth),
      0xdf => map(integer(4), depth),
      _ => throw const FormatException('Unsupported reference MessagePack tag'),
    };
  }
}

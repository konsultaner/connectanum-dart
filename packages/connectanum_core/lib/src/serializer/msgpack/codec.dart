import 'dart:typed_data';

import 'package:msgpack_dart/msgpack_dart.dart' as delegate;

import '../limits.dart';

const _maximumUint32 = 0xffffffff;
const _minimumInt32 = -0x80000000;
const _uint32Base = 0x100000000;
const _maximumExactInteger = 0x20000000000000;
final _supports64BitAccessors = _probe64BitAccessors();
const _portableCodec = PortableMessagePackCodec();

/// MessagePack backend for runtimes without exact 64-bit byte-data accessors.
///
/// The same backend can be used explicitly when a platform-independent integer
/// range and strict single-value decoding are required.
class PortableMessagePackCodec {
  const PortableMessagePackCodec();

  Uint8List encode(Object? value) => _serializeWithout64BitAccessors(value);

  Object? decode(Uint8List bytes) {
    final decoded = _decodeValue(bytes, 0, 0);
    if (decoded.nextOffset != bytes.length) {
      throw const FormatException('Trailing data after MessagePack value');
    }
    return decoded.value;
  }
}

@pragma('vm:prefer-inline')
@pragma('dart2js:tryInline')
Uint8List serialize(Object? value) {
  // A failed delegate attempt may already consume a streaming iterable. Choose
  // the portable backend up front when the runtime cannot encode wide integers.
  if (!_supports64BitAccessors) {
    return _portableCodec.encode(value);
  }
  try {
    return delegate.serialize(value);
  } on UnsupportedError {
    return _portableCodec.encode(value);
  }
}

@pragma('vm:prefer-inline')
@pragma('dart2js:tryInline')
Object? deserialize(Uint8List bytes) {
  if (!_supports64BitAccessors &&
      bytes.isNotEmpty &&
      (bytes[0] == 0xcf || bytes[0] == 0xd3)) {
    return _portableCodec.decode(bytes);
  }
  try {
    return delegate.deserialize(bytes);
  } on UnsupportedError {
    return _portableCodec.decode(bytes);
  }
}

Uint8List _serializeWithout64BitAccessors(Object? value) {
  if (value is int) {
    if (value > _maximumUint32) {
      return _encodeUint64(value);
    }
    if (value < _minimumInt32) {
      return _encodeInt64(value);
    }
    return delegate.serialize(value);
  }
  if (value is Uint8List || value is ByteData) {
    return delegate.serialize(value);
  }
  if (value is Map) {
    final builder = BytesBuilder(copy: false)
      ..add(_encodeCollectionHeader(value.length, 0x80, 0xde, 0xdf));
    for (final entry in value.entries) {
      builder
        ..add(_portableCodec.encode(entry.key))
        ..add(_portableCodec.encode(entry.value));
    }
    return builder.takeBytes();
  }
  if (value is Iterable) {
    // A virtual toList override can expose conversion options or its result.
    // Own the snapshot while consuming the source iterator exactly once.
    final values = value is List ? value : [for (final item in value) item];
    final builder = BytesBuilder(copy: false)
      ..add(_encodeCollectionHeader(values.length, 0x90, 0xdc, 0xdd));
    for (final item in values) {
      builder.add(_portableCodec.encode(item));
    }
    return builder.takeBytes();
  }
  return delegate.serialize(value);
}

Uint8List _encodeUint64(int value) {
  if (value > _maximumExactInteger) {
    throw const FormatException(
      'MessagePack integer exceeds the exact Dart web range',
    );
  }
  final bytes = Uint8List(9)..[0] = 0xcf;
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(1, value ~/ _uint32Base)
    ..setUint32(5, value % _uint32Base);
  return bytes;
}

Uint8List _encodeInt64(int value) {
  if (value < -_maximumExactInteger) {
    throw const FormatException(
      'MessagePack integer exceeds the exact Dart web range',
    );
  }
  final magnitude = -value;
  var high = magnitude ~/ _uint32Base;
  var low = magnitude % _uint32Base;
  if (low == 0) {
    high = _uint32Base - high;
  } else {
    high = _maximumUint32 - high;
    low = _uint32Base - low;
  }
  final bytes = Uint8List(9)..[0] = 0xd3;
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(1, high)
    ..setUint32(5, low);
  return bytes;
}

Uint8List _encodeCollectionHeader(
  int length,
  int fixedPrefix,
  int sixteenBitPrefix,
  int thirtyTwoBitPrefix,
) {
  if (length <= 15) {
    return Uint8List.fromList([fixedPrefix | length]);
  }
  if (length <= 0xffff) {
    final bytes = Uint8List(3)..[0] = sixteenBitPrefix;
    ByteData.sublistView(bytes).setUint16(1, length);
    return bytes;
  }
  final bytes = Uint8List(5)..[0] = thirtyTwoBitPrefix;
  ByteData.sublistView(bytes).setUint32(1, length);
  return bytes;
}

_DecodedValue _decodeValue(Uint8List bytes, int offset, int parentDepth) {
  if (offset >= bytes.length) {
    throw const FormatException('Truncated MessagePack value');
  }
  final lead = bytes[offset];
  if (lead == 0xcf || lead == 0xd3) {
    return _decode64BitInteger(bytes, offset, lead == 0xd3);
  }

  final collection = _readCollectionHeader(bytes, offset);
  if (collection != null) {
    final depth = enterSerializerContainer(parentDepth);
    var nextOffset = collection.nextOffset;
    if (collection.isMap) {
      if (collection.length > (bytes.length - nextOffset) ~/ 2) {
        throw const FormatException(
          'MessagePack collection length exceeds available bytes',
        );
      }
      final result = <dynamic, dynamic>{};
      for (var index = 0; index < collection.length; index++) {
        final key = _decodeValue(bytes, nextOffset, depth);
        final value = _decodeValue(bytes, key.nextOffset, depth);
        result[key.value] = value.value;
        nextOffset = value.nextOffset;
      }
      return _DecodedValue(result, nextOffset);
    }
    if (collection.length > bytes.length - nextOffset) {
      throw const FormatException(
        'MessagePack collection length exceeds available bytes',
      );
    }
    final result = <dynamic>[];
    for (var index = 0; index < collection.length; index++) {
      final value = _decodeValue(bytes, nextOffset, depth);
      result.add(value.value);
      nextOffset = value.nextOffset;
    }
    return _DecodedValue(result, nextOffset);
  }

  final nextOffset = _readScalarEnd(bytes, offset);
  return _DecodedValue(
    delegate.deserialize(Uint8List.sublistView(bytes, offset, nextOffset)),
    nextOffset,
  );
}

_DecodedValue _decode64BitInteger(
  Uint8List bytes,
  int offset,
  bool signed,
) {
  final end = offset + 9;
  if (end > bytes.length) {
    throw const FormatException('Truncated MessagePack integer');
  }
  final data = ByteData.sublistView(bytes, offset + 1, end);
  final high = signed ? data.getInt32(0) : data.getUint32(0);
  final low = data.getUint32(4);
  // Check the words before arithmetic: JavaScript would round 2^53 + 1 down
  // to the admissible endpoint. At -2^53 every nonzero low word is in range.
  if (high < -0x200000 || high > 0x200000 || (high == 0x200000 && low != 0)) {
    throw const FormatException(
      'MessagePack integer exceeds the exact Dart web range',
    );
  }
  return _DecodedValue(high * _uint32Base + low, end);
}

bool _probe64BitAccessors() {
  try {
    final data = ByteData(8);
    data.setUint64(0, _maximumExactInteger);
    if (data.getUint64(0) != _maximumExactInteger) {
      return false;
    }
    data.setInt64(0, -_maximumExactInteger);
    return data.getInt64(0) == -_maximumExactInteger;
  } on UnsupportedError {
    return false;
  }
}

_CollectionHeader? _readCollectionHeader(Uint8List bytes, int offset) {
  final lead = bytes[offset];
  if ((lead & 0xf0) == 0x80) {
    return _CollectionHeader(lead & 0x0f, offset + 1, true);
  }
  if ((lead & 0xf0) == 0x90) {
    return _CollectionHeader(lead & 0x0f, offset + 1, false);
  }
  if (lead == 0xdc || lead == 0xde) {
    _requireAvailable(bytes, offset + 1, 2);
    return _CollectionHeader(
      ByteData.sublistView(bytes, offset + 1, offset + 3).getUint16(0),
      offset + 3,
      lead == 0xde,
    );
  }
  if (lead == 0xdd || lead == 0xdf) {
    _requireAvailable(bytes, offset + 1, 4);
    return _CollectionHeader(
      ByteData.sublistView(bytes, offset + 1, offset + 5).getUint32(0),
      offset + 5,
      lead == 0xdf,
    );
  }
  return null;
}

int _readScalarEnd(Uint8List bytes, int offset) {
  final lead = bytes[offset];
  if (lead <= 0x7f ||
      lead >= 0xe0 ||
      lead == 0xc0 ||
      lead == 0xc2 ||
      lead == 0xc3) {
    return offset + 1;
  }
  if ((lead & 0xe0) == 0xa0) {
    return _checkedEnd(bytes, offset + 1, lead & 0x1f);
  }
  switch (lead) {
    case 0xcc:
    case 0xd0:
      return _checkedEnd(bytes, offset + 1, 1);
    case 0xcd:
    case 0xd1:
      return _checkedEnd(bytes, offset + 1, 2);
    case 0xce:
    case 0xd2:
    case 0xca:
      return _checkedEnd(bytes, offset + 1, 4);
    case 0xcb:
      return _checkedEnd(bytes, offset + 1, 8);
    case 0xd9:
    case 0xc4:
      return _readLengthPrefixedEnd(bytes, offset, _LengthReader.byte);
    case 0xda:
    case 0xc5:
      return _readLengthPrefixedEnd(bytes, offset, _LengthReader.word);
    case 0xdb:
    case 0xc6:
      return _readLengthPrefixedEnd(bytes, offset, _LengthReader.dword);
    case 0xd4:
      return _checkedEnd(bytes, offset + 2, 1);
    case 0xd5:
      return _checkedEnd(bytes, offset + 2, 2);
    case 0xd6:
      return _checkedEnd(bytes, offset + 2, 4);
    case 0xd7:
      return _checkedEnd(bytes, offset + 2, 8);
    case 0xd8:
      return _checkedEnd(bytes, offset + 2, 16);
    case 0xc7:
      return _readExtensionEnd(bytes, offset, _LengthReader.byte);
    case 0xc8:
      return _readExtensionEnd(bytes, offset, _LengthReader.word);
    case 0xc9:
      return _readExtensionEnd(bytes, offset, _LengthReader.dword);
    default:
      throw const FormatException('Unsupported MessagePack value');
  }
}

// Each MessagePack marker selects its exact header width and byte-data reader.
// Pair them once so callers cannot request an unsupported integer width.
class _LengthReader {
  _LengthReader._(this.bytes, this.read);

  static final byte = _LengthReader._(1, (data) => data.getUint8(0));
  static final word = _LengthReader._(2, (data) => data.getUint16(0));
  static final dword = _LengthReader._(4, (data) => data.getUint32(0));

  final int bytes;
  final int Function(ByteData) read;
}

int _readLengthPrefixedEnd(Uint8List bytes, int offset, _LengthReader width) {
  _requireAvailable(bytes, offset + 1, width.bytes);
  final length = _readLength(bytes, offset + 1, width);
  return _checkedEnd(bytes, offset + 1 + width.bytes, length);
}

int _readExtensionEnd(Uint8List bytes, int offset, _LengthReader width) {
  _requireAvailable(bytes, offset + 1, width.bytes + 1);
  final length = _readLength(bytes, offset + 1, width);
  return _checkedEnd(bytes, offset + 2 + width.bytes, length);
}

int _readLength(Uint8List bytes, int offset, _LengthReader width) {
  final data = ByteData.sublistView(bytes, offset, offset + width.bytes);
  return width.read(data);
}

void _requireAvailable(Uint8List bytes, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > bytes.length) {
    throw const FormatException('Truncated MessagePack value');
  }
}

int _checkedEnd(Uint8List bytes, int offset, int length) {
  _requireAvailable(bytes, offset, length);
  return offset + length;
}

class _DecodedValue {
  const _DecodedValue(this.value, this.nextOffset);

  final Object? value;
  final int nextOffset;
}

class _CollectionHeader {
  const _CollectionHeader(this.length, this.nextOffset, this.isMap);

  final int length;
  final int nextOffset;
  final bool isMap;
}

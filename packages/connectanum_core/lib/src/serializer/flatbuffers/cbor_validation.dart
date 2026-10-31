import '../owned_copy_metrics.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';

// A fixed, small cache retains immutable text only, never a borrowed buffer or
// its owner. Metadata repeats short protocol keys and values on every message.
final _shortAsciiText = List<String?>.filled(64, null);

String _asciiText(Uint8List bytes, int start, int end) {
  final length = end - start;
  if (length == 0) return '';
  if (length > 64) return String.fromCharCodes(bytes, start, end);
  final slot = (length * 7 ^ bytes[start] ^ bytes[end - 1] * 3) & 63;
  final cached = _shortAsciiText[slot];
  if (cached != null && cached.length == length) {
    var index = 0;
    while (index < length && cached.codeUnitAt(index) == bytes[start + index]) {
      index++;
    }
    if (index == length) return cached;
  }
  return _shortAsciiText[slot] = String.fromCharCodes(bytes, start, end);
}

/// Decode strict UTF-8, sharing only bounded immutable ASCII protocol text.
/// The cache never retains [bytes], including external/native backing storage.
String decodeFlatBufferUtf8(Uint8List bytes) {
  if (bytes.length <= 64) {
    var ascii = true;
    for (final byte in bytes) {
      if (byte >= 128) {
        ascii = false;
        break;
      }
    }
    if (ascii) return _asciiText(bytes, 0, bytes.length);
  }
  return utf8.decode(bytes);
}

final _validatedCborSpans = Expando<_ValidatedCborSpan>();

class _ValidatedCborSpan {
  const _ValidatedCborSpan(this.rootMajor, this.rootStringDictionaryKeys);

  final int rootMajor;
  final bool rootStringDictionaryKeys;
}

/// Records a CBOR application span already checked by a native FlatBuffers
/// reader. Only use this for immutable borrowed bytes whose owner keeps the
/// exact validated span unchanged for its full lifetime.
void rememberValidatedFlatBufferCborSpan(
  Uint8List bytes, {
  required int rootMajor,
  bool rootStringDictionaryKeys = false,
}) {
  _validatedCborSpans[bytes] = _ValidatedCborSpan(
    rootMajor,
    rootStringDictionaryKeys,
  );
}

/// Whether this exact borrowed application span was validated for this root.
/// Copies and unrelated lazy CBOR inputs do not inherit validation evidence.
bool isValidatedFlatBufferCborSpan(
  Uint8List bytes, {
  required int rootMajor,
  bool rootStringDictionaryKeys = false,
}) {
  final validated = _validatedCborSpans[bytes];
  return validated?.rootMajor == rootMajor &&
      validated?.rootStringDictionaryKeys == rootStringDictionaryKeys;
}

class FlatBufferCborLimits {
  const FlatBufferCborLimits({
    this.maxBytes = 67108864,
    this.maxDepth = 64,
    this.maxItems = 1000000,
  });
  final int maxBytes;
  final int maxDepth;
  final int maxItems;
}

/// Validate one complete CBOR value before handing bytes to the materializer.
/// Byte-string contents are skipped. Text is checked without allocating strings,
/// except dictionary keys when uniqueness must be checked.
void validateFlatBufferCbor(
  Uint8List bytes, {
  int? rootMajor,
  bool stringDictionaryKeys = false,
  bool rootStringDictionaryKeys = false,
  FlatBufferCborLimits limits = const FlatBufferCborLimits(),
}) => _validateFlatBufferCbor(
  bytes,
  rootMajor: rootMajor,
  stringDictionaryKeys: stringDictionaryKeys,
  rootStringDictionaryKeys: rootStringDictionaryKeys,
  limits: limits,
);

/// Validate native metadata immediately. Tagged values keep eager decoding:
/// semantic tag handlers can reject well-formed CBOR (for example bad dates).
bool validateDeferredFlatBufferMetadata(Uint8List bytes) =>
    !_validateFlatBufferCbor(
      bytes,
      rootMajor: 5,
      stringDictionaryKeys: true,
      limits: const FlatBufferCborLimits(maxBytes: 1048576),
    ).hasTags;

_Scanner _validateFlatBufferCbor(
  Uint8List bytes, {
  int? rootMajor,
  bool stringDictionaryKeys = false,
  bool rootStringDictionaryKeys = false,
  FlatBufferCborLimits limits = const FlatBufferCborLimits(),
}) {
  if (limits.maxBytes < 0 || limits.maxDepth < 1 || limits.maxItems < 1) {
    throw ArgumentError('Invalid CBOR validation limits');
  }
  if (bytes.isEmpty ||
      bytes.length > limits.maxBytes ||
      (rootMajor != null && bytes.first ~/ 32 != rootMajor)) {
    throw const FormatException('Invalid FlatBuffers CBOR container or size');
  }
  final scanner = _Scanner(
    bytes,
    limits,
    stringDictionaryKeys,
    rootStringDictionaryKeys,
  );
  scanner.value(0);
  if (scanner.cursor != bytes.length) scanner.invalid('trailing values');
  return scanner;
}

Map<String, dynamic> decodeFlatBufferMetadata(Uint8List bytes) {
  final scalar = _scalarMetadata(bytes);
  if (scalar != null) return scalar;
  validateFlatBufferCbor(
    bytes,
    rootMajor: 5,
    stringDictionaryKeys: true,
    limits: const FlatBufferCborLimits(maxBytes: 1048576),
  );
  try {
    return _normalize(cbor.decode(bytes)) as Map<String, dynamic>;
  } on Exception {
    throw const FormatException('Invalid FlatBuffers metadata value');
  }
}

// Scalar dictionaries are completely validated while materializing their values.
// Complex values retain the existing full validation and CBOR normalization.
Map<String, dynamic>? _scalarMetadata(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 1048576 || bytes.first ~/ 32 != 5) {
    throw const FormatException('Invalid FlatBuffers CBOR container or size');
  }
  final reader = _Scanner(
    bytes,
    const FlatBufferCborLimits(maxBytes: 1048576),
    true,
    false,
  );
  reader.charge();
  final root = reader.byte();
  final count = root % 32 == 31 ? null : reader.length(root % 32);
  final result = <String, dynamic>{};
  var index = 0;
  while (count == null ? !reader.takeBreak() : index < count) {
    reader.charge();
    final keyHeader = reader.byte();
    if (keyHeader ~/ 32 != 3) reader.invalid('dictionary key');
    final key = reader.string(3, keyHeader % 32, key: true)!;
    if (result.containsKey(key)) reader.invalid('duplicate dictionary key');
    reader.charge();
    final initial = reader.byte();
    final major = initial ~/ 32;
    final info = initial % 32;
    final Object? value;
    if (major == 0 || major == 1) {
      var magnitude = info;
      if (info >= 24) {
        magnitude = 0;
        final maximum = major == 0 ? 9007199254740992 : 9007199254740991;
        for (var i = 0, width = reader.width(info); i < width; i++) {
          final byte = reader.byte();
          if (magnitude > maximum ~/ 256 ||
              (magnitude == maximum ~/ 256 && byte > maximum % 256)) {
            return null;
          }
          magnitude = magnitude * 256 + byte;
        }
      }
      value = major == 0 ? magnitude : -1 - magnitude;
    } else if (major == 3) {
      value = reader.string(3, info, key: true);
    } else if (major == 7 && (info == 20 || info == 21 || info == 22)) {
      value = info == 22 ? null : info == 21;
    } else {
      return null;
    }
    result[key] = value;
    index++;
  }
  if (reader.cursor != bytes.length) reader.invalid('trailing values');
  return result;
}

Object? _normalize(Object? value) {
  if (value is CborBytes) {
    final data = value.bytes;
    return data is Uint8List ? data : OwnedCopyMetrics.copyBytes(data);
  }
  if (value is CborValue && value is! CborList && value is! CborMap) {
    return _normalize(value.toObject());
  }
  if (value is Uint8List) return value;
  if (value is BigInt && value.abs() <= BigInt.from(9007199254740992)) {
    return value.toInt();
  }
  if (value is List) return value.map(_normalize).toList(growable: false);
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        _normalize(entry.key) as String: _normalize(entry.value),
    };
  }
  return value;
}

class _Scanner {
  bool hasTags = false;
  _Scanner(
    this.bytes,
    this.limits,
    this.stringDictionaryKeys,
    this.rootStringDictionaryKeys,
  );
  final Uint8List bytes;
  final FlatBufferCborLimits limits;
  final bool stringDictionaryKeys;
  final bool rootStringDictionaryKeys;
  int cursor = 0;
  int items = 0;

  Never invalid(String reason) =>
      throw FormatException('Invalid FlatBuffers CBOR: $reason');

  void charge() {
    if (++items > limits.maxItems) invalid('item limit');
  }

  int byte() {
    if (cursor >= bytes.length) invalid('truncation');
    return bytes[cursor++];
  }

  void skip(int count) {
    if (count < 0 || count > bytes.length - cursor) invalid('truncation');
    cursor += count;
  }

  int width(int info) => switch (info) {
    24 => 1,
    25 => 2,
    26 => 4,
    27 => 8,
    _ => invalid('additional information'),
  };

  int length(int info) {
    if (info < 24) return info;
    final count = width(info);
    var result = 0;
    for (var i = 0; i < count; i++) {
      result = result * 256 + byte();
      // Stop before any browser integer precision is relevant. A collection or
      // string cannot contain more units than the entire bounded input span.
      if (result > bytes.length) invalid('declared length');
    }
    return result;
  }

  bool takeBreak() {
    if (cursor >= bytes.length) invalid('missing break');
    if (bytes[cursor] != 255) return false;
    cursor++;
    return true;
  }

  bool utf8Range(int start, int end) {
    var ascii = true;
    var index = start;
    while (index < end) {
      if (index + 8 <= end) {
        final blockEnd = index + 8;
        // A multibyte lead or continuation byte sets a high bit and is left
        // to the existing bytewise validator.
        final highBits =
            bytes[index] |
            bytes[index + 1] |
            bytes[index + 2] |
            bytes[index + 3] |
            bytes[index + 4] |
            bytes[index + 5] |
            bytes[index + 6] |
            bytes[index + 7];
        if (highBits < 128) {
          index = blockEnd;
          continue;
        }
        while (index < blockEnd && bytes[index] < 128) {
          index++;
        }
      }
      if (index >= end) break;
      final first = bytes[index++];
      if (first < 128) continue;
      ascii = false;
      final int count;
      final int low;
      final int high;
      if (first >= 0xc2 && first <= 0xdf) {
        count = 1;
        low = 0x80;
        high = 0xbf;
      } else if (first >= 0xe0 && first <= 0xef) {
        count = 2;
        low = first == 0xe0 ? 0xa0 : 0x80;
        high = first == 0xed ? 0x9f : 0xbf;
      } else if (first >= 0xf0 && first <= 0xf4) {
        count = 3;
        low = first == 0xf0 ? 0x90 : 0x80;
        high = first == 0xf4 ? 0x8f : 0xbf;
      } else {
        invalid('UTF-8');
      }
      if (index + count > end || bytes[index] < low || bytes[index] > high) {
        invalid('UTF-8');
      }
      index++;
      for (var i = 1; i < count; i++) {
        if (bytes[index] < 128 || bytes[index] > 191) invalid('UTF-8');
        index++;
      }
    }
    return ascii;
  }

  String? _stringChunk(int major, int chunkInfo, bool key) {
    final count = length(chunkInfo);
    final start = cursor;
    skip(count);
    final ascii = major == 3 && utf8Range(start, cursor);
    if (!key) return null;
    return ascii
        ? _asciiText(bytes, start, cursor)
        : utf8.decode(Uint8List.sublistView(bytes, start, cursor));
  }

  String? string(int major, int info, {bool key = false}) {
    if (info != 31) return _stringChunk(major, info, key);
    final output = key ? StringBuffer() : null;
    while (!takeBreak()) {
      charge();
      final initial = byte();
      if (initial ~/ 32 != major || initial % 32 == 31) {
        invalid('indefinite string chunk');
      }
      final value = _stringChunk(major, initial % 32, key);
      if (key) output!.write(value);
    }
    return output?.toString();
  }

  void value(int depth) {
    charge();
    final initial = byte();
    final major = initial ~/ 32;
    final info = initial % 32;
    switch (major) {
      case 0 || 1:
        if (info >= 24) skip(width(info));
      case 2 || 3:
        string(major, info);
      case 4 || 5:
        if (depth >= limits.maxDepth) invalid('depth limit');
        final count = info == 31 ? null : length(info);
        final keys =
            major == 5 &&
                (stringDictionaryKeys ||
                    (rootStringDictionaryKeys && depth == 0))
            ? <String>{}
            : null;
        var index = 0;
        while (count == null ? !takeBreak() : index < count) {
          if (major == 5 && keys != null) {
            charge();
            final key = byte();
            if (key ~/ 32 != 3) invalid('dictionary key');
            if (!keys.add(string(3, key % 32, key: true)!)) {
              invalid('duplicate dictionary key');
            }
          } else {
            value(depth + 1);
          }
          if (major == 5) value(depth + 1);
          index++;
        }
      case 6:
        hasTags = true;
        if (depth >= limits.maxDepth) invalid('depth limit');
        if (info >= 24) skip(width(info));
        value(depth + 1);
      case 7:
        if (info == 24) {
          if (byte() < 32) invalid('reserved simple value');
        } else if (info >= 25) {
          skip(width(info));
        }
    }
  }
}

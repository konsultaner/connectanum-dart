import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';

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
  final scanner = _Scanner(bytes, limits, stringDictionaryKeys);
  scanner.value(0);
  if (scanner.cursor != bytes.length) scanner.invalid('trailing values');
}

Map<String, dynamic> decodeFlatBufferMetadata(Uint8List bytes) {
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

Object? _normalize(Object? value) {
  if (value is CborBytes) {
    final data = value.bytes;
    return data is Uint8List ? data : Uint8List.fromList(data);
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
  _Scanner(this.bytes, this.limits, this.stringDictionaryKeys);
  final Uint8List bytes;
  final FlatBufferCborLimits limits;
  final bool stringDictionaryKeys;
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

  void utf8Range(int start, int end) {
    var index = start;
    while (index < end) {
      final first = bytes[index++];
      if (first < 128) continue;
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
  }

  String? string(int major, int info, {bool key = false}) {
    String? chunk(int chunkInfo) {
      final count = length(chunkInfo);
      final start = cursor;
      skip(count);
      if (major == 3) utf8Range(start, cursor);
      return key
          ? utf8.decode(Uint8List.sublistView(bytes, start, cursor))
          : null;
    }

    if (info != 31) return chunk(info);
    final output = key ? StringBuffer() : null;
    while (!takeBreak()) {
      charge();
      final initial = byte();
      if (initial ~/ 32 != major || initial % 32 == 31) {
        invalid('indefinite string chunk');
      }
      final value = chunk(initial % 32);
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
        final keys = stringDictionaryKeys && major == 5 ? <String>{} : null;
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

import '../owned_copy_metrics.dart';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:typed_data/typed_buffers.dart';

Uint8List encodeWampFlatBufferCbor(
  Object? value, {
  int maximumBytes = 67108864,
  bool stringDictionaryKeys = false,
}) {
  if (!stringDictionaryKeys) {
    final scalarArray = _tryEncodeScalarArray(value, maximumBytes);
    if (scalarArray != null) return scalarArray;
  }
  if (stringDictionaryKeys) {
    final scalar = _tryEncodeScalarStringMap(value, maximumBytes);
    if (scalar != null) return scalar;
  }
  final normalized = normalizeWampFlatBufferCborInput(
    value,
    maximumBytes: maximumBytes,
    stringDictionaryKeys: stringDictionaryKeys,
  );
  final bytes = cbor.encode(CborValue(normalized));
  if (bytes.length > maximumBytes) {
    throw ArgumentError(
      'Encoded FlatBuffers CBOR value exceeds the byte limit',
    );
  }
  if (bytes is Uint8List) return bytes;
  if (bytes is Uint8Buffer) {
    // This completed encoder buffer is local to this call and is never reused.
    return Uint8List.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  }
  return OwnedCopyMetrics.copyBytes(bytes);
}

/// Encode a small scalar WAMP keyword map without constructing CBOR wrapper
/// objects. More complex maps return `null` and use the regular encoder.
Uint8List? tryEncodeWampFlatBufferScalarKeywordMap(
  Map<String, dynamic> value, {
  int maximumBytes = 67108864,
}) => _tryEncodeScalarStringMap(value, maximumBytes);

// The pinned CBOR encoder uses definite maps below 256 entries. This narrow
// scalar form avoids wrapper/hash/UTF-8 staging allocations for ASCII maps.
// Larger, complex, Unicode or wide values retain the complete normal encoder.
// At most 47 scalar items at depth one are below the existing item/depth limits.
// Oversized inputs fall back so construction/error semantics stay unchanged.
Uint8List? _tryEncodeScalarStringMap(Object? value, int maximumBytes) {
  if (value is! Map || value.length > 23) return null;
  final pairs = List<Object?>.filled(value.length * 2, null);
  var index = 0;
  var length = 1;
  for (final entry in value.entries) {
    final key = entry.key;
    final item = entry.value;
    if (key is! String || key.length > maximumBytes || !_metadataAscii(key)) {
      return null;
    }
    length += _metadataHeaderLength(key.length) + key.length;
    if (item is String) {
      if (item.length > maximumBytes || !_metadataAscii(item)) return null;
      length += _metadataHeaderLength(item.length) + item.length;
    } else if (item is int && item >= -4294967296 && item <= 4294967295) {
      length += _metadataHeaderLength(item < 0 ? -1 - item : item);
    } else if (item == null || item is bool) {
      length++;
    } else {
      return null;
    }
    if (length > maximumBytes) return null;
    pairs[index++] = key;
    pairs[index++] = item;
  }
  if (length > maximumBytes) {
    return null;
  }
  final bytes = Uint8List(length);
  final data = ByteData.sublistView(bytes);
  bytes[0] = 0xa0 | value.length;
  var position = 1;

  for (final item in pairs) {
    if (item is String) {
      // This path has already proved the string is ASCII, where code units are
      // exactly its UTF-8 bytes. Unicode strings use the regular CBOR encoder.
      position = _writeScalarHeader(bytes, data, position, 0x60, item.length);
      for (var i = 0; i < item.length; i++) {
        bytes[position++] = item.codeUnitAt(i);
      }
    } else if (item is int) {
      position = _writeScalarHeader(
        bytes,
        data,
        position,
        item < 0 ? 0x20 : 0,
        item < 0 ? -1 - item : item,
      );
    } else {
      bytes[position++] = item == null
          ? 0xf6
          : item == true
          ? 0xf5
          : 0xf4;
    }
  }
  return bytes;
}

// Short scalar argument arrays avoid constructing the generic CborValue tree.
// Retaining each value during the sizing pass preserves a single snapshot even
// when the caller supplies a custom List implementation.
Uint8List? _tryEncodeScalarArray(Object? value, int maximumBytes) {
  if (value is! List || value is Uint8List) return null;
  final count = value.length;
  if (count > 47) return null;
  final items = List<Object?>.filled(count, null);
  var length = _metadataHeaderLength(count);
  for (var index = 0; index < count; index++) {
    final item = value[index];
    if (item is String) {
      if (item.length > maximumBytes) return null;
      length += _metadataHeaderLength(item.length) + item.length;
    } else if (item is int && item >= -4294967296 && item <= 4294967295) {
      length += _metadataHeaderLength(item < 0 ? -1 - item : item);
    } else if (item == null || item is bool) {
      length++;
    } else {
      return null;
    }
    if (length > maximumBytes) return null;
    items[index] = item;
  }
  if (length > maximumBytes) return null;
  final bytes = Uint8List(length);
  final data = ByteData.sublistView(bytes);
  var position = _writeScalarHeader(bytes, data, 0, 0x80, count);
  for (final item in items) {
    if (item is String) {
      position = _writeScalarHeader(bytes, data, position, 0x60, item.length);
      for (var i = 0; i < item.length; i++) {
        final codeUnit = item.codeUnitAt(i);
        if (codeUnit > 127) return null;
        bytes[position++] = codeUnit;
      }
    } else if (item is int) {
      position = _writeScalarHeader(
        bytes,
        data,
        position,
        item < 0 ? 0x20 : 0,
        item < 0 ? -1 - item : item,
      );
    } else {
      bytes[position++] = item == null
          ? 0xf6
          : item == true
          ? 0xf5
          : 0xf4;
    }
  }
  return bytes;
}

int _writeScalarHeader(
  Uint8List bytes,
  ByteData data,
  int position,
  int major,
  int length,
) {
  if (length < 24) {
    bytes[position++] = major | length;
  } else if (length <= 255) {
    bytes[position++] = major | 24;
    bytes[position++] = length;
  } else if (length <= 65535) {
    bytes[position++] = major | 25;
    data.setUint16(position, length, Endian.big);
    position += 2;
  } else {
    bytes[position++] = major | 26;
    data.setUint32(position, length, Endian.big);
    position += 4;
  }
  return position;
}

bool _metadataAscii(String text) {
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) > 127) return false;
  }
  return true;
}

int _metadataHeaderLength(int value) => value < 24
    ? 1
    : value <= 255
    ? 2
    : value <= 65535
    ? 3
    : 5;

/// Bound and normalize construction before encoding or metadata snapshots.
/// Transferable data is materialized once even if the input aliases it.
Object? normalizeWampFlatBufferCborInput(
  Object? value, {
  int maximumBytes = 67108864,
  bool stringDictionaryKeys = false,
}) => _CborInputBudget(maximumBytes, stringDictionaryKeys).visit(value, 0);

class _CborInputBudget {
  _CborInputBudget(this.maximumBytes, this.stringDictionaryKeys);
  final int maximumBytes;
  final bool stringDictionaryKeys;
  final active = HashSet<Object>.identity();
  final transfers = HashMap<TransferableTypedData, Uint8List>.identity();
  int items = 0;
  int minimumBytes = 0;

  void charge(int bytes) {
    minimumBytes += bytes;
    if (minimumBytes > maximumBytes || ++items > 1000000) {
      throw ArgumentError(
        'FlatBuffers CBOR input exceeds the construction budget',
      );
    }
  }

  Object? visit(Object? value, int depth) {
    if (value is TransferableTypedData) {
      final bytes = transfers.putIfAbsent(
        value,
        () => value.materialize().asUint8List(),
      );
      charge(bytes.length + 1);
      return bytes;
    }
    if (value is Uint8List) {
      charge(value.length + 1);
    } else if (value is String) {
      charge(value.length + 1);
    } else if (value is List || value is Map) {
      charge(1);
      if (depth >= 64 || !active.add(value!)) {
        throw ArgumentError(
          'FlatBuffers CBOR input is cyclic or too deeply nested',
        );
      }
      try {
        if (value is List) {
          List<Object?>? result;
          for (var index = 0; index < value.length; index++) {
            final item = value[index];
            final normalized = visit(item, depth + 1);
            if (!identical(item, normalized)) {
              result ??= value.take(index).toList(growable: true);
            }
            result?.add(normalized);
          }
          return result ?? value;
        }
        Map<Object?, Object?>? result;
        for (final entry in (value as Map).entries) {
          if (stringDictionaryKeys && entry.key is! String) {
            throw ArgumentError('WAMP metadata keys must be strings');
          }
          final key = visit(entry.key, depth + 1);
          final item = visit(entry.value, depth + 1);
          if (!identical(key, entry.key) || !identical(item, entry.value)) {
            result ??= Map<Object?, Object?>.from(value);
          }
          if (result != null) {
            if (!identical(key, entry.key)) result.remove(entry.key);
            result[key] = item;
          }
        }
        return result ?? value;
      } finally {
        active.remove(value);
      }
    } else if (value is DateTime) {
      charge(value.toIso8601String().length + 2);
    } else if (value is BigInt) {
      charge((value.bitLength + 7) ~/ 8 + 1);
    } else if (value == null || value is bool || value is num) {
      charge(1);
    } else {
      throw UnsupportedError('Unsupported WAMP value ${value.runtimeType}');
    }
    return value;
  }
}

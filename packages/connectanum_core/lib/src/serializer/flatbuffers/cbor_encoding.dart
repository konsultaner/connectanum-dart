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
  if (stringDictionaryKeys) {
    final scalar = _tryEncodeScalarMetadata(value, maximumBytes);
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

// The pinned CBOR encoder uses definite maps below 256 entries. This narrow
// scalar form avoids wrapper/hash/UTF-8 staging allocations for ASCII metadata.
// Larger, complex, Unicode or wide values retain the complete normal encoder.
// At most 47 scalar items at depth one are below the existing item/depth limits.
// Oversized inputs fall back so construction/error semantics stay unchanged.
Uint8List? _tryEncodeScalarMetadata(Object? value, int maximumBytes) {
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
  void header(int major, int n) {
    if (n < 24) {
      bytes[position++] = major | n;
    } else if (n <= 255) {
      bytes[position++] = major | 24;
      bytes[position++] = n;
    } else if (n <= 65535) {
      bytes[position++] = major | 25;
      data.setUint16(position, n, Endian.big);
      position += 2;
    } else {
      bytes[position++] = major | 26;
      data.setUint32(position, n, Endian.big);
      position += 4;
    }
  }

  for (final item in pairs) {
    if (item is String) {
      header(0x60, item.length);
      for (var i = 0; i < item.length; i++) {
        bytes[position++] = item.codeUnitAt(i);
      }
    } else if (item is int) {
      header(item < 0 ? 0x20 : 0, item < 0 ? -1 - item : item);
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

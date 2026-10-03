import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';

Uint8List encodeWampFlatBufferCbor(
  Object? value, {
  int maximumBytes = 67108864,
  bool stringDictionaryKeys = false,
}) {
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
  return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
}

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

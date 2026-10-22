import 'dart:convert';
import 'dart:typed_data';

import 'generated/validation_schema.dart';
import 'validation.dart';
import 'validation_types.dart';

/// Read known fields after bounded structural validation. Plain byte vectors
/// alias the original span; this does not materialize application payloads.
Map<String, Object?> readWampFlatBufferFields(Uint8List bytes) {
  validateWampFlatBuffer(bytes);
  final reader = _Reader(bytes);
  return reader.table(reader.data.getUint32(0, Endian.little), wampRootTable);
}

class _Reader {
  _Reader(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  // Most envelopes contain only the root and message tables. Keep their
  // checked views inline; larger graphs retain the original typed map keys.
  int _firstTableOffset = 0;
  int _firstTableReference = 0;
  Map<String, Object?>? _firstTable;
  int _secondTableOffset = 0;
  int _secondTableReference = 0;
  Map<String, Object?>? _secondTable;
  Map<(int, int), Map<String, Object?>>? _otherTables;
  int _firstStringOffset = 0;
  String? _firstString;
  Map<int, String>? _otherStrings;

  int integer(int offset, int width) => switch (width) {
    1 => data.getUint8(offset),
    2 => data.getUint16(offset, Endian.little),
    4 => data.getUint32(offset, Endian.little),
    8 =>
      data.getUint32(offset, Endian.little) +
          data.getUint32(offset + 4, Endian.little) * 4294967296,
    _ => throw StateError('Unsupported pinned field width'),
  };

  int target(int offset) => offset + data.getUint32(offset, Endian.little);

  int defaultScalar(String table, String field) => switch ((table, field)) {
    ('Publish', 'exclude_me') || ('Interrupt', 'mode') => 1,
    ('Heartbeat', 'presence') => 7,
    _ => 0,
  };

  bool boolean(FlatBufferFieldSpec field) =>
      field.width == 1 &&
      field.values.length == 2 &&
      field.values[0] == 0 &&
      field.values[1] == 1;

  Map<String, Object?> table(int offset, int reference) {
    final first = _firstTable;
    if (first != null &&
        offset == _firstTableOffset &&
        reference == _firstTableReference)
      return first;
    final second = _secondTable;
    if (second != null &&
        offset == _secondTableOffset &&
        reference == _secondTableReference)
      return second;
    final cached = _otherTables?[(offset, reference)];
    if (cached != null) return cached;
    final spec = wampValidationTables[reference];
    final vtable = offset - data.getInt32(offset, Endian.little);
    final vtableSize = data.getUint16(vtable, Endian.little);
    final output = <String, Object?>{};
    if (first == null) {
      _firstTableOffset = offset;
      _firstTableReference = reference;
      _firstTable = output;
    } else if (second == null) {
      _secondTableOffset = offset;
      _secondTableReference = reference;
      _secondTable = output;
    } else {
      (_otherTables ??= {})[(offset, reference)] = output;
    }
    for (var slot = 0; slot < spec.fields.length; slot++) {
      final field = spec.fields[slot];
      final entry = 4 + slot * 2;
      final relative = entry < vtableSize
          ? data.getUint16(vtable + entry, Endian.little)
          : 0;
      if (relative == 0) {
        if (field.kind == FlatBufferFieldKind.scalar) {
          final value = defaultScalar(spec.name, field.name);
          output[field.name] = boolean(field) ? value != 0 : value;
        } else {
          output[field.name] = null;
        }
        continue;
      }
      final position = offset + relative;
      switch (field.kind) {
        case FlatBufferFieldKind.scalar:
          final value = integer(position, field.width);
          output[field.name] = boolean(field) ? value != 0 : value;
        case FlatBufferFieldKind.string:
          output[field.name] = string(target(position));
        case FlatBufferFieldKind.table:
          output[field.name] = table(target(position), field.reference);
        case FlatBufferFieldKind.union:
          final tag = output[spec.fields[slot - 1].name] as int;
          output[field.name] = table(target(position), field.values[tag]);
        case FlatBufferFieldKind.scalarVector ||
            FlatBufferFieldKind.stringVector ||
            FlatBufferFieldKind.tableVector:
          output[field.name] = vector(target(position), field);
      }
    }
    return output;
  }

  String string(int offset) {
    final first = _firstString;
    if (first != null && offset == _firstStringOffset) return first;
    final cached = _otherStrings?[offset];
    if (cached != null) return cached;
    final length = data.getUint32(offset, Endian.little);
    final value = utf8.decode(
      Uint8List.sublistView(bytes, offset + 4, offset + 4 + length),
    );
    if (first == null) {
      _firstStringOffset = offset;
      _firstString = value;
    } else {
      (_otherStrings ??= {})[offset] = value;
    }
    return value;
  }

  Object vector(int offset, FlatBufferFieldSpec field) {
    final length = data.getUint32(offset, Endian.little);
    final start = offset + 4;
    if (field.kind == FlatBufferFieldKind.scalarVector &&
        field.width == 1 &&
        field.values.isEmpty) {
      return Uint8List.sublistView(bytes, start, start + length);
    }
    return List<Object?>.generate(length, (index) {
      final position = start + index * field.width;
      return switch (field.kind) {
        FlatBufferFieldKind.scalarVector => integer(position, field.width),
        FlatBufferFieldKind.stringVector => string(target(position)),
        FlatBufferFieldKind.tableVector => table(
          target(position),
          field.reference,
        ),
        _ => throw StateError('Unsupported pinned vector'),
      };
    }, growable: false);
  }
}

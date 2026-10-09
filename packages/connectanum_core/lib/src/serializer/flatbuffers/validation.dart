import 'dart:typed_data';

import 'generated/validation_schema.dart';
import 'validation_types.dart';

/// Limits for structural validation. Opaque byte vectors are bounded by frame
/// size, and are never scanned or decoded by this validator.
class WampFlatBufferValidationLimits {
  const WampFlatBufferValidationLimits({
    this.maxBytes = 64 * 1024 * 1024,
    this.maxDepth = 64,
    this.maxTables = 10000,
    this.maxVectorElements = 1000000,
    this.maxStringBytes = 1024 * 1024,
  });

  final int maxBytes;
  final int maxDepth;
  final int maxTables;
  final int maxVectorElements;
  final int maxStringBytes;
}

/// Check the entire known wire structure before using generated readers.
/// The caller must keep the input unchanged while consuming borrowed views.
void validateWampFlatBuffer(
  Uint8List bytes, {
  WampFlatBufferValidationLimits limits =
      const WampFlatBufferValidationLimits(),
}) {
  if (limits.maxBytes < 0 ||
      limits.maxDepth < 1 ||
      limits.maxTables < 1 ||
      limits.maxVectorElements < 0 ||
      limits.maxStringBytes < 0) {
    throw ArgumentError('Invalid FlatBuffers validation limits');
  }
  if (bytes.length > limits.maxBytes) {
    throw const FormatException('FlatBuffers frame exceeds the byte limit');
  }
  final validator = _Validator(bytes, limits);
  validator.table(validator.target(0), wampRootTable, 1);
}

class _Validator {
  _Validator(this.bytes, this.limits) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  final WampFlatBufferValidationLimits limits;
  final Map<(int, int), int> tables = {};
  var vectorElements = 0;
  var stringBytes = 0;

  Never invalid(String reason) =>
      throw FormatException('Invalid FlatBuffers frame: $reason');

  void range(int offset, int length, [int alignment = 1]) {
    if (offset < 0 ||
        length < 0 ||
        offset > bytes.length - length ||
        offset % alignment != 0) {
      invalid('offset, length or alignment');
    }
  }

  int u16(int offset) {
    range(offset, 2, 2);
    return data.getUint16(offset, Endian.little);
  }

  int u32(int offset) {
    range(offset, 4, 4);
    return data.getUint32(offset, Endian.little);
  }

  int target(int offset) {
    final relative = u32(offset);
    if (relative < 4) invalid('non-forward offset');
    final result = offset + relative;
    range(result, 4, 4);
    return result;
  }

  void scalar(int offset, FlatBufferFieldSpec field) {
    range(offset, field.width, field.width);
    if (field.wampInteger) {
      final low = u32(offset);
      final high = u32(offset + 4);
      if (high > 0x200000 || (high == 0x200000 && low != 0)) {
        invalid('integer exceeds the WAMP range');
      }
    }
    if (field.values.isNotEmpty) {
      final value = switch (field.width) {
        1 => bytes[offset],
        2 => u16(offset),
        4 => u32(offset),
        _ => invalid('unsupported enum width'),
      };
      if (!field.values.contains(value)) invalid('unknown enum value');
    }
  }

  int table(int offset, int reference, int depth) {
    if (depth > limits.maxDepth) invalid('nesting depth limit');
    final key = (offset, reference);
    final previous = tables[key];
    if (previous != null) {
      if (previous == 0) invalid('cyclic table');
      if (depth + previous - 1 > limits.maxDepth) {
        invalid('nesting depth limit');
      }
      return previous;
    }
    if (tables.length >= limits.maxTables) invalid('table count limit');
    tables[key] = 0;
    range(offset, 4, 4);
    final vtable = offset - data.getInt32(offset, Endian.little);
    final vtableSize = u16(vtable);
    final objectSize = u16(vtable + 2);
    if (vtableSize < 4 || vtableSize.isOdd || objectSize < 4) {
      invalid('table header');
    }
    range(vtable, vtableSize, 2);
    range(offset, objectSize, 4);
    final spec = wampValidationTables[reference];
    var unionTag = 0;
    var height = 1;
    void child(int childHeight) {
      if (childHeight + 1 > height) height = childHeight + 1;
    }

    for (var slot = 0; slot < spec.fields.length; slot++) {
      final field = spec.fields[slot];
      final entry = 4 + slot * 2;
      final relative = entry < vtableSize ? u16(vtable + entry) : 0;
      if (relative == 0) {
        if (field.required) invalid('missing required field');
        if (field.kind == FlatBufferFieldKind.union && unionTag != 0) {
          invalid('missing union value');
        }
        unionTag = 0;
        continue;
      }
      final width = field.kind == FlatBufferFieldKind.scalar ? field.width : 4;
      if (relative < 4 || relative > objectSize - width) {
        invalid('field exceeds its table');
      }
      final position = offset + relative;
      switch (field.kind) {
        case FlatBufferFieldKind.scalar:
          scalar(position, field);
          unionTag = field.width == 1 ? bytes[position] : 0;
        case FlatBufferFieldKind.string:
          string(target(position));
        case FlatBufferFieldKind.table:
          child(table(target(position), field.reference, depth + 1));
        case FlatBufferFieldKind.union:
          if (unionTag == 0 || unionTag >= field.values.length) {
            invalid('union discriminator');
          }
          child(table(target(position), field.values[unionTag], depth + 1));
          unionTag = 0;
        case FlatBufferFieldKind.scalarVector:
        case FlatBufferFieldKind.stringVector:
        case FlatBufferFieldKind.tableVector:
          child(vector(target(position), field, depth));
      }
    }
    tables[key] = height;
    return height;
  }

  int vector(int offset, FlatBufferFieldSpec field, int depth) {
    final length = u32(offset);
    final start = offset + 4;
    final scalarVector = field.kind == FlatBufferFieldKind.scalarVector;
    final width = scalarVector ? field.width : 4;
    range(start, length * width, width);
    // Byte vectors hold encoded CBOR or opaque application data. Do not scan
    // their contents, and permit the full configured frame size.
    if (scalarVector && width == 1 && field.values.isEmpty) return 0;
    vectorElements += length;
    if (vectorElements > limits.maxVectorElements) {
      invalid('vector element limit');
    }
    var height = 0;
    for (var index = 0; index < length; index++) {
      final position = start + index * width;
      switch (field.kind) {
        case FlatBufferFieldKind.scalarVector:
          scalar(position, field);
        case FlatBufferFieldKind.stringVector:
          string(target(position));
        case FlatBufferFieldKind.tableVector:
          final childHeight = table(
            target(position),
            field.reference,
            depth + 1,
          );
          if (childHeight > height) height = childHeight;
        default:
          invalid('unsupported vector type');
      }
    }
    return height;
  }

  void string(int offset) {
    final length = u32(offset);
    final start = offset + 4;
    range(start, length + 1);
    stringBytes += length;
    if (stringBytes > limits.maxStringBytes) invalid('string byte limit');
    if (bytes[start + length] != 0) invalid('string terminator');
    final end = start + length;
    var index = start;
    while (index < end) {
      final first = bytes[index++];
      if (first < 0x80) continue;
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
      for (var remaining = 1; remaining < count; remaining++) {
        if (bytes[index] < 0x80 || bytes[index] > 0xbf) invalid('UTF-8');
        index++;
      }
    }
  }
}

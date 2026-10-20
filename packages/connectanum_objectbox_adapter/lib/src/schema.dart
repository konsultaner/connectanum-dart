import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:objectbox/internal.dart';

/// The registered ObjectBox entity layout. Property IDs, not Dart field order,
/// determine FlatBuffers slots. Peers must agree on [fingerprint] before writing.
final class ObjectBoxEntitySchema {
  ObjectBoxEntitySchema.fromModel(
    ModelEntity entity, {
    bool allowRelationIds = false,
    this.maximumBytes = 64 * 1024 * 1024,
  }) : entityId = entity.id.id,
       _idSlot = entity.idProperty.id.id - 1,
       _fields = {
         for (final property in entity.properties)
           property.id.id - 1: property.type,
       } {
    if (maximumBytes < 16 || maximumBytes > 0x7fffffff) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes');
    }
    if (entity.relations.isNotEmpty || entity.backlinks.isNotEmpty) {
      throw UnsupportedError(
        'To-many relations require a separate relation policy',
      );
    }
    if (entity.idProperty.type != OBXPropertyType.Long) {
      throw UnsupportedError('ObjectBox IDs must occupy a 64-bit field');
    }
    final properties = entity.properties.toList()
      ..sort((a, b) => a.id.id.compareTo(b.id.id));
    for (final property in properties) {
      if (property.id.id <= 0 ||
          property.type == OBXPropertyType.Flex ||
          !_supported.contains(property.type)) {
        throw UnsupportedError(
          'Unsupported ObjectBox property ${property.name}',
        );
      }
      if (property.type == OBXPropertyType.Relation && !allowRelationIds) {
        throw UnsupportedError('To-one IDs require allowRelationIds: true');
      }
    }
    fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'format': 'connectanum_objectbox_schema_v1',
              'entity': entity.id.toString(),
              'properties': [
                for (final property in properties)
                  [
                    property.id.toString(),
                    property.type,
                    property.flags,
                    property.relationTarget,
                  ],
              ],
            }),
          ),
        )
        .toString();
  }

  final int entityId;
  final int maximumBytes;
  final int _idSlot;
  final Map<int, int> _fields;
  late final String fingerprint;

  static const _supported = {
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
  };

  /// Validates the complete entity layout without materializing its values.
  /// Returns the encoded ID; zero is permitted for copied ID assignment.
  int validate(Uint8List bytes, {required String schemaFingerprint}) {
    if (schemaFingerprint != fingerprint) {
      throw const FormatException(
        'ObjectBox schema fingerprint does not match',
      );
    }
    if (bytes.length < 16 || bytes.length > maximumBytes) {
      throw const FormatException(
        'ObjectBox FlatBuffer length is outside limits',
      );
    }
    return _EntityVerifier(bytes, _fields, _idSlot).verify();
  }
}

final class _EntityVerifier {
  _EntityVerifier(this.bytes, this.fields, this.idSlot)
    : data = ByteData.sublistView(bytes),
      workRemaining = bytes.length * 4;
  final Uint8List bytes;
  final ByteData data;
  final Map<int, int> fields;
  final int idSlot;
  final _strings = <int>{};
  late int tableEnd;
  int workRemaining;

  Never invalid(String reason) =>
      throw FormatException('Invalid ObjectBox FlatBuffer: $reason');

  void range(int start, int length) {
    if (start < 0 || length < 0 || start > bytes.length - length) {
      invalid('out-of-bounds range');
    }
  }

  int u16(int at) {
    range(at, 2);
    return data.getUint16(at, Endian.little);
  }

  int u32(int at) {
    range(at, 4);
    return data.getUint32(at, Endian.little);
  }

  int indirect(int at, {bool child = true}) {
    final distance = u32(at);
    if (distance < 4) invalid('invalid forward offset');
    final target = at + distance;
    range(target, 4);
    if (target % 4 != 0) invalid('unaligned offset');
    if (child && target < tableEnd) invalid('child overlaps inline fields');
    return target;
  }

  int verify() {
    final table = indirect(0, child: false);
    range(table, 4);
    final vtable = table - data.getInt32(table, Endian.little);
    final vtableLength = u16(vtable);
    final tableLength = u16(vtable + 2);
    if (vtableLength < 4 ||
        vtableLength.isOdd ||
        tableLength < 4 ||
        vtable.isOdd) {
      invalid('invalid table header');
    }
    range(vtable, vtableLength);
    range(table, tableLength);
    tableEnd = table + tableLength;
    if (vtable < tableEnd && vtable + vtableLength > table) {
      invalid('overlapping table and vtable');
    }
    final inlineRanges = <(int, int)>[];
    var idPresent = false;
    var id = 0;
    for (var slot = 0; slot < (vtableLength - 4) ~/ 2; slot++) {
      final offset = u16(vtable + 4 + slot * 2);
      if (offset == 0) continue;
      final type = fields[slot];
      if (type == null) invalid('unknown nonempty property slot $slot');
      final width = _scalarWidth(type) ?? 4;
      if (offset < 4 || offset > tableLength - width) {
        invalid('field outside table');
      }
      final at = table + offset;
      if (at % width != 0) invalid('unaligned field');
      inlineRanges.add((at, at + width));
      if (slot == idSlot) {
        idPresent = true;
        id = data.getUint64(at, Endian.little);
        if (id < 0) invalid('ID exceeds signed 64-bit range');
      }
      if (type == OBXPropertyType.String) {
        string(indirect(at));
      } else if (type >= OBXPropertyType.BoolVector) {
        vector(indirect(at), type);
      } else if (type == OBXPropertyType.Bool && bytes[at] > 1) {
        invalid('invalid boolean');
      }
    }
    inlineRanges.sort((a, b) => a.$1.compareTo(b.$1));
    for (var index = 1; index < inlineRanges.length; index++) {
      if (inlineRanges[index].$1 < inlineRanges[index - 1].$2) {
        invalid('overlapping inline fields');
      }
    }
    if (!idPresent) invalid('ID slot is absent');
    return id;
  }

  static int? _scalarWidth(int type) => switch (type) {
    1 || 2 => 1,
    3 || 4 => 2,
    5 || 7 => 4,
    6 || 8 || 10 || 11 || 12 => 8,
    _ => null,
  };

  void vector(int at, int type) {
    final count = u32(at);
    final start = at + 4;
    final width = switch (type) {
      22 || 23 => 1,
      24 || 25 => 2,
      26 || 28 || 30 => 4,
      27 || 29 || 31 || 32 => 8,
      _ => invalid('unsupported vector'),
    };
    // Dart's pinned builder can place 64-bit elements at a four-byte offset.
    // ObjectBox's real C reader supports that layout (including all physical
    // offsets). `indirect` already checks the vector's four-byte alignment.
    if (count > (bytes.length - start) ~/ width) {
      invalid('invalid vector bounds');
    }
    if (type == OBXPropertyType.StringVector) {
      consume(count);
      for (var index = 0; index < count; index++) {
        string(indirect(start + index * 4));
      }
    } else if (type == OBXPropertyType.BoolVector) {
      consume(count);
      for (var index = 0; index < count; index++) {
        if (bytes[start + index] > 1) invalid('invalid vector boolean');
      }
    }
  }

  void string(int at) {
    if (_strings.contains(at)) return;
    final length = u32(at);
    final start = at + 4;
    range(start, length + 1);
    consume(length + 1);
    if (bytes[start + length] != 0) invalid('missing string terminator');
    var cursor = start;
    final end = start + length;
    while (cursor < end) {
      final first = bytes[cursor++];
      if (first < 0x80) continue;
      int trailing;
      var lower = 0x80;
      var upper = 0xbf;
      if (first >= 0xc2 && first <= 0xdf) {
        trailing = 1;
      } else if (first >= 0xe0 && first <= 0xef) {
        trailing = 2;
        if (first == 0xe0) lower = 0xa0;
        if (first == 0xed) upper = 0x9f;
      } else if (first >= 0xf0 && first <= 0xf4) {
        trailing = 3;
        if (first == 0xf0) lower = 0x90;
        if (first == 0xf4) upper = 0x8f;
      } else {
        invalid('invalid UTF-8 lead byte');
      }
      if (cursor > end - trailing ||
          bytes[cursor] < lower ||
          bytes[cursor] > upper) {
        invalid('invalid UTF-8 continuation');
      }
      cursor++;
      for (var index = 1; index < trailing; index++) {
        if (bytes[cursor] < 0x80 || bytes[cursor] > 0xbf) {
          invalid('invalid UTF-8 continuation');
        }
        cursor++;
      }
    }
    if (_strings.length < 1024) _strings.add(at);
  }

  void consume(int work) {
    workRemaining -= work;
    if (workRemaining < 0) invalid('validation work limit exceeded');
  }
}

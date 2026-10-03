import 'dart:typed_data';

import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'generated/wamp_wamp.proto_generated.dart' as wire;
import 'generated/validation_schema.dart';
import 'validation_types.dart';

/// Reuse a byte vector already constructed in this builder's storage.
/// This reference never adopts external pointers or another allocation.
/// Consume it during the same build, before resetting the builder.
class FlatBufferByteVectorReference {
  FlatBufferByteVectorReference(this.builder, this.offset) {
    if (offset < 4 || offset > builder.offset) {
      throw ArgumentError('Byte vector offset is outside written storage');
    }
  }

  final fb.Builder builder;
  final int offset;
}

/// Write the pinned wire fields directly into a supplied builder. The message
/// codec supplies the projected fields; this kernel does not encode metadata or
/// application objects. The caller finishes/freezes the returned root offset.
int writeWampFlatBufferFields(
  Map<String, Object?> fields,
  fb.Builder builder,
) => _Writer(builder).table(wampRootTable, fields);

class _Writer {
  _Writer(this.builder);
  final fb.Builder builder;

  static final enums = <String, Map<String, int>>{
    'msg_type': {
      for (final value in wire.AnyMessageTypeId.values) value.name: value.value,
    },
    'request_type': {
      for (final value in wire.MessageType.values) value.name: value.value,
    },
    'ppt_scheme': {
      for (final value in wire.Pptscheme.values) value.name: value.value,
    },
    'ppt_serializer': {
      for (final value in wire.Pptserializer.values) value.name: value.value,
    },
    'ppt_cipher': {
      for (final value in wire.Pptcipher.values) value.name: value.value,
    },
    'match': {for (final value in wire.Match.values) value.name: value.value},
    'invoke': {
      for (final value in wire.InvocationPolicy.values) value.name: value.value,
    },
    'mode': {
      for (final value in wire.CancelMode.values) value.name: value.value,
    },
    'method': {
      for (final value in wire.AuthMethod.values) value.name: value.value,
    },
    'authmethod': {
      for (final value in wire.AuthMethod.values) value.name: value.value,
    },
    'authmethods': {
      for (final value in wire.AuthMethod.values) value.name: value.value,
    },
    'authmode': {
      for (final value in wire.AuthMode.values) value.name: value.value,
    },
    'channel_binding': {
      for (final value in wire.TlschannelBinding.values)
        value.name: value.value,
    },
    'kdf': {for (final value in wire.Kdf.values) value.name: value.value},
    for (final name in [
      'authfactor1_type',
      'authfactor2_type',
      'authfactor3_type',
    ])
      name: {
        for (final value in wire.AuthFactorTypeId.values)
          value.name: value.value,
      },
  };

  Never invalid() => throw ArgumentError('Invalid FlatBuffers wire field');

  int integer(FlatBufferFieldSpec field, Object? value) {
    if (value is String) value = enums[field.name]?[value];
    if (value is bool &&
        enums[field.name] == null &&
        field.values.length == 2 &&
        field.values[0] == 0 &&
        field.values[1] == 1) {
      value = value ? 1 : 0;
    }
    if (value is! int || value < 0) invalid();
    final maximum = switch (field.width) {
      1 => 255,
      2 => 65535,
      4 => 4294967295,
      8 => 9007199254740992,
      _ => invalid(),
    };
    if (value > maximum ||
        (field.values.isNotEmpty && !field.values.contains(value))) {
      invalid();
    }
    return value;
  }

  Map<String, Object?> dictionary(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) invalid();
    return value.cast<String, Object?>();
  }

  int table(int reference, Map<String, Object?> fields) {
    final spec = wampValidationTables[reference];
    final names = {for (final field in spec.fields) field.name};
    if (fields.keys.any((key) => !names.contains(key))) invalid();
    final offsets = <int, int>{};
    final scalars = <int, int>{};
    for (var slot = 0; slot < spec.fields.length; slot++) {
      final field = spec.fields[slot];
      final value = fields[field.name];
      if (value == null) {
        if (field.required) invalid();
        if (field.kind == FlatBufferFieldKind.union &&
            integer(
                  spec.fields[slot - 1],
                  fields[spec.fields[slot - 1].name] ?? 0,
                ) !=
                0) {
          invalid();
        }
        continue;
      }
      switch (field.kind) {
        case FlatBufferFieldKind.scalar:
          scalars[slot] = integer(field, value);
        case FlatBufferFieldKind.string:
          if (value is! String) invalid();
          offsets[slot] = builder.writeString(value);
        case FlatBufferFieldKind.table:
          offsets[slot] = table(field.reference, dictionary(value));
        case FlatBufferFieldKind.union:
          final tagField = spec.fields[slot - 1];
          final tag = integer(tagField, fields[tagField.name] ?? 0);
          if (tag == 0 || tag >= field.values.length) invalid();
          offsets[slot] = table(field.values[tag], dictionary(value));
        case FlatBufferFieldKind.scalarVector:
        case FlatBufferFieldKind.stringVector:
        case FlatBufferFieldKind.tableVector:
          offsets[slot] = vector(field, value);
      }
    }
    builder.startTable(spec.fields.length);
    for (final entry in offsets.entries) {
      builder.addOffset(entry.key, entry.value);
    }
    for (final entry in scalars.entries) {
      switch (spec.fields[entry.key].width) {
        case 1:
          builder.addUint8(entry.key, entry.value);
        case 2:
          builder.addUint16(entry.key, entry.value);
        case 4:
          builder.addUint32(entry.key, entry.value);
        case 8:
          builder.addUint64(entry.key, entry.value);
      }
    }
    return builder.endTable();
  }

  int vector(FlatBufferFieldSpec field, Object value) {
    if (value is FlatBufferByteVectorReference) {
      if (field.kind != FlatBufferFieldKind.scalarVector ||
          field.width != 1 ||
          field.values.isNotEmpty ||
          !identical(value.builder, builder)) {
        invalid();
      }
      return value.offset;
    }
    if (value is! List) invalid();
    switch (field.kind) {
      case FlatBufferFieldKind.scalarVector:
        if (field.width == 1 && field.values.isEmpty) {
          if (value is! Uint8List &&
              value.any((item) => item is! int || item < 0 || item > 255)) {
            invalid();
          }
          return builder.writeListUint8(value.cast<int>());
        }
        final integers = [for (final item in value) integer(field, item)];
        return switch (field.width) {
          1 => builder.writeListUint8(integers),
          2 => builder.writeListUint16(integers),
          4 => builder.writeListUint32(integers),
          8 => builder.writeListUint64(integers),
          _ => invalid(),
        };
      case FlatBufferFieldKind.stringVector:
        final strings = <int>[];
        for (final item in value) {
          if (item is! String) invalid();
          strings.add(builder.writeString(item));
        }
        return builder.writeList(strings);
      case FlatBufferFieldKind.tableVector:
        return builder.writeList([
          for (final item in value) table(field.reference, dictionary(item)),
        ]);
      default:
        invalid();
    }
  }
}

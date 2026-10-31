import '../owned_copy_metrics.dart';
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

/// Parts of one byte vector, kept separate until a contiguous view is requested.
class FlatBufferByteVectorParts {
  factory FlatBufferByteVectorParts(List<Uint8List> parts) {
    final retained = List<Uint8List>.unmodifiable(parts);
    var length = 0;
    for (final part in retained) {
      if (part.length > 67108864 - length) {
        throw ArgumentError('FlatBuffers byte vector exceeds the byte limit');
      }
      length += part.length;
    }
    return FlatBufferByteVectorParts._(retained, length);
  }
  FlatBufferByteVectorParts._(this.parts, this.length);
  final List<Uint8List> parts;
  final int length;

  Uint8List toBytes() {
    if (parts.length == 1) return parts.single;
    final builder = CopyAwareBytesBuilder();
    for (final part in parts) {
      builder.add(part);
    }
    return builder.takeBytes();
  }
}

/// Write the pinned wire fields directly into a supplied builder. The message
/// codec supplies the projected fields; this kernel does not encode metadata or
/// application objects. The caller finishes/freezes the returned root offset.
int writeWampFlatBufferFields(
  Map<String, Object?> fields,
  fb.Builder builder, {
  List<DeferredFlatBufferVector>? deferredVectors,
}) {
  final writer = _Writer(builder, deferredVectors);
  return writer.simplePptCall(fields) ?? writer.table(wampRootTable, fields);
}

class _Writer {
  _Writer(this.builder, this.deferredVectors);
  final fb.Builder builder;
  final List<DeferredFlatBufferVector>? deferredVectors;

  // The common opaque CALL needs neither schema-sized scratch lists nor a
  // recursive table walk. Check the complete supported shape before writing;
  // every other control dictionary still uses the generic schema validator.
  int? simplePptCall(Map<String, Object?> fields) {
    if (fields['msg_type'] is! int ||
        fields['msg_type'] != wire.AnyMessageTypeId.Call.value ||
        fields.length != 3 ||
        fields.keys.any(
          (key) => !const {'msg_type', 'msg', 'metadata'}.contains(key),
        )) {
      return null;
    }
    final body = fields['msg'];
    final metadata = fields['metadata'];
    if (body is! Map<String, Object?> ||
        metadata is! Uint8List ||
        metadata.length > 1048576 ||
        body.keys.any(
          (key) => !const {
            'request',
            'procedure',
            'payload',
            'ppt_scheme',
            'ppt_serializer',
          }.contains(key),
        )) {
      return null;
    }
    final request = body['request'];
    final procedure = body['procedure'];
    final payload = body['payload'];
    final scheme = body['ppt_scheme'];
    final serializer = body['ppt_serializer'];
    if (request is! int ||
        request <= 0 ||
        request > 9007199254740992 ||
        procedure is! String ||
        serializer is! int ||
        serializer != wire.Pptserializer.FLATBUFFERS.value ||
        (scheme != null &&
            (scheme is! int ||
                scheme < wire.Pptscheme.minValue ||
                scheme > wire.Pptscheme.maxValue))) {
      return null;
    }
    final reference = payload is FlatBufferByteVectorReference ? payload : null;
    if (reference == null && payload is! Uint8List) return null;
    if (reference != null && !identical(reference.builder, builder)) {
      return null;
    }

    // Match the generic field/offset order exactly, including its empty vector
    // placeholder for fragmented output. The native reference stays borrowed.
    final procedureOffset = builder.writeString(
      procedure,
      asciiOptimization: true,
    );
    final deferred = reference == null && deferredVectors != null;
    final payloadOffset =
        reference?.offset ??
        byteVector(deferred ? const <int>[] : payload as Uint8List);
    final call = wire.CallBuilder(builder)
      ..begin()
      ..addProcedureOffset(procedureOffset)
      ..addPayloadOffset(payloadOffset)
      ..addRequest(request);
    if (scheme != null) {
      call.addPptScheme(wire.Pptscheme.fromValue(scheme as int));
    }
    call.addPptSerializer(wire.Pptserializer.FLATBUFFERS);
    final callOffset = call.finish();
    if (deferred) {
      deferredVectors!.add(
        DeferredFlatBufferVector(callOffset, 5, payload as Uint8List),
      );
    }
    final metadataOffset = byteVector(metadata);
    return (wire.MessageBuilder(builder)
          ..begin()
          ..addMsgOffset(callOffset)
          ..addMetadataOffset(metadataOffset)
          ..addMsgType(wire.AnyMessageTypeId.Call))
        .finish();
  }

  // The pinned schema is constant; reuse field-name sets across frames.
  static final _fieldNames = [
    for (final table in wampValidationTables)
      {for (final field in table.fields) field.name},
  ];

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
    if (value is Map<String, Object?>) return value;
    if (value is! Map) invalid();
    for (final key in value.keys) {
      if (key is! String) invalid();
    }
    return value.cast<String, Object?>();
  }

  int table(int reference, Map<String, Object?> fields) {
    final spec = wampValidationTables[reference];
    final names = _fieldNames[reference];
    for (final key in fields.keys) {
      if (!names.contains(key)) invalid();
    }
    // Schema kinds distinguish offsets from scalars when emitting the table,
    // so one nullable scratch list replaces separate offset/scalar lists.
    final values = List<int?>.filled(spec.fields.length, null);
    List<Object>? borrowed;
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
          values[slot] = integer(field, value);
        case FlatBufferFieldKind.string:
          if (value is! String) invalid();
          values[slot] = builder.writeString(value, asciiOptimization: true);
        case FlatBufferFieldKind.table:
          values[slot] = table(field.reference, dictionary(value));
        case FlatBufferFieldKind.union:
          final tagField = spec.fields[slot - 1];
          final tag = integer(tagField, fields[tagField.name] ?? 0);
          if (tag == 0 || tag >= field.values.length) invalid();
          values[slot] = table(field.values[tag], dictionary(value));
        case FlatBufferFieldKind.scalarVector:
        case FlatBufferFieldKind.stringVector:
        case FlatBufferFieldKind.tableVector:
          if (deferredVectors != null &&
              field.kind == FlatBufferFieldKind.scalarVector &&
              field.width == 1 &&
              (const {'args', 'kwargs', 'payload'}).contains(field.name) &&
              (value is Uint8List || value is FlatBufferByteVectorParts)) {
            values[slot] = byteVector(const <int>[]);
            final retained = borrowed ??= <Object>[];
            retained
              ..add(slot)
              ..add(value);
          } else {
            values[slot] = vector(field, value);
          }
      }
    }
    builder.startTable(spec.fields.length);
    for (var slot = 0; slot < values.length; slot++) {
      final value = values[slot];
      if (value != null &&
          spec.fields[slot].kind != FlatBufferFieldKind.scalar) {
        builder.addOffset(slot, value);
      }
    }
    for (var slot = 0; slot < values.length; slot++) {
      final scalar = values[slot];
      if (scalar == null ||
          spec.fields[slot].kind != FlatBufferFieldKind.scalar) {
        continue;
      }
      switch (spec.fields[slot].width) {
        case 1:
          builder.addUint8(slot, scalar);
        case 2:
          builder.addUint16(slot, scalar);
        case 4:
          builder.addUint32(slot, scalar);
        case 8:
          builder.addUint64(slot, scalar);
      }
    }
    final offset = builder.endTable();
    if (borrowed != null) {
      for (var index = 0; index < borrowed.length; index += 2) {
        final slot = borrowed[index] as int;
        final value = borrowed[index + 1];
        deferredVectors!.add(
          value is Uint8List
              ? DeferredFlatBufferVector(offset, slot, value)
              : DeferredFlatBufferVector.fragmented(
                  offset,
                  slot,
                  value as FlatBufferByteVectorParts,
                ),
        );
      }
    }
    return offset;
  }

  int byteVector(List<int> values) {
    try {
      final result = builder.writeListUint8(values);
      if (builder is! CopyObservedByteVectorBuilder) {
        OwnedCopyMetrics.record(OwnedCopyKind.flatBufferVector, values.length);
      }
      return result;
    } catch (_) {
      if (builder is! CopyObservedByteVectorBuilder) {
        OwnedCopyMetrics.recordFailedCopy();
      }
      rethrow;
    }
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
          return byteVector(value is List<int> ? value : value.cast<int>());
        }
        final integers = [for (final item in value) integer(field, item)];
        return switch (field.width) {
          1 => byteVector(integers),
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

/// A byte vector appended after the owned routing envelope has been finished.
class DeferredFlatBufferVector {
  DeferredFlatBufferVector(this.tableOffset, this.slot, Uint8List bytes)
    : _bytes = bytes,
      _parts = null;
  DeferredFlatBufferVector.fragmented(
    this.tableOffset,
    this.slot,
    FlatBufferByteVectorParts parts,
  ) : _parts = parts,
      _bytes = null;
  final int tableOffset;
  final int slot;
  final Uint8List? _bytes;
  final FlatBufferByteVectorParts? _parts;
  int get length => _bytes?.length ?? _parts!.length;
  Iterable<Uint8List> get parts => _parts?.parts ?? [_bytes!];

  /// Explicit contiguous access coalesces a fragmented vector and observes it.
  Uint8List get bytes => _bytes ?? _parts!.toBytes();
}

/// Patch forward offsets into the envelope and retain the exact body views.
/// Only small vector headers and encoding prefixes are allocated here.
List<Uint8List> finishWampFlatBufferFragments(
  fb.Builder builder,
  int root,
  List<DeferredFlatBufferVector> vectors,
) {
  builder.finish(root);
  final control = builder.buffer;
  final data = ByteData.sublistView(control);
  final fragments = <Uint8List>[control];
  var length = control.length;
  const maximumBytes = 64 * 1024 * 1024;
  if (length > maximumBytes) {
    throw ArgumentError('FlatBuffers frame exceeds the byte limit');
  }
  for (final vector in vectors) {
    final table = control.length - vector.tableOffset;
    if (table < 0 || table > control.length - 4 || vector.slot < 0) {
      throw StateError('Invalid deferred FlatBuffers table');
    }
    final vtable = table - data.getInt32(table, Endian.little);
    if (vtable < 0 || vtable > control.length - 4) {
      throw StateError('Invalid deferred FlatBuffers vtable');
    }
    final slot = 4 + vector.slot * 2;
    final vtableLength = data.getUint16(vtable, Endian.little);
    if (slot + 2 > vtableLength || vtable + vtableLength > control.length) {
      throw StateError('Invalid deferred FlatBuffers slot');
    }
    final fieldOffset = data.getUint16(vtable + slot, Endian.little);
    final field = table + fieldOffset;
    if (fieldOffset == 0 || field > control.length - 4) {
      throw StateError('Absent deferred FlatBuffers field');
    }
    final padding = (12 - length % 8) % 8;
    final target = length + padding;
    final nextLength = target + 4 + vector.length;
    if (nextLength > maximumBytes) {
      throw ArgumentError('FlatBuffers frame exceeds the byte limit');
    }
    data.setUint32(field, target - field, Endian.little);
    final header = Uint8List(padding + 4);
    ByteData.sublistView(
      header,
    ).setUint32(padding, vector.length, Endian.little);
    fragments.add(header);
    fragments.addAll(vector.parts);
    length = nextLength;
  }
  return fragments;
}

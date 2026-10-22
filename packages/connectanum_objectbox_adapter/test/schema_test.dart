import 'dart:typed_data';

import 'package:connectanum_objectbox_adapter/connectanum_objectbox_adapter.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:objectbox/internal.dart';
import 'package:test/test.dart';

import 'support/model.dart';

void main() {
  final schema = ObjectBoxEntitySchema.fromModel(
    fixtureModel().model.entities.single,
  );
  int validate(Uint8List bytes) =>
      schema.validate(bytes, schemaFingerprint: schema.fingerprint);

  ObjectBoxEntitySchema changedModel(
    void Function(Map<String, dynamic>) change, {
    bool allowRelationIds = false,
  }) {
    final json = modelJson;
    final entity = (json['entities'] as List).single as Map<String, dynamic>;
    change(entity);
    if ((entity['relations'] as List).isNotEmpty) {
      json['lastRelationId'] = (entity['relations'] as List).last['id'];
    }
    return ObjectBoxEntitySchema.fromModel(
      ModelInfo.fromMap(json).entities.single,
      allowRelationIds: allowRelationIds,
    );
  }

  test(
    'unsupported types and relation policies fail before receiving bytes',
    () {
      for (final maximum in [15, 0x80000000]) {
        expect(
          () => ObjectBoxEntitySchema.fromModel(
            fixtureModel().model.entities.single,
            maximumBytes: maximum,
          ),
          throwsArgumentError,
        );
      }
      for (final type in [OBXPropertyType.Flex, 999]) {
        expect(
          () => changedModel((entity) {
            (entity['properties'] as List).first['type'] = type;
          }),
          throwsUnsupportedError,
        );
      }
      expect(
        () => changedModel((entity) {
          (entity['properties'] as List)[1]['type'] = OBXPropertyType.Int;
        }),
        throwsUnsupportedError,
      );
      void relation(Map<String, dynamic> entity) {
        final property = (entity['properties'] as List).first;
        property['type'] = OBXPropertyType.Relation;
        property['relationTarget'] = 'Other';
      }

      expect(() => changedModel(relation), throwsUnsupportedError);
      expect(changedModel(relation, allowRelationIds: true), isNotNull);
      expect(
        () => changedModel((entity) {
          entity['relations'] = [
            {'id': '1:12345', 'name': 'others', 'targetId': '2:90002'},
          ];
        }),
        throwsUnsupportedError,
      );
    },
  );

  test('boolean and wide vectors retain their FlatBuffers widths', () {
    for (final type in [
      OBXPropertyType.BoolVector,
      OBXPropertyType.LongVector,
      OBXPropertyType.DoubleVector,
    ]) {
      final selected = changedModel((entity) {
        final properties = entity['properties'] as List;
        properties.first['type'] = type;
        entity['properties'] = [properties[1], properties.first];
        entity['lastPropertyId'] = properties.first['id'];
      });
      final builder = fb.Builder();
      final vector = type == OBXPropertyType.BoolVector
          ? builder.writeListBool([false, true])
          : builder.writeListInt64([1, -1]);
      builder.startTable(3);
      builder.addInt64(0, 1);
      builder.addOffset(2, vector);
      builder.finish(builder.endTable());
      final bytes = Uint8List.fromList(builder.buffer);
      expect(
        selected.validate(bytes, schemaFingerprint: selected.fingerprint),
        1,
      );
      if (type == OBXPropertyType.BoolVector) {
        final field = fieldPosition(bytes, 2);
        final at =
            field + ByteData.sublistView(bytes).getUint32(field, Endian.little);
        bytes[at + 4] = 2;
        expect(
          () =>
              selected.validate(bytes, schemaFingerprint: selected.fingerprint),
          throwsFormatException,
        );
      }
    }
  });

  test(
    'property IDs, reordered declarations and sparse slots interoperate',
    () {
      for (final sample in [
        Sample(id: 1),
        Sample(id: 0, text: '', names: [], blob: [], scores: []),
      ]) {
        expect(validate(encodeSample(sample)), sample.id);
      }
      final model = fixtureModel().model.entities.single;
      model.properties.sort((a, b) => b.id.id.compareTo(a.id.id));
      expect(
        ObjectBoxEntitySchema.fromModel(model).fingerprint,
        schema.fingerprint,
      );
    },
  );

  test('wrong schema fingerprints fail before field interpretation', () {
    expect(
      () => schema.validate(
        encodeSample(Sample(id: 1)),
        schemaFingerprint: 'another-schema',
      ),
      throwsFormatException,
    );
  });

  test(
    'truncated roots and required payload ranges fail bounds validation',
    () {
      final bytes = encodeSample(Sample(id: 1));
      final data = ByteData.sublistView(bytes);
      final root = data.getUint32(0, Endian.little);
      for (final length in [0, 1, 3, 4, 15, root + 3]) {
        expect(
          () => validate(Uint8List.sublistView(bytes, 0, length)),
          throwsFormatException,
          reason: '$length',
        );
      }
      final bad = Uint8List.fromList(bytes);
      ByteData.sublistView(bad).setUint32(0, 0xffffffff, Endian.little);
      expect(() => validate(bad), throwsFormatException);
    },
  );

  test('unknown nonempty persisted slots are rejected', () {
    final bytes = encodeSample(Sample(id: 1));
    ByteData.sublistView(
      bytes,
    ).setUint16(vtablePosition(bytes) + 6, 8, Endian.little);
    expect(() => validate(bytes), throwsFormatException);
  });

  test('overlapping scalar fields cannot be changed by an ID rewrite', () {
    final bytes = encodeSample(Sample());
    final data = ByteData.sublistView(bytes);
    final vtable = vtablePosition(bytes);
    data.setUint16(
      vtable + 4 + 10 * 2,
      data.getUint16(vtable + 4, Endian.little),
      Endian.little,
    );
    expect(() => validate(bytes), throwsFormatException);
  });

  test('a string cannot alias mutable inline ID storage', () {
    final bytes = encodeSample(Sample());
    final data = ByteData.sublistView(bytes);
    final field = fieldPosition(bytes, 2);
    final id = fieldPosition(bytes, 0);
    data.setUint32(field, id > field ? id - field : 0, Endian.little);
    expect(() => validate(bytes), throwsFormatException);
  });

  test('invalid UTF-8 and missing terminators never enter native parsers', () {
    for (final terminator in [false, true]) {
      final bytes = encodeSample(Sample(id: 1, text: 'hello'));
      final data = ByteData.sublistView(bytes);
      final field = fieldPosition(bytes, 2);
      final string = field + data.getUint32(field, Endian.little);
      bytes[string + 4 + (terminator ? 5 : 0)] = terminator ? 1 : 0xc0;
      expect(() => validate(bytes), throwsFormatException);
    }
  });

  test('UTF-8 continuation, surrogate and range limits are validated', () {
    for (final sequence in <List<int>>[
      [0xc2],
      [0xc2, 0x7f],
      [0xe0, 0x80, 0x80],
      [0xed, 0xa0, 0x80],
      [0xe2, 0x82, 0x7f],
      [0xf0, 0x80, 0x80, 0x80],
      [0xf4, 0x90, 0x80, 0x80],
    ]) {
      final bytes = encodeSample(Sample(id: 1, text: 'x' * sequence.length));
      final field = fieldPosition(bytes, 2);
      final at =
          field + ByteData.sublistView(bytes).getUint32(field, Endian.little);
      bytes.setRange(at + 4, at + 4 + sequence.length, sequence);
      expect(() => validate(bytes), throwsFormatException, reason: '$sequence');
    }
  });

  test(
    'missing IDs, invalid booleans and overlapping headers are rejected',
    () {
      for (final change in <void Function(Uint8List)>[
        (bytes) => ByteData.sublistView(
          bytes,
        ).setUint16(vtablePosition(bytes) + 4, 0, Endian.little),
        (bytes) => bytes[fieldPosition(bytes, 9)] = 2,
        (bytes) {
          final data = ByteData.sublistView(bytes);
          final table = data.getUint32(0, Endian.little);
          final vtable = vtablePosition(bytes);
          data.setUint16(vtable, table - vtable + 4, Endian.little);
        },
        (bytes) {
          final data = ByteData.sublistView(bytes);
          final vtable = vtablePosition(bytes);
          data.setUint16(
            vtable + 4 + 9 * 2,
            data.getUint16(vtable + 2, Endian.little),
            Endian.little,
          );
        },
      ]) {
        final bytes = encodeSample(Sample(id: 1));
        change(bytes);
        expect(() => validate(bytes), throwsFormatException);
      }
    },
  );

  test('oversized vector counts fail without iterating or allocating', () {
    final bytes = encodeSample(Sample(id: 1));
    final data = ByteData.sublistView(bytes);
    final field = fieldPosition(bytes, 7);
    final vector = field + data.getUint32(field, Endian.little);
    data.setUint32(vector, 0xffffffff, Endian.little);
    expect(() => validate(bytes), throwsFormatException);
  });

  test('invalid ID sign, field alignment and table headers are rejected', () {
    final original = encodeSample(Sample(id: 1));
    for (final change in <void Function(Uint8List)>[
      (bytes) => ByteData.sublistView(
        bytes,
      ).setInt64(fieldPosition(bytes, 0), -1, Endian.little),
      (bytes) => ByteData.sublistView(
        bytes,
      ).setUint16(vtablePosition(bytes) + 4, 5, Endian.little),
      (bytes) => ByteData.sublistView(
        bytes,
      ).setUint16(vtablePosition(bytes), 3, Endian.little),
      (bytes) => ByteData.sublistView(
        bytes,
      ).setUint16(vtablePosition(bytes) + 2, 3, Endian.little),
    ]) {
      final bytes = Uint8List.fromList(original);
      change(bytes);
      expect(() => validate(bytes), throwsFormatException);
    }
  });
}

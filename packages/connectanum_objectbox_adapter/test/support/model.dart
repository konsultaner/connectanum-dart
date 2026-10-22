import 'dart:typed_data';

import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:objectbox/internal.dart';

int entityReads = 0;
int entityWrites = 0;

final class Sample {
  Sample({
    this.id = 0,
    this.text = 'München 🌍\u0000end',
    List<double>? scores,
    List<int>? blob,
    this.flag = true,
    this.counter = -42,
    this.names = const ['one', '東京', '🌍'],
    this.longs = const [1, -9223372036854775807, 9223372036854775807],
  }) : scores = Float32List.fromList(scores ?? [1.25, -2.5]),
       blob = Uint8List.fromList(blob ?? [0, 1, 128, 255]);
  int id;
  String text;
  Float32List scores;
  Uint8List blob;
  bool flag;
  int counter;
  List<String> names;
  List<int> longs;
}

Map<String, dynamic> get modelJson => {
  'entities': [
    {
      'id': '1:90001',
      'name': 'Sample',
      'lastPropertyId': '14:10014',
      'properties': [
        {
          'id': '3:10003',
          'name': 'text',
          'type': OBXPropertyType.String,
          'flags': 0,
        },
        {
          'id': '1:10001',
          'name': 'id',
          'type': OBXPropertyType.Long,
          'flags': OBXPropertyFlags.ID | OBXPropertyFlags.ID_SELF_ASSIGNABLE,
        },
        {
          'id': '5:10005',
          'name': 'scores',
          'type': OBXPropertyType.FloatVector,
          'flags': 0,
        },
        {
          'id': '8:10008',
          'name': 'blob',
          'type': OBXPropertyType.ByteVector,
          'flags': 0,
        },
        {
          'id': '10:10010',
          'name': 'flag',
          'type': OBXPropertyType.Bool,
          'flags': 0,
        },
        {
          'id': '11:10011',
          'name': 'counter',
          'type': OBXPropertyType.Long,
          'flags': 0,
        },
        {
          'id': '12:10012',
          'name': 'names',
          'type': OBXPropertyType.StringVector,
          'flags': 0,
        },
        {
          'id': '14:10014',
          'name': 'longs',
          'type': OBXPropertyType.LongVector,
          'flags': 0,
        },
      ],
      'relations': [],
      'backlinks': [],
    },
  ],
  'lastEntityId': '1:90001',
  'lastIndexId': '0:0',
  'lastRelationId': '0:0',
  'lastSequenceId': '0:0',
  'retiredEntityUids': [],
  'retiredIndexUids': [],
  'retiredPropertyUids': [],
  'retiredRelationUids': [],
  'modelVersion': 5,
  'modelVersionParserMinimum': 5,
  'version': 1,
};

ModelDefinition fixtureModel() {
  final model = ModelInfo.fromMap(modelJson);
  final definition = EntityDefinition<Sample>(
    model: model.entities.single,
    objectToFB: (sample, builder) {
      builder.finish(writeSample(sample, builder));
      return sample.id;
    },
    objectFromFB: (_, data) {
      entityReads++;
      final context = fb.BufferContext(data);
      final root = context.derefObject(0);
      return Sample(
        id: const fb.Int64Reader().vTableGet(context, root, 4, 0),
        text: const fb.StringReader().vTableGet(context, root, 8, ''),
        scores: const fb.ListReader<double>(
          fb.Float32Reader(),
        ).vTableGet(context, root, 12, const []),
        blob: const fb.ListReader<int>(
          fb.Uint8Reader(),
        ).vTableGet(context, root, 18, const []),
        flag: const fb.BoolReader().vTableGet(context, root, 22, false),
        counter: const fb.Int64Reader().vTableGet(context, root, 24, 0),
        names: const fb.ListReader<String>(
          fb.StringReader(),
        ).vTableGet(context, root, 26, const []),
        longs: const fb.ListReader<int>(
          fb.Int64Reader(),
        ).vTableGet(context, root, 30, const []),
      );
    },
    getId: (sample) => sample.id,
    setId: (sample, id) => sample.id = id,
    toOneRelations: (_) => [],
    toManyRelations: (_) => {},
  );
  return ModelDefinition(model, {Sample: definition});
}

int writeSample(Sample sample, fb.Builder builder) {
  entityWrites++;
  final text = builder.writeString(sample.text);
  final scores = builder.writeListFloat32(sample.scores);
  final blob = builder.writeListUint8(sample.blob);
  final names = builder.writeList([
    for (final name in sample.names) builder.writeString(name),
  ]);
  final longs = builder.writeListInt64(sample.longs);
  builder.startTable(14);
  builder.addInt64(0, sample.id);
  builder.addOffset(2, text);
  builder.addOffset(4, scores);
  builder.addOffset(7, blob);
  builder.addBool(9, sample.flag);
  builder.addInt64(10, sample.counter);
  builder.addOffset(11, names);
  builder.addOffset(13, longs);
  return builder.endTable();
}

Uint8List encodeSample(Sample sample) {
  final builder = fb.Builder();
  builder.finish(writeSample(sample, builder));
  return builder.buffer;
}

int fieldPosition(Uint8List bytes, int slot) {
  final data = ByteData.sublistView(bytes);
  final root = data.getUint32(0, Endian.little);
  final vtable = root - data.getInt32(root, Endian.little);
  return root + data.getUint16(vtable + 4 + slot * 2, Endian.little);
}

int vtablePosition(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final root = data.getUint32(0, Endian.little);
  return root - data.getInt32(root, Endian.little);
}

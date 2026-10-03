import 'package:connectanum_core/src/serializer/flatbuffers/wire_reader.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/generated/validation_schema.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';
import 'flatbuffers_fixture_data.dart';

import 'package:connectanum_core/src/serializer/flatbuffers/frame.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/message_writer.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/wire_writer.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/runtime.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;

Uint8List encoded(
  Map<String, Object?> body,
  Map<String, Object?>? dictionary, {
  String name = 'Call',
}) {
  final builder = WampFlatBufferBuilder();
  final tag = wire.AnyMessageTypeId.values
      .singleWhere((tag) => tag.name == name)
      .value;
  builder.finish(
    writeWampFlatBufferFields({
      'msg_type': tag,
      'msg': body,
      if (dictionary != null)
        'metadata': Uint8List.fromList(cbor.encode(CborValue(dictionary))),
    }, builder),
  );
  return builder.buffer;
}

void main() {
  test('aliased wire strings share one decoded allocation', () {
    final builder = WampFlatBufferBuilder();
    builder.finish(
      writeWampFlatBufferFields({
        'msg_type': 8,
        'msg': {
          'request': 1,
          'topic': 'com.topic',
          'exclude_authid': List.filled(256, 'x' * 2048),
        },
      }, builder),
    );
    final bytes = builder.buffer;
    final data = ByteData.sublistView(bytes);
    int field(int table, int slot) {
      final vtable = table - data.getInt32(table, Endian.little);
      return table + data.getUint16(vtable + 4 + slot * 2, Endian.little);
    }

    int target(int offset) => offset + data.getUint32(offset, Endian.little);
    final root = data.getUint32(0, Endian.little);
    final body = target(field(root, 1));
    final spec = wampValidationTables.singleWhere((t) => t.name == 'Publish');
    final slot = spec.fields.indexWhere((f) => f.name == 'exclude_authid');
    final vector = target(field(body, slot));
    final first = vector + 4;
    final stringTarget = target(first);
    for (var i = 1; i < 256; i++) {
      final entry = first + i * 4;
      data.setUint32(entry, stringTarget - entry, Endian.little);
    }
    final fields = readWampFlatBufferFields(bytes)['msg'] as Map;
    final strings = fields['exclude_authid'] as List;
    expect(strings.length, 256);
    expect(strings.first, 'x' * 2048);
    expect(strings.every((value) => identical(value, strings.first)), isTrue);
  });

  for (final fixture
      in (jsonDecode(flatBuffersFixtureJson) as List).cast<Map>()) {
    test('checked independent frame ${fixture['name']}', () {
      final bytes = base64Decode(fixture['base64'] as String);
      final frame = readWampFlatBufferFrame(bytes);
      expect(frame.name, (fixture['wire'] as Map)['msg_type']);
    });
  }
  test('model frame retains encoded byte vector as an original input view', () {
    final builder = WampFlatBufferBuilder();
    builder.finish(
      writeWampFlatBufferMessage(
        Call(42, 'com.proc', arguments: [1, 2]),
        builder,
      ),
    );
    final bytes = builder.buffer;
    final frame = readWampFlatBufferFrame(bytes);
    final args = frame.fields['args'] as Uint8List;
    expect(args, cbor.encode(CborValue([1, 2])));
    final offset = args.offsetInBytes - bytes.offsetInBytes;
    bytes[offset + 1] = 7;
    expect(args[1], 7);
  });
  for (final change in [
    {'timeout': 5},
    {'receive_progress': true},
    {'ppt_scheme': 4},
  ]) {
    test('metadata agreement rejects conflicting field $change', () {
      expect(
        () => readWampFlatBufferFrame(
          encoded({
            'request': 42,
            'procedure': 'com.proc',
            ...change,
          }, {}),
        ),
        throwsFormatException,
      );
    });
  }
  test('metadata agreement accepts large integer placeholder', () {
    final frame = readWampFlatBufferFrame(
      encoded(
        {
          'request': 42,
          'procedure': 'com.proc',
        },
        {'timeout': 9007199254740992},
      ),
    );
    expect(frame.dictionary!['timeout'], 9007199254740992);
  });
  test('metadata agreement accepts any representable dictionary entry', () {
    final frame = readWampFlatBufferFrame(
      encoded(
        {
          'method': 3,
          'extra': {'key': 'nonce', 'value': 'abc'},
        },
        {'salt': 'xyz', 'nonce': 'abc'},
        name: 'Challenge',
      ),
    );
    expect(frame.challengeMethod, 'wamp-scram');
  });
  test('unexpected root metadata on an acknowledgement is rejected', () {
    expect(
      () => readWampFlatBufferFrame(
        encoded(
          {
            'request': 42,
            'publication': 10,
          },
          {},
          name: 'Published',
        ),
      ),
      throwsFormatException,
    );
  });
  test('non-WELCOME session does not silently override session identity', () {
    expect(
      () => readWampFlatBufferFrame(
        encoded({
          'session': 123,
          'request': 42,
          'procedure': 'com.proc',
        }, {}),
      ),
      throwsFormatException,
    );
  });
  test('malformed application CBOR is rejected before returning a view', () {
    expect(
      () => readWampFlatBufferFrame(
        encoded({
          'request': 42,
          'procedure': 'com.proc',
          'args': [0x81],
        }, {}),
      ),
      throwsFormatException,
    );
  });
  test('conflicting transparent and regular payloads are rejected', () {
    expect(
      () => readWampFlatBufferFrame(
        encoded({
          'request': 42,
          'procedure': 'com.proc',
          'args': [0x80],
          'payload': [1],
        }, {}),
      ),
      throwsFormatException,
    );
  });
}

import 'package:connectanum_core/src/serializer/flatbuffers/validation_types.dart';
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
  _sparseTableChecks();
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
  test('opaque RESULT validates controls beyond its PPT headers', () {
    const principal = {'session': 9, 'authid': 'alice', 'authrole': 'member'};
    final body = <String, Object?>{
      'request': 42,
      'ppt_serializer': 6,
      'payload': Uint8List.fromList([0, 255]),
      'callee': 9,
      'callee_authrole': 'member',
      'forward_for': [principal],
    };
    final dictionary = <String, Object?>{
      'ppt_scheme': 'x_example',
      'ppt_serializer': 'flatbuffers',
      'callee': 9,
      'callee_authrole': 'member',
      'forward_for': [principal],
    };
    final frame = readWampFlatBufferFrame(
      encoded(body, dictionary, name: 'Result'),
    );
    expect(frame.fields['payload'], [0, 255]);
    expect(frame.dictionary, dictionary);
    for (final change in <Map<String, Object?>>[
      {'callee': 10},
      {'callee_authrole': 42},
      {
        'forward_for': [
          {...principal, 'session': 10},
        ],
      },
    ]) {
      expect(
        () => readWampFlatBufferFrame(
          encoded(body, {...dictionary, ...change}, name: 'Result'),
        ),
        throwsFormatException,
        reason: '$change',
      );
    }
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

void _sparseTableChecks() {
  for (final table in wampValidationTables) {
    final names = {for (final field in table.fields) field.name};
    if (!names.contains('args')) continue;
    final body = <String, Object?>{
      for (final field in table.fields)
        if (field.required && field.kind == FlatBufferFieldKind.string)
          field.name: 'com.example.value',
      if (names.contains('request')) 'request': 42,
      if (names.contains('request_type')) 'request_type': 48,
    };
    test(
      'optional payload omitted ${table.name} preserves defaults and args/kwargs views',
      () {
        final bytes = encoded(
          {
            ...body,
            'args': [0x80],
            'kwargs': [0xa0],
          },
          {},
          name: table.name,
        );
        final frame = readWampFlatBufferFrame(bytes);
        expect(frame.fields['payload'], isNull);
        expect(frame.fields['args'], isA<Uint8List>());
        expect(frame.fields['kwargs'], isA<Uint8List>());
        if (table.name == 'Call') {
          expect(frame.fields['request'], 42);
          expect(frame.fields['session'], 0);
          expect(frame.fields['timeout'], 0);
          expect(frame.fields['receive_progress'], isFalse);
        }
        final args = frame.fields['args'] as Uint8List;
        final position = args.offsetInBytes - bytes.offsetInBytes;
        expect(position, inInclusiveRange(0, bytes.length - args.length));
        bytes[position] = 0x81;
        expect(
          args.single,
          0x81,
          reason: 'the exact backing storage is retained',
        );
        for (final field in table.fields) {
          if (field.kind == FlatBufferFieldKind.scalar) {
            expect(frame.fields.containsKey(field.name), isTrue);
            expect(frame.fields[field.name], isNotNull);
          }
        }
      },
    );
    for (final item in <String, List<int>>{
      'args_empty': [],
      'args_truncated': [0x81],
      'args_root': [0xa0],
      'kwargs_empty': [],
      'kwargs_truncated': [0xa1],
      'kwargs_root': [0x80],
      'kwargs_key': [0xa1, 0x01, 0x01],
    }.entries) {
      test('optional payload omitted ${table.name} rejects ${item.key}', () {
        final key = item.key.startsWith('args_') ? 'args' : 'kwargs';
        final bytes = encoded({...body, key: item.value}, {}, name: table.name);
        expect(
          () => readWampFlatBufferFrame(bytes),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'CBOR validation',
              startsWith('Invalid FlatBuffers CBOR'),
            ),
          ),
        );
      });
    }
  }
  test('public metadata stays independently mutable with explicit nulls', () {
    final bytes = encoded(
      {'request': 42, 'procedure': 'com.example.echo'},
      {
        'user_null': null,
        'nested': {'value': null},
      },
    );
    final first = readWampFlatBufferFrame(bytes).dictionary!;
    final second = readWampFlatBufferFrame(bytes).dictionary!;
    expect(first.containsKey('user_null'), isTrue);
    expect(second.containsKey('user_null'), isTrue);
    first.remove('user_null');
    (first['nested'] as Map)['value'] = 42;
    expect(second.containsKey('user_null'), isTrue);
    expect((second['nested'] as Map).containsKey('value'), isTrue);
    expect((second['nested'] as Map)['value'], isNull);
  });
}

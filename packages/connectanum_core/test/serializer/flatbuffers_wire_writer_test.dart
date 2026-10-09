import 'dart:convert';
import 'dart:typed_data';
import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;
import 'package:connectanum_core/src/serializer/flatbuffers/runtime.dart'
    as runtime;
import 'package:connectanum_core/src/serializer/flatbuffers/validation.dart';
import 'package:test/test.dart';
import 'flatbuffers_fixture_data.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/wire_writer.dart';

void main() {
  final rows = (jsonDecode(flatBuffersFixtureJson) as List)
      .cast<Map<String, dynamic>>();
  for (final row in rows) {
    test('direct schema writer ${row['name']}', () {
      final builder = runtime.WampFlatBufferBuilder();
      builder.finish(
        writeWampFlatBufferFields(
          Map<String, Object?>.from(row['wire']),
          builder,
        ),
      );
      validateWampFlatBuffer(builder.buffer);
      final actual = wire.Message(builder.buffer);
      expect(actual.msgType!.value, row['union_tag']);
      final fields = _fields(actual.msg);
      for (final entry in (row['wire']['msg'] as Map).entries) {
        expect(fields[entry.key], entry.value, reason: '${entry.key}');
      }
      expect(actual.metadata, row['wire']['metadata']);
    });
  }
  test('reuses a previously written vector without rewriting it', () {
    final builder = runtime.WampFlatBufferBuilder(initialSize: 2048);
    final data = Uint8List.fromList(List.generate(1024, (i) => i % 256));
    final reference = FlatBufferByteVectorReference(
      builder,
      builder.writeListUint8(data),
    );
    builder.finish(
      writeWampFlatBufferFields({
        'msg_type': 'Call',
        'msg': {'request': 42, 'procedure': 'com.proc', 'args': reference},
      }, builder),
    );
    validateWampFlatBuffer(builder.buffer);
    final bytes = builder.buffer;
    final context = ByteData.sublistView(bytes);
    final root = context.getUint32(0, Endian.little);
    final rootVtable = root - context.getInt32(root, Endian.little);
    final bodyPointer = root + context.getUint16(rootVtable + 6, Endian.little);
    final body = bodyPointer + context.getUint32(bodyPointer, Endian.little);
    final bodyVtable = body - context.getInt32(body, Endian.little);
    final vectorPointer =
        body + context.getUint16(bodyVtable + 10, Endian.little);
    final vector =
        vectorPointer + context.getUint32(vectorPointer, Endian.little);
    expect(vector, bytes.length - reference.offset);
    expect((wire.Message(bytes).msg as wire.Call).args, data);
  });
  test('rejects references belonging to another builder before adoption', () {
    final source = runtime.WampFlatBufferBuilder();
    final reference = FlatBufferByteVectorReference(
      source,
      source.writeListUint8([1, 2, 3]),
    );
    final destination = runtime.WampFlatBufferBuilder();
    expect(
      () => writeWampFlatBufferFields({
        'msg_type': 'Call',
        'msg': {'request': 42, 'procedure': 'com.proc', 'args': reference},
      }, destination),
      throwsArgumentError,
    );
  });
  test('reused offsets survive growth and preserve uint64 controls', () {
    final builder = runtime.WampFlatBufferBuilder(initialSize: 16);
    final reference = FlatBufferByteVectorReference(
      builder,
      builder.writeListUint8([0, 255, 7]),
    );
    builder.finish(
      writeWampFlatBufferFields({
        'msg_type': 'Publish',
        'metadata': Uint8List(8192),
        'msg': {
          'request': 9007199254740992,
          'topic': 'com.proc',
          'args': reference,
          'exclude': [0, 9007199254740992],
          'acknowledge': false,
        },
      }, builder),
    );
    validateWampFlatBuffer(builder.buffer);
    final actual = wire.Message(builder.buffer).msg as wire.Publish;
    expect(actual.args, [0, 255, 7]);
    expect(actual.request, 9007199254740992);
    expect(actual.exclude, [0, 9007199254740992]);
    expect(actual.acknowledge, false);
  });
  test(
    'rejects missing required fields, enums, negative and oversized values',
    () {
      for (final fields in <Map<String, Object?>>[
        {'msg_type': 0, 'msg': {}},
        {
          'msg_type': 'Call',
          'msg': {'request': 42},
        },
        {
          'msg_type': 'Call',
          'msg': {'request': -1, 'procedure': 'com.proc'},
        },
        {
          'msg_type': 'Call',
          // The next representable JavaScript integer above the WAMP bound.
          'msg': {'request': 9007199254740994, 'procedure': 'com.proc'},
        },
        {
          'msg_type': 'Call',
          'msg': {
            'request': 42,
            'procedure': 'com.proc',
            'args': [256],
          },
        },
        {
          'msg_type': 'Cancel',
          'msg': {'request': 42, 'mode': 'unknown'},
        },
        {
          'msg_type': 'Cancel',
          'msg': {'request': 42, 'mode': true},
        },
        {
          'msg_type': 'Call',
          'msg': {
            'request': 42,
            'procedure': 'com.proc',
            'timeout': 4294967296,
          },
        },
        {
          'msg_type': 'Call',
          'msg': {'request': 42, 'procedure': 'com.proc', 'unknown': true},
        },
      ]) {
        expect(
          () => writeWampFlatBufferFields(
            fields,
            runtime.WampFlatBufferBuilder(),
          ),
          throwsArgumentError,
        );
      }
    },
  );
}

Map<String, dynamic> _fields(dynamic value) => switch (value) {
  wire.Hello m => {
    'realm': m.realm,
    'roles': {'caller': m.roles?.caller == null ? null : {}},
  },
  wire.Welcome m => {
    'session': m.session,
    'realm': m.realm,
    'roles': {'dealer': m.roles?.dealer == null ? null : {}},
    'authid': m.authid,
    'authrole': m.authrole,
  },
  wire.Abort m => {'reason': m.reason, 'message': m.message},
  wire.Challenge m => {
    'method': m.method.name,
    'method_name': m.methodName,
    'extra': {'key': m.extra?.key, 'value': m.extra?.value},
  },
  wire.Authenticate m => {
    'signature': m.signature,
    'extra': {'key': m.extra?.key, 'value': m.extra?.value},
  },
  wire.Goodbye m => {'reason': m.reason, 'message': m.message},
  wire.Error m => {
    'request_type': m.requestType.name,
    'request': m.request,
    'error': m.error,
    'args': m.args,
    'kwargs': m.kwargs,
  },
  wire.Publish m => {
    'request': m.request,
    'topic': m.topic,
    'args': m.args,
    'kwargs': m.kwargs,
    'acknowledge': m.acknowledge,
    'exclude_me': m.excludeMe,
  },
  wire.Published m => {'request': m.request, 'publication': m.publication},
  wire.Subscribe m => {
    'request': m.request,
    'topic': m.topic,
    'match': m.match.name,
    'get_retained': m.getRetained,
  },
  wire.Subscribed m => {'request': m.request, 'subscription': m.subscription},
  wire.Unsubscribe m => {'request': m.request, 'subscription': m.subscription},
  wire.Unsubscribed m => {'request': m.request},
  wire.Event m => {
    'subscription': m.subscription,
    'publication': m.publication,
    'args': m.args,
    'kwargs': m.kwargs,
    'publisher': m.publisher,
    'topic': m.topic,
  },
  wire.EventReceived m => {'publication': m.publication},
  wire.Call m => {
    'request': m.request,
    'procedure': m.procedure,
    'args': m.args,
    'kwargs': m.kwargs,
    'timeout': m.timeout,
    'receive_progress': m.receiveProgress,
    'payload': m.payload,
    'ppt_scheme': m.pptScheme.name,
    'ppt_serializer': m.pptSerializer.name,
  },
  wire.Cancel m => {'request': m.request, 'mode': m.mode.name},
  wire.Result m => {
    'request': m.request,
    'args': m.args,
    'kwargs': m.kwargs,
    'progress': m.progress,
  },
  wire.Register m => {
    'request': m.request,
    'procedure': m.procedure,
    'match': m.match.name,
    'invoke': m.invoke.name,
  },
  wire.Registered m => {'request': m.request, 'registration': m.registration},
  wire.Unregister m => {'request': m.request, 'registration': m.registration},
  wire.Unregistered m => {'request': m.request},
  wire.Invocation m => {
    'request': m.request,
    'registration': m.registration,
    'args': m.args,
    'kwargs': m.kwargs,
    'caller': m.caller,
    'receive_progress': m.receiveProgress,
  },
  wire.Interrupt m => {
    'request': m.request,
    'mode': m.mode.name,
    'reason': m.reason,
  },
  wire.Yield m => {
    'request': m.request,
    'args': m.args,
    'kwargs': m.kwargs,
    'progress': m.progress,
  },
  wire.Heartbeat m => {
    'ping': m.ping,
    'incoming': m.incoming,
    'outgoing': m.outgoing,
    'presence': m.presence,
  },
  _ => throw StateError('Unexpected fixture type ${value.runtimeType}'),
};

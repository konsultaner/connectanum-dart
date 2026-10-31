import 'dart:convert';
import 'dart:typed_data';

import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;
import 'package:connectanum_core/src/serializer/flatbuffers/runtime.dart'
    as runtime;
import 'package:connectanum_core/src/serializer/flatbuffers/validation.dart';
import 'package:test/test.dart';
import 'flatbuffers_fixture_data.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/wire_writer.dart';

class _Utf8OnlyBuilder extends fb.Builder {
  @override
  int writeString(String value, {bool asciiOptimization = false}) =>
      super.writeString(value);
}

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
  test('ASCII-optimized routing strings preserve UTF-8 wire bytes', () {
    for (final realm in [
      '',
      'com.example.proc',
      'a' * 24,
      'com.\u0000\u007f',
      'com.λ🧪',
      'com.\uD800',
      'com.\uDC00',
    ]) {
      final optimized = runtime.WampFlatBufferBuilder();
      optimized.finish(
        writeWampFlatBufferFields({
          'msg_type': 'Hello',
          'msg': {
            'realm': realm,
            'roles': {'caller': {}},
          },
        }, optimized),
      );

      // Keep the reference string writer on its normal UTF-8 path. This fixture
      // needs no uint64 writes, unsupported by the SDK builder under dart2js.
      final standard = _Utf8OnlyBuilder();
      standard.finish(
        writeWampFlatBufferFields({
          'msg_type': 'Hello',
          'msg': {
            'realm': realm,
            'roles': {'caller': {}},
          },
        }, standard),
      );

      expect(optimized.buffer, standard.buffer);
      expect(
        (wire.Message(optimized.buffer).msg as wire.Hello).realm,
        utf8.decode(utf8.encode(realm)),
      );
    }
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
  test('opaque CALL matches generic bytes for all payload storage forms', () {
    for (final storage in ['inline', 'reference', 'deferred']) {
      for (final request in [0, 1, 9007199254740992]) {
        for (final scheme in [null, 0, 1, 2, 3, 4]) {
          for (final procedure in ['', 'com.proc', 'com.λ🧪', 'com.\uD800']) {
            for (final length in [0, 7, 65536]) {
              final payload = Uint8List.fromList(
                List.generate(length, (index) => index % 251),
              );
              Uint8List encode(bool generic) {
                final builder = runtime.WampFlatBufferBuilder(initialSize: 16);
                final vectors = <DeferredFlatBufferVector>[];
                final fields = <String, Object?>{
                  'msg_type': wire.AnyMessageTypeId.Call.value,
                  'metadata': Uint8List.fromList([0xa1, 0x61, 0x78, 0x01]),
                  'msg': <String, Object?>{
                    'request': request,
                    'procedure': procedure,
                    'payload': storage == 'reference'
                        ? FlatBufferByteVectorReference(
                            builder,
                            builder.writeListUint8(payload),
                          )
                        : payload,
                    'ppt_scheme': ?scheme,
                    'ppt_serializer': wire.Pptserializer.FLATBUFFERS.value,
                    // An absent optional field has the same wire representation,
                    // while selecting the complete generic schema walk.
                    if (generic) 'timeout': null,
                  },
                };
                final root = writeWampFlatBufferFields(
                  fields,
                  builder,
                  deferredVectors: storage == 'deferred' ? vectors : null,
                );
                if (storage == 'deferred') {
                  final fragments = finishWampFlatBufferFragments(
                    builder,
                    root,
                    vectors,
                  );
                  expect(vectors, hasLength(1));
                  expect(identical(fragments.last, payload), isTrue);
                  final combined = BytesBuilder(copy: false);
                  for (final fragment in fragments) {
                    combined.add(fragment);
                  }
                  return combined.takeBytes();
                }
                builder.finish(root);
                return builder.buffer;
              }

              final actual = encode(false);
              expect(actual, encode(true), reason: '$storage/$request/$scheme');
              validateWampFlatBuffer(actual);
              final call = wire.Message(actual).msg as wire.Call;
              expect(call.request, request);
              expect(call.payload, payload);
              expect(call.pptScheme.value, scheme ?? 0);
            }
          }
        }
      }
    }
  });
  test(
    'opaque CALL guards preserve invalid-field and foreign-owner rejection',
    () {
      final foreign = runtime.WampFlatBufferBuilder();
      final foreignVector = FlatBufferByteVectorReference(
        foreign,
        foreign.writeListUint8([1, 2, 3]),
      );
      for (final override in <Map<String, Object?>>[
        {'request': -1},
        {'request': 9007199254740994},
        {'request': 1.5},
        {'procedure': null},
        {'ppt_scheme': 5},
        {'ppt_scheme': 3.5},
        {'ppt_serializer': 6.5},
        // Dart's JavaScript backend represents integral doubles as ints too.
        // Only runtimes that distinguish them can reject their numeric type.
        if (!identical(0, 0.0)) ...[
          {'request': 1.0},
          {'ppt_scheme': 4.0},
          {'ppt_serializer': 6.0},
        ],
        {'unknown': null},
        {'payload': foreignVector},
      ]) {
        expect(
          () => writeWampFlatBufferFields({
            'msg_type': wire.AnyMessageTypeId.Call.value,
            'metadata': Uint8List.fromList([0xa0]),
            'msg': <String, Object?>{
              'request': 1,
              'procedure': 'com.proc',
              'payload': Uint8List(0),
              'ppt_scheme': 4,
              'ppt_serializer': 6,
              ...override,
            },
          }, runtime.WampFlatBufferBuilder()),
          throwsArgumentError,
          reason: override.toString(),
        );
      }
      for (final tag in [
        wire.AnyMessageTypeId.Call.value + 0.5,
        if (!identical(0, 0.0)) wire.AnyMessageTypeId.Call.value.toDouble(),
      ]) {
        expect(
          () => writeWampFlatBufferFields({
            'msg_type': tag,
            'metadata': Uint8List.fromList([0xa0]),
            'msg': <String, Object?>{
              'request': 1,
              'procedure': 'com.proc',
              'payload': Uint8List(0),
              'ppt_scheme': 4,
              'ppt_serializer': 6,
            },
          }, runtime.WampFlatBufferBuilder()),
          throwsArgumentError,
        );
      }
    },
  );
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

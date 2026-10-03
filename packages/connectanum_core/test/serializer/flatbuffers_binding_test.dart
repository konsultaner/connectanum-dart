import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;
import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:connectanum_core/src/serializer/flatbuffers/runtime.dart'
    as runtime;
import 'package:test/test.dart';

import 'flatbuffers_fixture_data.dart';

void main() {
  final cases = (jsonDecode(flatBuffersFixtureJson) as List)
      .cast<Map<String, dynamic>>();
  for (final fixture in cases) {
    test('pinned compiler binding: ${fixture['name']}', () {
      final bytes = base64Decode(fixture['base64'] as String);
      final message = wire.Message(bytes);
      expect(message.msgType!.value, fixture['union_tag']);
      expect(_wampId(message.msg), fixture['wamp_id']);
      final expected = Map<String, dynamic>.from(fixture['wire']['msg']);
      final actual = _fields(message.msg);
      for (final entry in expected.entries) {
        expect(actual[entry.key], entry.value, reason: entry.key);
      }
      expect(message.metadata, fixture['wire']['metadata']);
      if (actual['args'] != null) {
        expect(cbor.decode(actual['args'] as List<int>).toObject(), [
          1,
          'hello',
        ]);
      }
      if (actual['kwargs'] != null) {
        expect(
          cbor.decode(actual['kwargs'] as List<int>).toObject(),
          {
            'key': Uint8List.fromList([0, 255]),
          },
        );
      }
      if (fixture['name'] == 'call_typed_payload') {
        final inner =
            wire.Message(actual['payload'] as List<int>).msg as wire.Call;
        expect(inner.request, 77);
        expect(inner.procedure, 'com.example.proc');
        expect(cbor.decode(message.metadata!).toObject(), {
          'ppt_scheme': 'opaque',
          'ppt_serializer': 'flatbuffers',
          '_schema': 'wamp.proto.Message',
        });
      }
    });
  }

  test('union tags are distinct from WAMP message IDs', () {
    expect(wire.AnyMessageTypeId.Call.value, 16);
    expect(wire.MessageType.CALL.value, 48);
    expect(wire.AnyMessageTypeId.Error.value, 7);
    expect(wire.MessageType.ERROR.value, 8);
    expect(wire.AnyMessageTypeId.Heartbeat.value, 26);
  });

  test('Dart builder emits a standard Call plus optional metadata', () {
    final call = wire.CallObjectBuilder(
      request: 77,
      procedure: 'com.example.proc',
      args: [0x82, 1, 0x65, ...utf8.encode('hello')],
    );
    final root = wire.MessageObjectBuilder(
      msgType: wire.AnyMessageTypeId.Call,
      msg: call,
      metadata: [0xa1, 0x61, 0x78, 0x18, 0x2a],
    );
    final fb.Builder builder = runtime.WampFlatBufferBuilder();
    builder.finish(root.finish(builder));
    final read = wire.Message(builder.buffer);
    final payload = read.msg as wire.Call;
    expect(payload.request, 77);
    expect(payload.procedure, 'com.example.proc');
    expect(cbor.decode(payload.args!).toObject(), [1, 'hello']);
    expect(cbor.decode(read.metadata!).toObject(), {'x': 42});
  });

  test(
    'portable uint64 scalar and vector writes include the WAMP upper ID',
    () {
      const ids = [
        0,
        4294967295,
        4294967296,
        9007199254740991,
        9007199254740992,
      ];
      for (final id in ids) {
        final bytes = wire.PublishObjectBuilder(
          request: id,
          topic: 'com.example.topic',
          exclude: ids,
        ).toBytes();
        final publish = wire.MessageObjectBuilder(
          msgType: wire.AnyMessageTypeId.Publish,
          msg: wire.PublishObjectBuilder(
            request: id,
            topic: 'com.example.topic',
            exclude: ids,
          ),
        ).toBytes();
        expect(wire.Publish(bytes).request, id);
        expect((wire.Message(publish).msg as wire.Publish).exclude, ids);
      }
    },
  );

  test(
    'unsafe uint64 values are rejected without changing wire representation',
    () {
      for (final value in [-1, 9007199254740994]) {
        expect(
          () => wire.CallObjectBuilder(
            request: value,
            procedure: 'com.example.proc',
          ).toBytes(),
          throwsArgumentError,
        );
      }
      // 2^53 + 1 cannot be represented exactly as a dart2js integer literal.
      final data = ByteData(8)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(4, 0x200000, Endian.little);
      expect(
        () => const runtime.WampUint64Reader().read(fb.BufferContext(data), 0),
        throwsFormatException,
      );
    },
  );

  test('empty uint64 vectors remain present after a byte-sized value', () {
    final builder = runtime.WampFlatBufferBuilder(initialSize: 8);
    builder.putUint8(1);
    final root = wire.MessageObjectBuilder(
      msgType: wire.AnyMessageTypeId.Publish,
      msg: wire.PublishObjectBuilder(
        request: 42,
        topic: 'com.example.topic',
        exclude: [],
      ),
    );
    builder.finish(root.finish(builder));
    expect((wire.Message(builder.buffer).msg as wire.Publish).exclude, isEmpty);
  });

  test(
    'a Uint8List frame view cannot read outside its declared byte range',
    () {
      final allocation = Uint8List(16);
      final view = Uint8List.sublistView(allocation, 4, 12);
      final context = runtime.bufferContext(view);
      expect(context.buffer.lengthInBytes, 8);
      expect(
        () => context.buffer.getUint32(8, Endian.little),
        throwsArgumentError,
      );
    },
  );
}

int _wampId(dynamic message) => switch (message) {
  wire.Hello() => 1,
  wire.Welcome() => 2,
  wire.Abort() => 3,
  wire.Challenge() => 4,
  wire.Authenticate() => 5,
  wire.Goodbye() => 6,
  wire.Error() => 8,
  wire.Publish() => 16,
  wire.Published() => 17,
  wire.Subscribe() => 32,
  wire.Subscribed() => 33,
  wire.Unsubscribe() => 34,
  wire.Unsubscribed() => 35,
  wire.Event() => 36,
  wire.EventReceived() => 37,
  wire.Call() => 48,
  wire.Cancel() => 49,
  wire.Result() => 50,
  wire.Register() => 64,
  wire.Registered() => 65,
  wire.Unregister() => 66,
  wire.Unregistered() => 67,
  wire.Invocation() => 68,
  wire.Interrupt() => 69,
  wire.Yield() => 70,
  wire.Heartbeat() => 7,
  _ => throw StateError('Unknown message table'),
};

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
  },
  _ => throw StateError('Unexpected fixture type ${value.runtimeType}'),
};

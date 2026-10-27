import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;
import 'package:connectanum_core/src/serializer/flatbuffers/cbor_encoding.dart'
    show tryEncodeWampFlatBufferScalarKeywordMap;
import 'package:connectanum_core/src/serializer/flatbuffers/message_writer.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/runtime.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/validation.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/wire_writer.dart';
import 'package:test/test.dart';

Uint8List encode(AbstractMessage message) {
  final builder = WampFlatBufferBuilder(initialSize: 64);
  builder.finish(writeWampFlatBufferMessage(message, builder));
  validateWampFlatBuffer(builder.buffer);
  return builder.buffer;
}

Map<Object?, Object?> metadata(wire.Message message) =>
    cbor.decode(message.metadata!).toObject() as Map<Object?, Object?>;

void main() {
  final messages = <String, AbstractMessage>{
    'Hello': Hello('realm', Details()),
    'Welcome': Welcome(123, Details()),
    'Abort': Abort('wamp.error.not_authorized'),
    'Challenge': Challenge('ticket', Extra()),
    'Authenticate': Authenticate(signature: 'secret'),
    'Goodbye': Goodbye(GoodbyeMessage('bye'), 'wamp.close.normal'),
    'Error': Error(48, 10, {}, 'wamp.error.runtime_error'),
    'Publish': Publish(11, 'com.topic'),
    'Published': Published(11, 123),
    'Subscribe': Subscribe(12, 'com.topic'),
    'Subscribed': Subscribed(12, 124),
    'Unsubscribe': Unsubscribe(13, 124),
    'Unsubscribed': Unsubscribed(13, null),
    'Event': Event(124, 123, EventDetails()),
    'Call': Call(14, 'com.proc'),
    'Cancel': Cancel(14),
    'Result': Result(14, ResultDetails()),
    'Register': Register(15, 'com.proc'),
    'Registered': Registered(15, 125),
    'Unregister': Unregister(16, 125),
    'Unregistered': Unregistered(16),
    'Invocation': Invocation(17, 125, InvocationDetails(null, null, null)),
    'Interrupt': Interrupt(17),
    'Yield': Yield(17),
    'Heartbeat': Heartbeat(ping: 0),
  };
  const requests = {
    'Error': 10,
    'Publish': 11,
    'Published': 11,
    'Subscribe': 12,
    'Subscribed': 12,
    'Unsubscribe': 13,
    'Unsubscribed': 13,
    'Call': 14,
    'Cancel': 14,
    'Result': 14,
    'Register': 15,
    'Registered': 15,
    'Unregister': 16,
    'Unregistered': 16,
    'Invocation': 17,
    'Interrupt': 17,
    'Yield': 17,
  };
  for (final entry in messages.entries) {
    test('direct model writer: ${entry.key}', () {
      final result = wire.Message(encode(entry.value));
      expect(result.msgType!.name, entry.key);
      final body = result.msg as dynamic;
      if (requests.containsKey(entry.key)) {
        expect(body.request, requests[entry.key]);
      }
      if (entry.key != 'Heartbeat') {
        expect(body.session, entry.key == 'Welcome' ? 123 : 0);
      }
      if (entry.key == 'Published' || entry.key == 'Event') {
        expect(body.publication, 123);
      }
      if (entry.key == 'Subscribed' ||
          entry.key == 'Unsubscribe' ||
          entry.key == 'Event') {
        expect(body.subscription, 124);
      }
      if (entry.key == 'Registered' ||
          entry.key == 'Unregister' ||
          entry.key == 'Invocation') {
        expect(body.registration, 125);
      }
      final hasDictionary = !{
        'Published',
        'Subscribed',
        'Unsubscribe',
        'Registered',
        'Unregister',
      }.contains(entry.key);
      expect(result.metadata != null, hasDictionary);
      if (hasDictionary) expect(metadata(result), isA<Map>());
    });
  }

  test('routing IDs and procedure are not overwritten by option keys', () {
    final result = wire.Message(
      encode(
        Call(
          14,
          'com.proc',
          options: CallOptions(
            custom: {'request': 99, 'session': 99, 'procedure': 'com.other'},
          ),
        ),
      ),
    );
    final call = result.msg as wire.Call;
    expect(call.request, 14);
    expect(call.session, 0);
    expect(call.procedure, 'com.proc');
    expect(metadata(result)['request'], 99);
  });

  test(
    'HELLO metadata survives without typed roles and with empty authmethods',
    () {
      final details = Details()
        ..agent = 'client'
        ..authid = 'alice'
        ..authmethods = [];
      details.custom['_custom'] = null;
      final result = wire.Message(encode(Hello('realm', details)));
      expect(metadata(result), {
        'agent': 'client',
        'authid': 'alice',
        'authmethods': [],
        '_custom': null,
      });
      final hello = result.msg as wire.Hello;
      expect(hello.roles, isNotNull);
      expect(hello.authid, 'alice');
      expect(hello.authmethods, isEmpty);
    },
  );

  test('role features and payload transparency alias use upstream fields', () {
    final features = CallerFeatures()
      ..callCanceling = true
      ..payloadPassThruMode = true;
    final details = Details()
      ..roles = (Roles()..caller = (Caller()..features = features));
    final result = wire.Message(encode(Hello('realm', details)));
    final hello = result.msg as wire.Hello;
    expect(hello.roles!.caller!.callCanceling, true);
    expect(hello.roles!.caller!.payloadTransparency, true);
    expect((metadata(result)['roles'] as Map)['caller'], isA<Map>());
  });

  test('custom authentication methods retain their actual names', () {
    final challenge = wire.Message(encode(Challenge('custom-auth', Extra())));
    final body = challenge.msg as wire.Challenge;
    expect(body.method.value, 0);
    expect(body.methodName, 'custom-auth');
    final details = Details()
      ..authmethods = ['custom-auth', 'ticket', 'wamp-scram'];
    final hello = wire.Message(encode(Hello('realm', details)));
    expect((hello.msg as wire.Hello).authmethods!.map((item) => item.value), [
      1,
      3,
    ]);
    expect(metadata(hello)['authmethods'], [
      'custom-auth',
      'ticket',
      'wamp-scram',
    ]);
  });

  test('metadata does not replace HELLO realm or authentication signature', () {
    final details = Details()..realm = 'metadata-realm';
    final hello = wire.Message(encode(Hello('routed-realm', details)));
    expect((hello.msg as wire.Hello).realm, 'routed-realm');
    expect(metadata(hello)['realm'], 'metadata-realm');
    final authenticate = Authenticate(signature: 'proof');
    authenticate.extra = {'signature': 'extra-value', 'nonce': 'n'};
    final result = wire.Message(encode(authenticate));
    expect((result.msg as wire.Authenticate).signature, 'proof');
    expect(metadata(result)['signature'], 'extra-value');
  });

  test(
    'CHALLENGE extra projects a representable entry from the complete dictionary',
    () {
      final result = wire.Message(
        encode(Challenge('wamp-scram', Extra(nonce: 'nonce'))),
      );
      final body = result.msg as wire.Challenge;
      expect(body.extra!.key, 'nonce');
      expect(body.extra!.value, 'nonce');
      expect(metadata(result)['nonce'], 'nonce');
    },
  );

  test('large timeout remains in metadata rather than truncating', () {
    final result = wire.Message(
      encode(
        Call(14, 'com.proc', options: CallOptions(timeout: 9007199254740992)),
      ),
    );
    expect((result.msg as wire.Call).timeout, 0);
    final timeout = switch (metadata(result)['timeout']) {
      int value => BigInt.from(value),
      BigInt value => value,
      _ => throw StateError('Expected an integer timeout'),
    };
    expect(timeout, BigInt.from(9007199254740992));
  });

  test('WELCOME placeholders do not manufacture auth identity in metadata', () {
    final result = wire.Message(encode(Welcome(9007199254740992, Details())));
    final welcome = result.msg as wire.Welcome;
    expect(welcome.session, 9007199254740992);
    expect(welcome.authid, '');
    expect(welcome.authrole, '');
    expect(welcome.realm, '');
    expect(metadata(result), isEmpty);
  });

  test(
    'ordinary args/kwargs are encoded independently of envelope metadata',
    () {
      final result = wire.Message(
        encode(
          Call(
            14,
            'com.proc',
            arguments: [1, null],
            argumentsKeywords: {
              'bytes': Uint8List.fromList([0, 255]),
            },
          ),
        ),
      );
      final call = result.msg as wire.Call;
      expect(cbor.decode(call.args!).toObject(), [1, null]);
      expect(cbor.decode(call.kwargs!).toObject(), {
        'bytes': [0, 255],
      });
      expect(metadata(result), isEmpty);
    },
  );

  test('small scalar keyword maps use the compact CBOR wire form', () {
    final result = wire.Message(
      encode(Call(14, 'com.proc', argumentsKeywords: {'a': 1})),
    );
    final kwargs = (result.msg as wire.Call).kwargs!;
    expect(kwargs, [0xa1, 0x61, 0x61, 0x01]);
    expect(cbor.decode(kwargs).toObject(), {'a': 1});
  });

  test('small scalar argument arrays use the compact CBOR wire form', () {
    final result = wire.Message(
      encode(Call(14, 'com.proc', arguments: [1, 'a', null, true])),
    );
    final args = (result.msg as wire.Call).args!;
    expect(args, [0x84, 0x01, 0x61, 0x61, 0xf6, 0xf5]);
    expect(cbor.decode(args).toObject(), [1, 'a', null, true]);
  });

  test('complex argument arrays preserve nested maps and binary values', () {
    final bytes = Uint8List.fromList([1, 2]);
    final result = wire.Message(
      encode(
        Call(
          14,
          'com.proc',
          arguments: [
            {
              'nested': {1: 'value'},
            },
            bytes,
          ],
        ),
      ),
    );
    final args = (result.msg as wire.Call).args!;
    expect(args, [
      0x82, // Two WAMP positional arguments.
      0xa1, 0x66, 0x6e, 0x65, 0x73, 0x74, 0x65, 0x64,
      0xa1, 0x01, 0x65, 0x76, 0x61, 0x6c, 0x75, 0x65,
      0x42, 0x01, 0x02, // Uint8List remains a CBOR byte string.
    ]);
    expect(cbor.decode(args).toObject(), [
      {
        'nested': {1: 'value'},
      },
      [1, 2],
    ]);
  });

  test('scalar argument arrays fall back when an item is a byte vector', () {
    final result = wire.Message(
      encode(
        Call(
          14,
          'com.proc',
          arguments: [
            1,
            Uint8List.fromList([2]),
          ],
        ),
      ),
    );
    final args = (result.msg as wire.Call).args!;
    expect(args, [0x82, 0x01, 0x41, 0x02]);
    expect(cbor.decode(args).toObject(), [
      1,
      [2],
    ]);
  });

  test('keyword scalar fast path falls back outside its validated subset', () {
    expect(
      tryEncodeWampFlatBufferScalarKeywordMap({
        'nested': [1],
      }),
      isNull,
    );
    expect(tryEncodeWampFlatBufferScalarKeywordMap({'wide': 1 << 40}), isNull);
    expect(tryEncodeWampFlatBufferScalarKeywordMap({'unicode': 'λ'}), isNull);
  });

  test(
    'keyword scalar fast path encodes integer header boundaries exactly',
    () {
      for (final entry in <String, int>{
        'small': 65535,
        'unsigned': 4294967295,
        'negative': -65536,
        'signed': -4294967296,
      }.entries) {
        final encoded = tryEncodeWampFlatBufferScalarKeywordMap({
          entry.key: entry.value,
        })!;
        final key = entry.key.codeUnits;
        final major = entry.value < 0 ? 0x20 : 0;
        final magnitude = entry.value < 0 ? -1 - entry.value : entry.value;
        final header = magnitude <= 65535
            ? <int>[major | 25, magnitude >> 8, magnitude & 0xff]
            : <int>[
                major | 26,
                (magnitude >> 24) & 0xff,
                (magnitude >> 16) & 0xff,
                (magnitude >> 8) & 0xff,
                magnitude & 0xff,
              ];
        expect(encoded, [0xa1, 0x60 | key.length, ...key, ...header]);
        expect(cbor.decode(encoded).toObject(), {entry.key: entry.value});
      }
    },
  );

  test('complex keyword maps preserve numeric keys in nested maps', () {
    final result = wire.Message(
      encode(
        Call(
          14,
          'com.proc',
          argumentsKeywords: {
            'nested': {1: 'value'},
          },
        ),
      ),
    );
    final kwargs = (result.msg as wire.Call).kwargs!;
    expect(cbor.decode(kwargs).toObject(), {
      'nested': {1: 'value'},
    });
  });

  test('absent and empty argument vectors remain distinct', () {
    final absent = wire.Message(encode(Call(1, 'com.proc'))).msg as wire.Call;
    final empty =
        wire.Message(
              encode(Call(1, 'com.proc', arguments: [], argumentsKeywords: {})),
            ).msg
            as wire.Call;
    expect(absent.args, isNull);
    expect(absent.kwargs, isNull);
    expect(cbor.decode(empty.args!).toObject(), isEmpty);
    expect(cbor.decode(empty.kwargs!).toObject(), isEmpty);
  });

  test('encoded CBOR arguments do not invoke the model decoder', () {
    final input = Uint8List.fromList(cbor.encode(CborValue([1, 'payload'])));
    final call = Call(1, 'com.proc')
      ..setLazyPayload(
        argumentsBytes: input,
        argumentsDecoder: (_) => throw StateError('Unexpected materialization'),
        encoding: LazyPayloadEncoding.cbor,
      );
    final result = wire.Message(encode(call)).msg as wire.Call;
    expect(result.args, input);
    expect(call.hasLazyArguments, true);
  });

  test('raw lazy CBOR arguments are validated before writing', () {
    for (final bytes in [
      <int>[0xa0], // A valid map is the wrong root type for args.
      <int>[0x80, 0xff], // A valid array followed by a trailing break.
    ]) {
      final call = Call(1, 'com.proc')
        ..setLazyPayload(
          argumentsBytes: Uint8List.fromList(bytes),
          argumentsDecoder: (_) =>
              throw StateError('Unexpected materialization'),
          encoding: LazyPayloadEncoding.cbor,
        );
      expect(() => encode(call), throwsFormatException);
    }
  });

  test('raw lazy CBOR keyword maps are validated before writing', () {
    for (final bytes in [
      <int>[0x80], // A valid array is the wrong root type for kwargs.
      <int>[0xa0, 0xff], // A valid map followed by a trailing break.
    ]) {
      final call = Call(1, 'com.proc')
        ..setLazyPayload(
          argumentsKeywordsBytes: Uint8List.fromList(bytes),
          argumentsKeywordsDecoder: (_) =>
              throw StateError('Unexpected materialization'),
          encoding: LazyPayloadEncoding.cbor,
        );
      expect(() => encode(call), throwsFormatException);
    }
  });

  test('reuse an already-built vector without invoking the model decoder', () {
    final input = Uint8List.fromList(cbor.encode(CborValue([1, 'payload'])));
    final call = Call(1, 'com.proc')
      ..setLazyPayload(
        argumentsBytes: input,
        argumentsDecoder: (_) => throw StateError('Unexpected materialization'),
        encoding: LazyPayloadEncoding.json,
      );
    final builder = WampFlatBufferBuilder(initialSize: 64);
    final vector = FlatBufferByteVectorReference(
      builder,
      builder.writeListUint8(input),
    );
    builder.finish(
      writeWampFlatBufferMessage(call, builder, argumentsVector: vector),
    );
    validateWampFlatBuffer(builder.buffer);
    final result = wire.Message(builder.buffer).msg as wire.Call;
    expect(result.args, input);
    final data = ByteData.sublistView(builder.buffer);
    final root = data.getUint32(0, Endian.little);
    final rootVtable = root - data.getInt32(root, Endian.little);
    final msgField = root + data.getUint16(rootVtable + 6, Endian.little);
    final body = msgField + data.getUint32(msgField, Endian.little);
    final vtable = body - data.getInt32(body, Endian.little);
    final argsField = body + data.getUint16(vtable + 10, Endian.little);
    final argsOffset = argsField + data.getUint32(argsField, Endian.little);
    expect(argsOffset, builder.buffer.length - vector.offset);
  });

  test('transparent payload is retained without lazy argument decoding', () {
    final call = Call(
      1,
      'com.proc',
      options: CallOptions(pptScheme: 'opaque', pptSerializer: 'flatbuffers'),
    )..transparentBinaryPayload = Uint8List.fromList([1, 2, 3]);
    call.setLazyPayload(
      argumentsBytes: Uint8List.fromList([0]),
      argumentsDecoder: (_) => throw StateError('Unexpected materialization'),
      encoding: LazyPayloadEncoding.cbor,
    );
    final result = wire.Message(encode(call)).msg as wire.Call;
    expect(result.payload, [1, 2, 3]);
    expect(result.args, isNull);
    expect(result.pptSerializer.value, 6);
  });

  test(
    'control-only writes preserve PPT metadata without reading payloads',
    () {
      final call =
          Call(
            1,
            'com.proc',
            options: CallOptions(
              pptScheme: 'opaque',
              pptSerializer: 'flatbuffers',
            ),
          )..setLazyPayload(
            argumentsBytes: Uint8List.fromList([0x80]),
            argumentsDecoder: (_) =>
                throw StateError('Unexpected materialization'),
            encoding: LazyPayloadEncoding.cbor,
          );
      final builder = WampFlatBufferBuilder(initialSize: 64);
      builder.finish(
        writeWampFlatBufferMessage(
          call,
          builder,
          includeApplicationPayload: false,
        ),
      );
      validateWampFlatBuffer(builder.buffer);
      final decoded = wire.Message(builder.buffer);
      final message = decoded.msg as wire.Call;
      expect(message.args, isNull);
      expect(message.kwargs, isNull);
      expect(message.payload, isNull);
      expect(metadata(decoded), {
        'ppt_scheme': 'opaque',
        'ppt_serializer': 'flatbuffers',
      });
    },
  );

  test('invalid types, IDs and unsupported messages are rejected', () {
    expect(
      () => encode(
        Call(
          1,
          'com.proc',
          options: CallOptions(custom: {'receive_progress': 'yes'}),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => encode(Call(9007199254740994, 'com.proc')),
      throwsArgumentError,
    );
    expect(() => encode(UnknownMessage(999)), throwsUnsupportedError);
    expect(
      () => encode(Error(49, 1, {}, 'wamp.error.test')),
      throwsArgumentError,
    );
    expect(
      () => encode(Abort('wamp.error.test', arguments: [])),
      throwsUnsupportedError,
    );
  });

  test('HEARTBEAT absent controls and zero have different presence bits', () {
    final absent = wire.Message(encode(Heartbeat())).msg as wire.Heartbeat;
    final zero =
        wire.Message(encode(Heartbeat(ping: 0, incoming: 0, outgoing: 0))).msg
            as wire.Heartbeat;
    expect(absent.presence, 0);
    expect(zero.presence, 7);
  });

  test('metadata construction rejects depth, cycles and oversized bytes', () {
    Object? deep;
    for (var i = 0; i < 64; i++) {
      deep = [deep];
    }
    expect(
      () => encode(Heartbeat(details: {'_deep': deep})),
      throwsArgumentError,
    );
    final cycle = <Object?>[];
    cycle.add(cycle);
    expect(
      () => encode(Heartbeat(details: {'_cycle': cycle})),
      throwsArgumentError,
    );
    expect(
      () => encode(Heartbeat(details: {'_large': Uint8List(1048576)})),
      throwsArgumentError,
    );
  });

  test('metadata construction accepts shared acyclic values', () {
    final shared = {
      'key': [1, 2],
    };
    final result = wire.Message(
      encode(Heartbeat(details: {'a': shared, 'b': shared})),
    );
    expect(metadata(result), {'a': shared, 'b': shared});
  });

  test('CBOR date values survive metadata and application arguments', () {
    final date = DateTime.utc(2026, 10, 3, 12, 34, 56);
    final result = wire.Message(
      encode(
        Call(
          1,
          'com.date',
          options: CallOptions(custom: {'_date': date}),
          arguments: [date],
        ),
      ),
    );
    expect(metadata(result)['_date'], date);
    final call = result.msg as wire.Call;
    expect(cbor.decode(call.args!).toObject(), [date]);
  });
}

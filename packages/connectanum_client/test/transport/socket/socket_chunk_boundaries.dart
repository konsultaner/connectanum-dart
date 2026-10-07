part of 'socket_transport_test.dart';

void _controlledSocketChunks() {
  for (final (name, serializer, serializerType)
      in <(String, AbstractSerializer, int)>[
        ('json', json_serializer.Serializer(), SocketHelper.serializationJson),
        (
          'msgpack',
          msgpack_serializer.Serializer(),
          SocketHelper.serializationMsgpack,
        ),
        ('cbor', cbor_serializer.Serializer(), SocketHelper.serializationCbor),
      ]) {
    for (final length in [64, 70 * 1024]) {
      for (final split in [1, 3, 4, 11]) {
        test(
          '$name preserves ordered frames across controlled split $split/$length',
          () async {
            final socket = _ChunkSocket();
            final transport = SocketTransport(
              'localhost',
              12345,
              serializer,
              serializerType,
            );
            addTearDown(transport.close);
            await IOOverrides.runZoned(
              transport.open,
              socketConnect:
                  (
                    host,
                    port, {
                    sourceAddress,
                    int sourcePort = 0,
                    timeout,
                  }) async {
                    expect(host, 'localhost');
                    expect(port, 12345);
                    return socket;
                  },
            );
            final received = <AbstractMessage>[];
            final errors = <Object>[];
            final subscription = transport.receive().listen(
              received.add,
              onError: errors.add,
            );
            addTearDown(subscription.cancel);
            expect(socket.writes, [
              SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthExponent,
                serializerType,
              ),
            ]);
            socket.feed(
              SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthExponent,
                serializerType,
              ),
            );
            await transport.onReady;
            expect(transport.isReady, isTrue);

            final payload = Uint8List.fromList(
              List.generate(length, (i) => i & 255),
            );
            Uint8List frame(int id) {
              final encoded = serializer.serialize(
                Result(id, ResultDetails(), arguments: [payload]),
              );
              final bytes = encoded is String
                  ? utf8.encode(encoded)
                  : encoded as List<int>;
              return (BytesBuilder(copy: false)
                    ..add(
                      SocketHelper.buildMessageHeader(
                        SocketHelper.messageWamp,
                        bytes.length,
                        false,
                      ),
                    )
                    ..add(bytes))
                  .takeBytes();
            }

            final frames = [frame(7), frame(8), frame(9)];
            socket.feed(
              (BytesBuilder(copy: false)
                    ..add(frames[0])
                    ..add(Uint8List.sublistView(frames[1], 0, split)))
                  .takeBytes(),
            );
            expect(
              received,
              hasLength(1),
              reason: 'Do not emit the incomplete second frame',
            );
            socket.feed(
              Uint8List.sublistView(frames[1], split, frames[1].length - 2),
            );
            expect(
              received,
              hasLength(1),
              reason: 'The declared payload still needs two bytes',
            );
            socket.feed(
              (BytesBuilder(copy: false)
                    ..add(
                      Uint8List.sublistView(frames[1], frames[1].length - 2),
                    )
                    ..add(frames[2]))
                  .takeBytes(),
            );

            expect(errors, isEmpty);
            expect(received, hasLength(3));
            for (var index = 0; index < 3; index++) {
              final result = received[index] as Result;
              expect(result.callRequestId, index + 7);
              expect(result.arguments, hasLength(1));
              expect(result.arguments!.single, orderedEquals(payload));
            }
            expect(
              socket.writes,
              hasLength(1),
              reason: 'Valid fragmentation must not produce protocol errors',
            );
            expect(transport.isReady, isTrue);
            await transport.close();
            expect(transport.isOpen, isFalse);
            expect(socket.destroyCount, 1);
          },
        );
      }
    }
  }
}

class _ChunkSocket extends Stream<Uint8List> implements Socket {
  final _incoming = StreamController<Uint8List>(sync: true);
  final _done = Completer<void>();
  final writes = <List<int>>[];
  final submitted = <List<int>>[];
  var destroyCount = 0;

  void feed(List<int> bytes) => _incoming.add(Uint8List.fromList(bytes));

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  void add(List<int> bytes) {
    submitted.add(bytes);
    writes.add(List.of(bytes));
  }

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  Future<void> get done => _done.future;

  @override
  Future<E> drain<E>([E? futureValue]) async => futureValue as E;

  @override
  Future<Socket> close() async => this;

  @override
  void destroy() {
    destroyCount++;
    if (!_done.isCompleted) {
      _done.complete();
      unawaited(_incoming.close());
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _segmentedSocketSends() {
  for (final (name, serializer, serializerType)
      in <(String, AbstractSerializer, int)>[
        ('cbor', cbor_serializer.Serializer(), SocketHelper.serializationCbor),
        (
          'msgpack',
          msgpack_serializer.Serializer(),
          SocketHelper.serializationMsgpack,
        ),
        (
          'flatbuffers',
          flatbuffers_serializer.Serializer(),
          SocketHelper.serializationFlatBuffers,
        ),
      ]) {
    for (final length in [23, 65536]) {
      test(
        '$name sends segmented $length-byte body with one small-frame copy',
        () async {
          final socket = _ChunkSocket();
          final transport = SocketTransport(
            'localhost',
            12345,
            serializer,
            serializerType,
          );
          addTearDown(transport.close);
          await IOOverrides.runZoned(
            transport.open,
            socketConnect:
                (
                  host,
                  port, {
                  sourceAddress,
                  int sourcePort = 0,
                  timeout,
                }) async => socket,
          );
          final subscription = transport.receive().listen((_) {});
          addTearDown(subscription.cancel);
          socket.feed(
            SocketHelper.getInitialHandshake(
              SocketHelper.maxMessageLengthExponent,
              serializerType,
            ),
          );
          await transport.onReady;
          if (name == 'flatbuffers') {
            final hello = Hello('realm', Details.forHello());
            transport.send(hello);
            final profile = const FlatBuffersSessionProfile.router()
                .acceptIncoming(hello);
            final welcome = Welcome(9, Details.forWelcome());
            profile.prepareOutgoing(welcome);
            final bytes = serializer.serialize(welcome) as Uint8List;
            socket.feed(
              (BytesBuilder(copy: false)
                    ..add(
                      SocketHelper.buildMessageHeader(
                        SocketHelper.messageWamp,
                        bytes.length,
                        false,
                      ),
                    )
                    ..add(bytes))
                  .takeBytes(),
            );
          }
          socket.writes.clear();
          socket.submitted.clear();
          final body = Uint8List(length);
          final message = name == 'flatbuffers'
              ? (Call(
                  42,
                  'com.probe',
                  options: CallOptions(
                    pptScheme: 'opaque',
                    pptSerializer: 'flatbuffers',
                  ),
                )..transparentBinaryPayload = body)
              : Call(42, 'com.probe', arguments: [body]);
          final fragments = serializer.serializeFragments(message)!;
          final payload = (BytesBuilder(
            copy: false,
          )..addAllFragments(fragments)).takeBytes();
          DartTransportCopyMetrics.beginWindow();
          late DartTransportCopyMetricsSnapshot copies;
          try {
            transport.send(message);
          } finally {
            copies = DartTransportCopyMetrics.endWindow();
          }
          final wire = (BytesBuilder(
            copy: false,
          )..addAllFragments(socket.writes)).takeBytes();
          expect(
            SocketHelper.getPayloadLength(Uint8List.sublistView(wire, 0, 4), 4),
            payload.length,
          );
          expect(Uint8List.sublistView(wire, 4), payload);
          final decoded =
              serializer.deserialize(Uint8List.sublistView(wire, 4)) as Call;
          expect(decoded.requestId, 42);
          expect(decoded.procedure, 'com.probe');
          expect(
            name == 'flatbuffers'
                ? decoded.transparentBinaryPayload
                : decoded.arguments!.single,
            body,
          );
          if (length == 23) {
            expect(socket.submitted, hasLength(1));
            expect(copies.rawSocketFramePayloadCopiedBytes, payload.length);
            expect(copies.rawSocketFragmentCoalesceCopiedBytes, 0);
            expect(copies.knownOwnCopyBytes, payload.length);
          } else {
            expect(
              socket.submitted,
              hasLength(1 + fragments.where((p) => p.isNotEmpty).length),
            );
            expect(socket.submitted.any((p) => identical(p, body)), true);
            expect(copies.knownOwnCopyBytes, 0);
          }
        },
      );
    }
  }
}

extension on BytesBuilder {
  void addAllFragments(Iterable<List<int>> fragments) {
    for (final fragment in fragments) {
      add(fragment);
    }
  }
}

void _nativeRangeSocketSends() {
  for (final (name, serializer, serializerType)
      in <(String, AbstractSerializer, int)>[
        ('cbor', cbor_serializer.Serializer(), SocketHelper.serializationCbor),
        (
          'msgpack',
          msgpack_serializer.Serializer(),
          SocketHelper.serializationMsgpack,
        ),
        (
          'flatbuffers',
          flatbuffers_serializer.Serializer(),
          SocketHelper.serializationFlatBuffers,
        ),
      ]) {
    for (final offset in [17, 37]) {
      for (final readonly in [false, true]) {
        test(
          '$name sends bounded native range offset=$offset readonly=$readonly',
          () async {
            const length = 65536;
            final root = allocateNativeExternalBytes(length + 96);
            for (var i = 0; i < root.length; i++) {
              root[i] = (i * 37 + 11) & 255;
            }
            var body = Uint8List.sublistView(root, offset, offset + length);
            if (readonly) body = body.asUnmodifiableView();
            final expectedAddress =
                nativeExternalByteSlice(root)!.pointer.address + offset;
            final socket = _ChunkSocket();
            final transport = SocketTransport(
              'localhost',
              12345,
              serializer,
              serializerType,
            );
            addTearDown(transport.close);
            await IOOverrides.runZoned(
              transport.open,
              socketConnect:
                  (
                    host,
                    port, {
                    sourceAddress,
                    int sourcePort = 0,
                    timeout,
                  }) async => socket,
            );
            final subscription = transport.receive().listen((_) {});
            addTearDown(subscription.cancel);
            socket.feed(
              SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthExponent,
                serializerType,
              ),
            );
            await transport.onReady;
            if (name == 'flatbuffers') {
              final hello = Hello('realm', Details.forHello());
              transport.send(hello);
              final profile = const FlatBuffersSessionProfile.router()
                  .acceptIncoming(hello);
              final welcome = Welcome(9, Details.forWelcome());
              profile.prepareOutgoing(welcome);
              final encoded = serializer.serialize(welcome) as Uint8List;
              socket.feed(
                (BytesBuilder(copy: false)
                      ..add(
                        SocketHelper.buildMessageHeader(
                          SocketHelper.messageWamp,
                          encoded.length,
                          false,
                        ),
                      )
                      ..add(encoded))
                    .takeBytes(),
              );
            }
            socket.submitted.clear();
            socket.writes.clear();
            final message = name == 'flatbuffers'
                ? (Call(
                    42,
                    'com.native.range',
                    options: CallOptions(
                      pptScheme: 'opaque',
                      pptSerializer: 'flatbuffers',
                    ),
                  )..transparentBinaryPayload = body)
                : Call(42, 'com.native.range', arguments: [body]);
            retainNativeExternalBytes(message, root);
            final expected = serializer.serialize(message) as Uint8List;
            DartTransportCopyMetrics.beginWindow();
            late DartTransportCopyMetricsSnapshot copies;
            try {
              transport.send(message);
            } finally {
              copies = DartTransportCopyMetrics.endWindow();
            }
            final submitted =
                socket.submitted.singleWhere((p) => p.length == length)
                    as Uint8List;
            expect(
              submitted.buffer.lengthInBytes,
              length,
              reason:
                  'A bounded external buffer must avoid the SDK partial-view copy',
            );
            expect(submitted.offsetInBytes, 0);
            expect(submitted, orderedEquals(body));
            final native = nativeExternalByteSlice(submitted);
            expect(native, isNotNull);
            expect(native!.pointer.address, expectedAddress);
            expect(native.length, length);
            final wire = (BytesBuilder(
              copy: false,
            )..addAllFragments(socket.writes)).takeBytes();
            final payload = Uint8List.sublistView(wire, 4);
            if (name != 'flatbuffers') {
              expect(payload, orderedEquals(expected));
            }
            final parsed = serializer.deserialize(payload) as Call;
            expect(parsed.requestId, 42);
            expect(parsed.procedure, 'com.native.range');
            if (name == 'flatbuffers') {
              expect(parsed.transparentBinaryPayload, orderedEquals(body));
              expect(parsed.options!.pptScheme, 'opaque');
              expect(parsed.options!.pptSerializer, 'flatbuffers');
            } else {
              expect(parsed.arguments!.single, orderedEquals(body));
            }
            expect(copies.knownOwnCopyBytes, 0);
          },
        );
      }
    }
  }
}

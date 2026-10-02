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
  void add(List<int> bytes) => writes.add(List.of(bytes));

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  Future<void> get done => _done.future;

  @override
  Future<E> drain<E>([E? futureValue]) async => futureValue as E;

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

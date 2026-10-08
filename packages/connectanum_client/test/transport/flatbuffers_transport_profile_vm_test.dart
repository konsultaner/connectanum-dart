@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_client/src/transport/socket/socket_helper.dart';
import 'package:connectanum_client/src/transport/socket/socket_transport.dart';
import 'package:connectanum_client/src/transport/websocket/websocket_transport_io.dart';
import 'package:connectanum_client/src/transport/websocket/websocket_transport_serialization.dart';
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:test/test.dart';

const _deadline = Duration(seconds: 5);

Future<core.AbstractMessage> _next(
  StreamIterator<core.AbstractMessage> input,
) async {
  expect(await input.moveNext().timeout(_deadline), isTrue);
  return input.current;
}

class _FailingCodec extends flat.Serializer {
  int? failMessage;

  @override
  Uint8List serialize(core.AbstractMessage message) {
    if (message.id == failMessage) {
      failMessage = null;
      throw StateError('Deliberate encoding failure');
    }
    return super.serialize(message);
  }
}

StreamIterator<core.AbstractMessage> _incoming(
  client.AbstractTransport channel,
) {
  var listened = false;
  final controller = StreamController<core.AbstractMessage>(
    onListen: () => listened = true,
  );
  final subscription = channel.receive()!.listen(
    (message) {
      if (message != null) controller.add(message);
    },
    onError: controller.addError,
    onDone: controller.close,
  );
  addTearDown(() async {
    await subscription.cancel();
    // A failed assertion before the first moveNext must still drain teardown.
    if (!listened) controller.stream.listen((_) {});
    await controller.close();
  });
  return StreamIterator(controller.stream);
}

void main() {
  for (final size in [2048, 128 * 1024]) {
    test(
      'peer-limit rejects $size-byte outgoing payload before socket write',
      () async {
        final peer = await _Peer.start(rawPeerMaxExponent: 11);
        final channel = SocketTransport.withFlatBuffersSerializer(
          '127.0.0.1',
          peer.port,
          messageLengthExponent: 20,
        );
        StreamIterator<core.AbstractMessage>? input;
        try {
          await channel.open();
          input = _incoming(channel);
          await channel.onReady.timeout(_deadline);
          channel.send(core.Hello('realm', core.Details.forHello()));
          expect(await _next(input), isA<core.Welcome>());
          expect(channel.maxMessageLength, 2048);
          final message = core.Call(1, 'echo', arguments: ['x' * size]);
          expect(
            flat.Serializer().serialize(message).length,
            greaterThan(2048),
          );
          expect(() => channel.send(message), throwsStateError);
          // A valid retry proves rejection did not leave a partial frame header.
          channel.send(core.Call(2, 'echo', arguments: [42]));
          expect((await _next(input) as core.Result).arguments, [42]);
          expect(peer.codes, [1, 48]);
        } finally {
          await channel.close();
          await input?.cancel();
          await peer.dispose();
        }
      },
    );
  }
  test(
    'peer-limit rejected immediate HELLO leaves profile retryable',
    () async {
      final peer = await _Peer.start(rawPeerMaxExponent: 11);
      final channel = SocketTransport.withFlatBuffersSerializer(
        '127.0.0.1',
        peer.port,
        messageLengthExponent: 20,
      );
      StreamIterator<core.AbstractMessage>? input;
      try {
        await channel.open();
        input = _incoming(channel);
        await channel.onReady.timeout(_deadline);
        final oversized = core.Hello('x' * 5000, core.Details.forHello());
        expect(
          flat.Serializer().serialize(oversized).length,
          greaterThan(2048),
        );
        expect(() => channel.send(oversized), throwsStateError);
        channel.send(core.Hello('realm', core.Details.forHello()));
        expect(await _next(input), isA<core.Welcome>());
        expect(
          (await peer.firstMessageReceived.future as core.Hello).realm,
          'realm',
        );
        expect(peer.codes, [1]);
      } finally {
        await channel.close();
        await input?.cancel();
        await peer.dispose();
      }
    },
  );
  test(
    'peer-limit rejects queued HELLO after smaller peer handshake',
    () async {
      final peer = await _Peer.start(
        rawPeerMaxExponent: 11,
        holdNegotiation: true,
      );
      final channel = SocketTransport.withFlatBuffersSerializer(
        '127.0.0.1',
        peer.port,
        messageLengthExponent: 20,
      );
      StreamSubscription<core.AbstractMessage?>? input;
      try {
        await channel.open();
        input = channel.receive().listen((_) {}, onError: (Object error) {});
        await peer.handshakeReceived.future.timeout(_deadline);
        final message = core.Hello('x' * 5000, core.Details.forHello());
        expect(flat.Serializer().serialize(message).length, greaterThan(2048));
        channel.send(message);
        peer.negotiate();
        final terminal = await Future.any<Object?>([
          channel.onConnectionLost!.future,
          peer.firstMessageReceived.future,
        ]).timeout(_deadline);
        expect(terminal, isA<StateError>());
        expect(peer.codes, isEmpty);
      } finally {
        await channel.close();
        await input?.cancel();
        await peer.dispose();
      }
    },
  );
  for (final websocket in [false, true]) {
    final kind = websocket ? 'WebSocket' : 'RawSocket';
    client.AbstractTransport transport(_Peer peer, {flat.Serializer? codec}) =>
        websocket
        ? WebSocketTransport(
            'ws://127.0.0.1:${peer.port}/ws',
            codec ?? flat.Serializer(),
            WebSocketSerialization.serializationFlatBuffers,
          )
        : SocketTransport(
            '127.0.0.1',
            peer.port,
            codec ?? flat.Serializer(),
            5,
            messageLengthExponent: 20,
          );

    test('$kind rejects mismatched FlatBuffers codec before opening', () {
      for (final selected in [true, false]) {
        expect(
          () => websocket
              ? WebSocketTransport(
                  'ws://127.0.0.1:1/ws',
                  selected ? json.Serializer() : flat.Serializer(),
                  selected ? 'wamp.2.flatbuffers' : 'wamp.2.json',
                )
              : SocketTransport(
                  '127.0.0.1',
                  1,
                  selected ? json.Serializer() : flat.Serializer(),
                  selected ? 5 : 1,
                ),
          throwsArgumentError,
        );
      }
    });

    for (final scenario in ['anonymous', 'ticket']) {
      test(
        '$kind $scenario RPC/pubsub/progress/error/128KiB and reopen',
        () async {
          final peer = await _Peer.start(
            websocket: websocket,
            scenario: scenario,
          );
          final channel = transport(peer);
          StreamIterator<core.AbstractMessage>? input;
          try {
            for (var round = 0; round < 2; round++) {
              await channel.open();
              input = _incoming(channel);
              await channel.onReady.timeout(_deadline);
              expect(
                () => channel.send(core.Call(1, 'echo')),
                throwsStateError,
              );
              channel.send(core.Hello('realm', core.Details.forHello()));
              if (scenario == 'ticket') {
                expect(await _next(input), isA<core.Challenge>());
                channel.send(core.Authenticate(signature: 'secret'));
              }
              expect(await _next(input), isA<core.Welcome>());

              final data = Uint8List.fromList(
                List.generate(128 * 1024, (i) => i % 251),
              );
              channel.send(
                core.Call(
                  1,
                  'echo',
                  arguments: [data],
                  options: core.CallOptions(receiveProgress: true),
                ),
              );
              final progress = await _next(input) as core.Result;
              expect(progress.details.progress, isTrue);
              expect(progress.arguments, ['progress']);
              final result = await _next(input) as core.Result;
              expect(result.arguments!.single, orderedEquals(data));
              channel.send(core.Call(2, 'missing'));
              final error = await _next(input) as core.Error;
              expect(error.requestId, 2);
              expect(error.error, 'wamp.error.no_such_procedure');
              channel.send(core.Subscribe(3, 'topic'));
              expect(await _next(input), isA<core.Subscribed>());
              channel.send(core.Publish(4, 'topic', arguments: [data]));
              final event = await _next(input) as core.Event;
              expect(event.arguments!.single, orderedEquals(data));
              channel.send(core.Goodbye(null, 'wamp.close.normal'));
              expect(await _next(input), isA<core.Goodbye>());
              await channel.close();
              await input.cancel();
              input = null;
            }
            expect(
              peer.codes,
              scenario == 'ticket'
                  ? [1, 5, 48, 48, 32, 16, 6, 1, 5, 48, 48, 32, 16, 6]
                  : [1, 48, 48, 32, 16, 6, 1, 48, 48, 32, 16, 6],
            );
          } finally {
            await channel.close();
            await input?.cancel();
            await peer.dispose();
          }
        },
      );
    }

    for (final scenario in ['missing-challenge', 'missing-welcome']) {
      test(
        '$kind $scenario rejected before auth/application delivery',
        () async {
          final peer = await _Peer.start(
            websocket: websocket,
            scenario: scenario,
          );
          final channel = transport(peer);
          final delivered = <core.AbstractMessage>[];
          var credentials = 0;
          await channel.open();
          final subscription = channel.receive()!.listen((message) {
            if (message == null) return;
            delivered.add(message);
            if (message is core.Challenge) {
              credentials++;
              channel.send(core.Authenticate(signature: 'secret'));
            }
          });
          try {
            await channel.onReady.timeout(_deadline);
            channel.send(core.Hello('realm', core.Details.forHello()));
            expect(
              await channel.onConnectionLost!.future.timeout(_deadline),
              isA<UnsupportedError>(),
            );
            expect(credentials, scenario == 'missing-challenge' ? 0 : 1);
            expect(delivered.whereType<core.Welcome>(), isEmpty);
            expect(peer.codes, scenario == 'missing-challenge' ? [1] : [1, 5]);
          } finally {
            await channel.close();
            await subscription.cancel();
            await peer.dispose();
          }
        },
      );
    }

    test(
      '$kind serialization rejection does not commit HELLO or GOODBYE',
      () async {
        final peer = await _Peer.start(websocket: websocket);
        final codec = _FailingCodec()
          ..failMessage = core.MessageTypes.codeHello;
        final channel = transport(peer, codec: codec);
        await channel.open();
        final input = _incoming(channel);
        try {
          await channel.onReady.timeout(_deadline);
          final hello = core.Hello('realm', core.Details.forHello());
          expect(() => channel.send(hello), throwsStateError);
          expect(peer.codes, isEmpty);
          channel.send(hello);
          expect(await _next(input), isA<core.Welcome>());
          codec.failMessage = core.MessageTypes.codeGoodbye;
          expect(
            () => channel.send(core.Goodbye(null, 'wamp.close.normal')),
            throwsStateError,
          );
          channel.send(core.Call(7, 'echo', arguments: ['still established']));
          expect((await _next(input) as core.Result).arguments, [
            'still established',
          ]);
          channel.send(core.Goodbye(null, 'wamp.close.normal'));
          expect(await _next(input), isA<core.Goodbye>());
          expect(peer.codes, [1, 48, 6]);
        } finally {
          await channel.close();
          await input.cancel();
          await peer.dispose();
        }
      },
    );
  }

  for (final unsolicitedUpgrade in [false, true]) {
    test(
      'RawSocket rejects ${unsolicitedUpgrade ? "unsolicited upgrade" : "different serializer"}',
      () async {
        final server = await ServerSocket.bind('127.0.0.1', 0);
        final sockets = <Socket>[];
        final subscription = server.listen((peer) {
          sockets.add(peer);
          var replied = false;
          peer.listen((_) {
            if (replied) return;
            replied = true;
            peer.add(unsolicitedUpgrade ? [0x3f, 0] : [0x7f, 0xb2, 0, 0]);
          });
        });
        final channel = SocketTransport(
          '127.0.0.1',
          server.port,
          json.Serializer(),
          1,
          messageLengthExponent: 20,
        );
        StreamSubscription<core.AbstractMessage>? incoming;
        try {
          await channel.open();
          incoming = channel.receive().listen((_) {});
          await expectLater(
            channel.onReady.timeout(_deadline),
            throwsA(
              isA<Map>().having(
                (error) => error['errorNumber'],
                'errorNumber',
                unsolicitedUpgrade
                    ? SocketHelper.errorUseOfReservedBits
                    : SocketHelper.errorSerializerNotSupported,
              ),
            ),
          );
          expect(channel.isOpen, isFalse);
          expect(channel.isReady, isFalse);
        } finally {
          for (final socket in sockets) {
            socket.destroy();
          }
          await incoming?.cancel();
          await channel.close();
          await subscription.cancel();
          await server.close();
        }
      },
    );
  }
  test('RawSocket close completes without receive consumption', () async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final accepted = Completer<Socket>();
    final subscription = server.listen((peer) {
      accepted.complete(peer);
      peer.listen((_) {});
    });
    final channel = SocketTransport(
      '127.0.0.1',
      server.port,
      json.Serializer(),
      1,
    );
    Socket? peer;
    try {
      await channel.open();
      peer = await accepted.future.timeout(_deadline);
      await channel.close().timeout(_deadline);
      expect(channel.isOpen, isFalse);
    } finally {
      peer?.destroy();
      await subscription.cancel();
      await server.close();
    }
  });
  test(
    'RawSocket rejected oversized queued HELLO leaves profile retryable',
    () async {
      final peer = await _Peer.start(holdNegotiation: true);
      final codec = flat.Serializer();
      final channel = SocketTransport(
        '127.0.0.1',
        peer.port,
        codec,
        5,
        messageLengthExponent: 12,
      );
      StreamIterator<core.AbstractMessage>? input;
      try {
        await channel.open();
        input = _incoming(channel);
        await peer.handshakeReceived.future.timeout(_deadline);
        final oversized = core.Hello('x' * 10000, core.Details.forHello());
        expect(codec.serialize(oversized).length, greaterThan(1 << 12));
        expect(() => channel.send(oversized), throwsStateError);
        final retry = core.Hello('realm', core.Details.forHello());
        expect(codec.serialize(retry).length, lessThan(1 << 12));
        channel.send(retry);
        expect(peer.codes, isEmpty);
        peer.negotiate();
        await channel.onReady.timeout(_deadline);
        expect(await _next(input), isA<core.Welcome>());
        expect(peer.codes, [1]);
      } finally {
        await channel.close();
        await input?.cancel();
        await peer.dispose();
      }
    },
  );

  for (final exponent in [20, 30]) {
    test(
      'RawSocket queues two messages using negotiated ${exponent == 30 ? 5 : 4}-byte headers',
      () async {
        final peer = await _Peer.start(
          holdNegotiation: true,
          flatbuffers: false,
          autoReply: false,
        );
        final channel = SocketTransport(
          '127.0.0.1',
          peer.port,
          json.Serializer(),
          1,
          messageLengthExponent: exponent,
        );
        await channel.open();
        final subscription = channel.receive().listen((_) {});
        try {
          await peer.handshakeReceived.future.timeout(_deadline);
          channel.send(core.Hello('realm', core.Details.forHello()));
          channel.send(core.Call(8, 'echo', arguments: ['queued']));
          expect(channel.isReady, isFalse);
          expect(peer.codes, isEmpty);
          peer.negotiate();
          await peer.receivedTwo.future.timeout(_deadline);
          expect(peer.codes, [1, 48]);
          expect(peer.headerLength, exponent == 30 ? 5 : 4);
        } finally {
          await channel.close();
          await subscription.cancel();
          await peer.dispose();
        }
      },
    );
  }
}

class _Peer {
  _Peer({
    required this.scenario,
    required this.flatbuffers,
    required this.holdNegotiation,
    required this.autoReply,
    this.rawPeerMaxExponent,
  });
  final String scenario;
  final bool flatbuffers;
  final bool holdNegotiation;
  final bool autoReply;
  final int? rawPeerMaxExponent;
  final firstMessageReceived = Completer<core.AbstractMessage>();
  final codes = <int>[];
  final handshakeReceived = Completer<void>();
  final receivedTwo = Completer<void>();
  final rawSockets = <Socket>[];
  final webSockets = <WebSocket>[];
  ServerSocket? rawServer;
  HttpServer? webServer;
  late int port;
  int headerLength = 4;
  void Function()? negotiatePending;

  static Future<_Peer> start({
    bool websocket = false,
    String scenario = 'anonymous',
    bool flatbuffers = true,
    bool holdNegotiation = false,
    bool autoReply = true,
    int? rawPeerMaxExponent,
  }) async {
    final peer = _Peer(
      scenario: scenario,
      flatbuffers: flatbuffers,
      holdNegotiation: holdNegotiation,
      autoReply: autoReply,
      rawPeerMaxExponent: rawPeerMaxExponent,
    );
    if (websocket) {
      final server = await HttpServer.bind('127.0.0.1', 0);
      peer.webServer = server;
      peer.port = server.port;
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (protocols) => protocols.single,
        );
        expect(socket.protocol, 'wamp.2.flatbuffers');
        peer.webSockets.add(socket);
        final codec = flat.Serializer();
        final respond = peer.responder(
          (message) => socket.add(codec.serialize(message)),
        );
        socket.listen(
          (data) => respond(
            codec.deserialize(Uint8List.fromList(data as List<int>))!,
          ),
        );
      });
    } else {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      peer.rawServer = server;
      peer.port = server.port;
      server.listen(peer.acceptRaw);
    }
    return peer;
  }

  core.AbstractSerializer get codec =>
      flatbuffers ? flat.Serializer() : json.Serializer();

  void Function(core.AbstractMessage) responder(
    void Function(core.AbstractMessage) writeBytes,
  ) {
    var profile = const flat.FlatBuffersSessionProfile.router();
    void write(core.AbstractMessage message, {bool acknowledge = true}) {
      if (flatbuffers && acknowledge) {
        profile = profile.prepareOutgoing(message);
      }
      writeBytes(message);
    }

    return (message) {
      codes.add(message.id);
      if (!firstMessageReceived.isCompleted) {
        firstMessageReceived.complete(message);
      }
      if (codes.length == 2 && !receivedTwo.isCompleted) receivedTwo.complete();
      if (!autoReply) return;
      if (flatbuffers &&
          (scenario != 'missing-challenge' || message is core.Hello)) {
        profile = profile.acceptIncoming(message);
      }
      if (message is core.Hello) {
        if (scenario == 'anonymous') {
          write(core.Welcome(42, core.Details.forWelcome()));
        } else {
          write(
            core.Challenge('ticket', core.Extra()),
            acknowledge: scenario != 'missing-challenge',
          );
        }
      } else if (message is core.Authenticate) {
        expect(message.signature, 'secret');
        write(
          core.Welcome(42, core.Details.forWelcome()),
          acknowledge: scenario != 'missing-welcome',
        );
      } else if (message is core.Call) {
        if (message.procedure == 'missing') {
          write(
            core.Error(
              48,
              message.requestId,
              {},
              'wamp.error.no_such_procedure',
            ),
          );
        } else {
          if (message.options?.receiveProgress == true) {
            write(
              core.Result(
                message.requestId,
                core.ResultDetails(progress: true),
                arguments: ['progress'],
              ),
            );
          }
          write(
            core.Result(
              message.requestId,
              core.ResultDetails(),
              arguments: message.arguments,
            ),
          );
        }
      } else if (message is core.Subscribe) {
        write(core.Subscribed(message.requestId, 100));
      } else if (message is core.Publish) {
        write(
          core.Event(
            100,
            101,
            core.EventDetails(),
            arguments: message.arguments,
          ),
        );
      } else if (message is core.Goodbye) {
        write(core.Goodbye(null, 'wamp.close.goodbye_and_out'));
      }
    };
  }

  void acceptRaw(Socket socket) {
    rawSockets.add(socket);
    final serializer = codec;
    var bytes = Uint8List(0);
    var initial = true;
    var upgrade = false;
    final respond = responder((message) {
      final encoded = serializer.serialize(message);
      final payload = encoded is String
          ? Uint8List.fromList(encoded.codeUnits)
          : encoded as Uint8List;
      socket.add([
        ...SocketHelper.buildMessageHeader(
          0,
          payload.length,
          headerLength == 5,
        ),
        ...payload,
      ]);
    });
    socket.listen((chunk) {
      bytes = Uint8List.fromList([...bytes, ...chunk]);
      if (initial) {
        if (bytes.length < 4) return;
        expect(bytes[0], 0x7f);
        expect(bytes[1] & 15, flatbuffers ? 5 : 1);
        final requested = SocketHelper.getMaxMessageSizeExponent(bytes);
        negotiatePending = () {
          upgrade = requested > 24;
          socket.add(
            SocketHelper.getInitialHandshake(
              rawPeerMaxExponent ?? (upgrade ? 24 : requested),
              flatbuffers ? 5 : 1,
            ),
          );
        };
        bytes = Uint8List.sublistView(bytes, 4);
        initial = false;
        if (!handshakeReceived.isCompleted) handshakeReceived.complete();
        if (!holdNegotiation) negotiate();
      }
      if (bytes.isNotEmpty && bytes[0] == 0x3f) {
        if (bytes.length < 2) return;
        expect(bytes[0], 0x3f);
        socket.add(bytes.sublist(0, 2));
        bytes = Uint8List.sublistView(bytes, 2);
        headerLength = 5;
        upgrade = false;
      }
      while (bytes.length >= headerLength) {
        final length = SocketHelper.getPayloadLength(bytes, headerLength);
        if (bytes.length < headerLength + length) return;
        final payload = Uint8List.sublistView(
          bytes,
          headerLength,
          headerLength + length,
        );
        final message = serializer.deserialize(payload)!;
        bytes = Uint8List.sublistView(bytes, headerLength + length);
        respond(message);
      }
    });
  }

  void negotiate() {
    final pending = negotiatePending!;
    negotiatePending = null;
    pending();
  }

  Future<void> dispose() async {
    for (final socket in rawSockets) {
      socket.destroy();
    }
    for (final socket in webSockets) {
      await socket.close();
    }
    await rawServer?.close();
    await webServer?.close(force: true);
  }
}

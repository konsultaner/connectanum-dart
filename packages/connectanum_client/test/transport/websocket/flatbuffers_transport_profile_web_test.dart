@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_client/src/transport/websocket/websocket_transport_web.dart';
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'websocket_test_observer.dart';

const _timeout = Duration(seconds: 5);
const _serverSource = r'''
import 'dart:io';
import 'dart:typed_data';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  final sockets = <WebSocket>[];
  final profiles = <WebSocket, flat.FlatBuffersSessionProfile>{};
  final codec = flat.Serializer();
  void write(WebSocket socket, AbstractMessage message, {bool acknowledge = true}) {
    if (acknowledge) profiles[socket] = profiles[socket]!.prepareOutgoing(message);
    socket.add(codec.serialize(message));
  }
  server.listen((request) async {
    final socket = request.uri.path == '/wrong'
        ? await WebSocketTransformer.upgrade(request)
        : await WebSocketTransformer.upgrade(request,
            protocolSelector: (protocols) => protocols.single);
    sockets.add(socket);
    profiles[socket] = const flat.FlatBuffersSessionProfile.router();
    socket.listen((data) {
      final message = codec.deserialize(Uint8List.fromList(data as List<int>))!;
      profiles[socket] = profiles[socket]!.acceptIncoming(message);
      channel.sink.add({'received': message.id});
      if (message is Call) {
        write(socket, Result(message.requestId, ResultDetails(), arguments: message.arguments));
      } else if (message is Subscribe) {
        write(socket, Subscribed(message.requestId, 100));
      } else if (message is Publish) {
        write(socket, Event(100, 101, EventDetails(), arguments: message.arguments));
      } else if (message is Goodbye) {
        write(socket, Goodbye(null, 'wamp.close.goodbye_and_out'));
      }
    });
  });
  channel.sink.add(server.port);
  await for (final raw in channel.stream) {
    final command = raw as Map;
    final action = command['action'];
    if (action == 'shutdown') {
      for (final socket in sockets) await socket.close();
      await server.close(force: true);
      channel.sink.add({'reply': command['id']});
      break;
    }
    final socket = sockets.last;
    if (action == 'welcome') {
      write(socket, Welcome(42, Details.forWelcome()), acknowledge: command['ack'] != false);
    } else if (action == 'challenge') {
      write(socket, Challenge('ticket', Extra()), acknowledge: command['ack'] != false);
    } else if (action == 'malformed') {
      socket.add([0, 0, 0, 0]);
    }
    channel.sink.add({'reply': command['id']});
  }
  await channel.sink.close();
}
''';

class _Endpoint {
  _Endpoint() : channel = spawnHybridCode(_serverSource) {
    subscription = channel.stream.listen(
      (event) {
        if (event is num) {
          port.complete(event.toInt());
        } else {
          final value = event as Map;
          if (value['received'] case final num code) codes.add(code.toInt());
          events.add(value);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!port.isCompleted) port.completeError(error, stack);
        events.addError(error, stack);
      },
    );
  }
  final StreamChannel<dynamic> channel;
  final port = Completer<int>();
  final events = StreamController<Map>.broadcast();
  final codes = <int>[];
  late final StreamSubscription<dynamic> subscription;
  var sequence = 0;

  Future<void> command(String action, {bool ack = true}) async {
    final id = sequence++;
    final reply = events.stream.firstWhere((event) => event['reply'] == id);
    channel.sink.add({'id': id, 'action': action, 'ack': ack});
    await reply.timeout(_timeout);
  }

  Future<void> send(
    WebSocketTransport transport,
    core.AbstractMessage message,
  ) async {
    final received = events.stream.firstWhere(
      (event) => event['received'] == message.id,
    );
    transport.send(message);
    await received.timeout(_timeout);
  }

  Future<void> close() async {
    await command('shutdown');
    await subscription.cancel();
    await channel.sink.close();
    await events.close();
  }
}

StreamIterator<core.AbstractMessage> _incoming(WebSocketTransport transport) {
  final controller = StreamController<core.AbstractMessage>();
  final subscription = transport.receive().listen((message) {
    if (message != null) controller.add(message);
  }, onError: controller.addError);
  addTearDown(() async {
    await subscription.cancel();
    await controller.close();
  });
  return StreamIterator(controller.stream);
}

Future<core.AbstractMessage> _next(
  StreamIterator<core.AbstractMessage> input,
) async {
  expect(await input.moveNext().timeout(_timeout), isTrue);
  return input.current;
}

class _CountingCodec extends flat.Serializer {
  int decodes = 0;
  @override
  core.AbstractMessage? deserialize(Uint8List? bytes) {
    decodes++;
    return super.deserialize(bytes);
  }
}

void main() {
  late WebSocketTestObserver observer;
  setUp(() {
    observer = WebSocketTestObserver();
    addTearDown(observer.restore);
  });

  test(
    'browser public native/RawSocket FlatBuffers factories reject unavailable platform',
    () {
      expect(
        () => client.SocketTransport('127.0.0.1', 1, json.Serializer(), 1),
        throwsUnsupportedError,
      );
      expect(
        () => client.SocketTransport.withFlatBuffersSerializer('127.0.0.1', 1),
        throwsUnsupportedError,
      );
      expect(
        () => client.NativeRawSocketTransport.withFlatBuffersSerializer(
          '127.0.0.1',
          1,
        ),
        throwsUnsupportedError,
      );
      expect(
        () => client.NativeWebSocketTransport.withFlatBuffersSerializer(
          'ws://127.0.0.1:1/ws',
        ),
        throwsUnsupportedError,
      );
    },
  );

  test('browser FlatBuffers selection rejects both codec mismatches', () {
    expect(
      () => WebSocketTransport(
        'ws://127.0.0.1:1/ws',
        json.Serializer(),
        'wamp.2.flatbuffers',
      ),
      throwsArgumentError,
    );
    expect(
      () => WebSocketTransport(
        'ws://127.0.0.1:1/ws',
        flat.Serializer(),
        'wamp.2.json',
      ),
      throwsArgumentError,
    );
  });

  test(
    'browser rejects missing FlatBuffers subprotocol before credentials',
    () async {
      final endpoint = _Endpoint();
      final port = await endpoint.port.future;
      final transport = WebSocketTransport.withFlatBuffersSerializer(
        'ws://127.0.0.1:$port/wrong',
      );
      try {
        await expectLater(transport.open(), throwsUnsupportedError);
        expect(transport.isOpen, isFalse);
        expect(endpoint.codes, isEmpty);
      } finally {
        await transport.close();
        await endpoint.close();
      }
    },
  );

  for (final authenticated in [false, true]) {
    test(
      'browser FlatBuffers ${authenticated ? 'ticket' : 'anonymous'} RPC/pubsub/128KiB',
      () async {
        final endpoint = _Endpoint();
        final port = await endpoint.port.future;
        final transport = WebSocketTransport.withFlatBuffersSerializer(
          'ws://127.0.0.1:$port/ws',
        );
        StreamIterator<core.AbstractMessage>? input;
        try {
          await observer.open(transport);
          input = _incoming(transport);
          expect(
            () => transport.send(core.Authenticate(signature: 'early')),
            throwsStateError,
          );
          await endpoint.send(
            transport,
            core.Hello('realm', core.Details.forHello()),
          );
          if (authenticated) {
            await endpoint.command('challenge');
            expect(await _next(input), isA<core.Challenge>());
            await endpoint.send(
              transport,
              core.Authenticate(signature: 'secret'),
            );
          }
          await endpoint.command('welcome');
          expect(await _next(input), isA<core.Welcome>());
          final data = Uint8List.fromList(
            List.generate(128 * 1024, (i) => i % 251),
          );
          transport.send(core.Call(1, 'echo', arguments: [data]));
          expect(
            (await _next(input) as core.Result).arguments!.single,
            orderedEquals(data),
          );
          transport.send(core.Subscribe(2, 'topic'));
          expect(await _next(input), isA<core.Subscribed>());
          transport.send(core.Publish(3, 'topic', arguments: [data]));
          expect(
            (await _next(input) as core.Event).arguments!.single,
            orderedEquals(data),
          );
          transport.send(core.Goodbye(null, 'wamp.close.normal'));
          expect(await _next(input), isA<core.Goodbye>());
        } finally {
          await transport.close();
          await input?.cancel();
          await endpoint.close();
        }
      },
    );
  }

  for (final action in ['challenge', 'welcome']) {
    test(
      'browser rejects unacknowledged $action before application delivery',
      () async {
        final endpoint = _Endpoint();
        final port = await endpoint.port.future;
        final transport = WebSocketTransport.withFlatBuffersSerializer(
          'ws://127.0.0.1:$port/ws',
        );
        final delivered = <core.AbstractMessage>[];
        await observer.open(transport);
        final subscription = transport.receive().listen((message) {
          if (message != null) delivered.add(message);
        });
        try {
          await endpoint.send(
            transport,
            core.Hello('realm', core.Details.forHello()),
          );
          await endpoint.command(action, ack: false);
          expect(
            await transport.onConnectionLost!.future.timeout(_timeout),
            isA<UnsupportedError>(),
          );
          expect(delivered, isEmpty);
          expect(endpoint.codes, [1]);
        } finally {
          await transport.close();
          await subscription.cancel();
          await endpoint.close();
        }
      },
    );
  }

  for (final action in ['welcome', 'malformed']) {
    test('browser ignores old $action Blob after close/reopen', () async {
      final endpoint = _Endpoint();
      final port = await endpoint.port.future;
      final codec = _CountingCodec();
      final transport = WebSocketTransport(
        'ws://127.0.0.1:$port/ws',
        codec,
        'wamp.2.flatbuffers',
      );
      final oldDelivered = <core.AbstractMessage>[];
      await observer.open(transport);
      // Capture must precede the Dart receive listener's Blob read.
      observer.holdNextBinaryFrame();
      final oldSubscription = transport.receive().listen((message) {
        if (message != null) oldDelivered.add(message);
      });
      StreamIterator<core.AbstractMessage>? input;
      try {
        await endpoint.send(
          transport,
          core.Hello('realm', core.Details.forHello()),
        );
        final releaseOld = observer.captureReleaseDecode();
        final delivered = observer.nextMessage();
        await endpoint.command(action);
        await delivered.timeout(_timeout);
        await expectDeliveredCompletion(observer.decodeStarted());
        await transport.close();
        await observer.closed();
        await observer.open(transport);
        input = _incoming(transport);
        // The new profile is HELLO, where an old WELCOME would wrongly fit.
        await endpoint.send(
          transport,
          core.Hello('realm', core.Details.forHello()),
        );
        await releaseOld();
        for (var turn = 0; turn < 3; turn++)
          await Future<void>.delayed(Duration.zero);
        expect(
          codec.decodes,
          0,
          reason: 'A stale Blob must not reach the decoder',
        );
        expect(oldDelivered, isEmpty);
        expect(transport.isOpen, isTrue);
        expect(transport.onConnectionLost!.isCompleted, isFalse);
        expect(
          () => transport.send(core.Call(8, 'too early')),
          throwsStateError,
        );
        await endpoint.command('welcome');
        expect(await _next(input), isA<core.Welcome>());
        transport.send(core.Call(9, 'echo', arguments: ['new connection']));
        expect((await _next(input) as core.Result).arguments, [
          'new connection',
        ]);
      } finally {
        await transport.close();
        await oldSubscription.cancel();
        await input?.cancel();
        await endpoint.close();
      }
    });
  }
}

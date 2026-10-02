@TestOn('browser')
library;

import 'dart:async';

import 'websocket_test_observer.dart';

import 'package:connectanum_client/src/transport/websocket/websocket_transport_web.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

const _serverSource = r'''
import 'dart:io';
import 'dart:typed_data';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack;
import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  final sockets = <WebSocket>[];
  AbstractSerializer serializer(WebSocket socket) => switch(socket.protocol) {
    'wamp.2.json' => json.Serializer(),
    'wamp.2.msgpack' => msgpack.Serializer(),
    _ => cbor.Serializer(),
  };
  server.listen((request) async {
    if (request.uri.path == '/reject') {
      request.response.statusCode = 403;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request,
      protocolSelector: (protocols) => protocols.single);
    sockets.add(socket);
    socket.listen((data) {
      final codec = serializer(socket);
      final message = data is String
        ? (codec as json.Serializer).deserializeFromString(data)
        : codec.deserialize(Uint8List.fromList(data as List<int>));
      channel.sink.add({'event': 'received', 'code': message?.id,
        if (message is Goodbye) 'reason': message.reason});
    });
  });
  channel.sink.add(server.port);
  await for (final raw in channel.stream) {
    final command = raw as Map;
    final action = command['action'];
    if (action == 'shutdown') {
      for (final socket in sockets) { await socket.close(); }
      await server.close(force: true);
      channel.sink.add({'reply': command['id']});
      break;
    }
    final socket = sockets.last;
    if (action == 'close') {
      await socket.close(command['code'] as int);
    } else if (action == 'goodbye') {
      socket.add(serializer(socket).serialize(Goodbye(null, Goodbye.reasonNormal)));
    } else if (action == 'subscribed') {
      final requestId = command['code'] as int;
      socket.add(switch(socket.protocol) {
        'wamp.2.msgpack' => [0x93, 0x21, requestId, 100 + requestId],
        _ => [0x83, 0x18, 0x21, requestId, 0x18, 100 + requestId],
      });
    } else if (action == 'malformed') {
      socket.add(switch(socket.protocol) {
        'wamp.2.json' => '[999]',
        'wamp.2.msgpack' => [0x91, 0xcd, 0x03, 0xe7],
        _ => [0x81, 0x19, 0x03, 0xe7],
      });
    }
    channel.sink.add({'reply': command['id']});
  }
  await channel.sink.close();
}
''';

class _Endpoint {
  _Endpoint(this.channel) {
    subscription = channel.stream.listen(
      (event) {
        if (event is num) {
          port.complete(event.toInt());
        } else {
          events.add(event as Map);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        failed = true;
        if (!port.isCompleted) {
          port.completeError(error, stackTrace);
        } else {
          events.addError(error, stackTrace);
        }
      },
    );
  }
  final StreamChannel<dynamic> channel;
  final port = Completer<int>();
  final events = StreamController<Map>.broadcast();
  late final StreamSubscription<dynamic> subscription;
  var sequence = 0;
  var failed = false;

  Future<void> command(String action, {int? code}) async {
    final id = sequence++;
    final reply = events.stream.firstWhere((event) => event['reply'] == id);
    channel.sink.add({
      'id': id,
      'action': action,
      'code': ?code,
    });
    await reply;
  }

  Future<void> close() async {
    if (!failed) await command('shutdown');
    await subscription.cancel();
    await channel.sink.close();
    await events.close();
  }
}

WebSocketTransport _transport(String serializer, String url) =>
    switch (serializer) {
      'json' => WebSocketTransport.withJsonSerializer(url),
      'msgpack' => WebSocketTransport.withMsgpackSerializer(url),
      _ => WebSocketTransport.withCborSerializer(url),
    };

void main() {
  late WebSocketTestObserver observer;
  setUp(() {
    observer = WebSocketTestObserver();
    addTearDown(observer.restore);
  });
  test('receive before opening rejects synchronously', () {
    final transport = WebSocketTransport.withJsonSerializer(
      'ws://127.0.0.1:1/wamp',
    );
    expect(transport.receive, throwsStateError);
    expect(transport.isReady, isFalse);
  });

  test('rejected handshake signals loss without readiness', () async {
    final endpoint = _Endpoint(spawnHybridCode(_serverSource));
    addTearDown(endpoint.close);
    final transport = WebSocketTransport.withJsonSerializer(
      'ws://127.0.0.1:${await endpoint.port.future}/reject',
    );
    addTearDown(transport.close);
    final opening = observer.open(transport, rejected: true);
    var ready = false;
    unawaited(transport.onReady.then((_) => ready = true));
    await opening;
    await expectDeliveredCompletion(transport.onConnectionLost!.future);
    expect(transport.isOpen, isFalse);
    expect(transport.isReady, isFalse);
    expect(ready, isFalse);
    expect(transport.onConnectionLost!.isCompleted, isTrue);
  });

  for (final serializer in ['msgpack', 'cbor']) {
    test(
      '$serializer network frames survive an earlier pending Blob',
      () async {
        final endpoint = _Endpoint(spawnHybridCode(_serverSource));
        addTearDown(endpoint.close);
        final transport = _transport(
          serializer,
          'ws://127.0.0.1:${await endpoint.port.future}/wamp',
        );
        addTearDown(transport.close);
        await observer.open(transport);
        observer.holdNextBinaryFrame();
        final messages = <AbstractMessage?>[];
        final errors = <Object>[];
        final subscription = transport.receive().listen(
          messages.add,
          onError: errors.add,
        );
        addTearDown(subscription.cancel);

        final firstDelivered = observer.nextMessage();
        await endpoint.command('subscribed', code: 1);
        await firstDelivered;
        await expectDeliveredCompletion(observer.decodeStarted());
        final secondDelivered = observer.nextMessage();
        await endpoint.command('subscribed', code: 2);
        await secondDelivered;
        expect(messages, isEmpty, reason: 'decoding must preserve wire order');
        await observer.releaseDecode();
        for (var turn = 0; turn < 3; turn++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(errors, isEmpty);
        expect(messages, hasLength(2));
        expect(messages, everyElement(isA<Subscribed>()));
        expect(
          messages.cast<Subscribed>().map(
            (message) => message.subscribeRequestId,
          ),
          [1, 2],
        );
        expect(
          messages.cast<Subscribed>().map((message) => message.subscriptionId),
          [101, 102],
        );
        expect(transport.isReady, isTrue);
        expect(transport.onConnectionLost!.isCompleted, isFalse);
        expect(transport.onDisconnect!.isCompleted, isFalse);
      },
    );
  }

  for (final serializer in ['json', 'msgpack', 'cbor']) {
    for (final mode in [
      'normal',
      'abnormal',
      'sent-goodbye',
      'received-goodbye',
    ]) {
      test('$serializer $mode close classification', () async {
        final endpoint = _Endpoint(spawnHybridCode(_serverSource));
        addTearDown(endpoint.close);
        final transport = _transport(
          serializer,
          'ws://127.0.0.1:${await endpoint.port.future}/wamp',
        );
        addTearDown(transport.close);
        await observer.open(
          transport,
          pingInterval: const Duration(seconds: 1),
        );
        expect(transport.isOpen, isTrue);
        expect(transport.isReady, isTrue);
        final messages = StreamController<AbstractMessage?>.broadcast();
        final subscription = transport.receive().listen(messages.add);
        addTearDown(() async {
          await subscription.cancel();
          await messages.close();
        });
        if (mode == 'sent-goodbye') {
          final received = endpoint.events.stream.firstWhere(
            (e) => e['event'] == 'received',
          );
          transport.send(Goodbye(null, Goodbye.reasonNormal));
          expect(await received, {
            'event': 'received',
            'code': 6,
            'reason': 'wamp.close.normal',
          });
        } else if (mode == 'received-goodbye') {
          final received = messages.stream.first;
          await endpoint.command('goodbye');
          expect(
            await received,
            isA<Goodbye>().having(
              (m) => m.reason,
              'reason',
              Goodbye.reasonNormal,
            ),
          );
        }
        final classification = Future.any([
          transport.onConnectionLost!.future.then((_) => 'lost'),
          transport.onDisconnect!.future.then((_) => 'disconnect'),
        ]);
        await endpoint.command('close', code: mode == 'normal' ? 1000 : 1001);
        await observer.closed();
        expect(
          await expectDeliveredCompletion(classification),
          mode == 'abnormal' ? 'lost' : 'disconnect',
        );
        expect(transport.onConnectionLost!.isCompleted, mode == 'abnormal');
        expect(transport.onDisconnect!.isCompleted, mode != 'abnormal');
        expect(transport.isOpen, isFalse);
        expect(transport.isReady, isFalse);
      });
    }

    test('$serializer malformed frame closes and signals error', () async {
      final endpoint = _Endpoint(spawnHybridCode(_serverSource));
      addTearDown(endpoint.close);
      final transport = _transport(
        serializer,
        'ws://127.0.0.1:${await endpoint.port.future}/wamp',
      );
      addTearDown(transport.close);
      await observer.open(transport);
      final received = transport.receive().first;
      await endpoint.command('malformed');
      expect(await received, isNull);
      final error = await transport.onConnectionLost!.future;
      expect(
        error,
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Could not deserialize inbound WebSocket WAMP message'),
        ),
      );
      expect(transport.onDisconnect!.isCompleted, isTrue);
      expect(transport.isOpen, isFalse);
      await transport.close();
      expect(await transport.onConnectionLost!.future, same(error));
    });
  }
}

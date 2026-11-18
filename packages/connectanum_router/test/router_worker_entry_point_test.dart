@TestOn('vm')
library;

import 'dart:isolate';

import 'package:async/async.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

import 'support/native_lib.dart';

void main() {
  final libraryPath = resolveOrBuildNativeLib();

  test('worker reports invalid native handles and remains available', () async {
    final boss = ReceivePort();
    final events = StreamQueue<Object?>(boss);
    SendPort? commands;
    var stopped = false;

    Future<Map> nextEvent(int type) async {
      while (await events.hasNext) {
        final event = await events.next;
        if (event is Map && event['type'] == type) return event;
      }
      throw StateError('Worker event stream ended before event $type');
    }

    addTearDown(() async {
      try {
        if (!stopped && commands != null) {
          commands.send([2]);
          await nextEvent(4);
        }
      } finally {
        await events.cancel();
        boss.close();
      }
    });

    defaultRouterWorkerEntryPoint({
      'bossPort': boss.sendPort,
      'connectionId': 91,
      'listenerId': 1,
      'libraryPath': libraryPath,
      'metadata': {
        'protocol': 'websocket',
        'websocketProtocol': 'wamp.2.json',
        'websocketSerializer': 'json',
      },
    });
    commands = (await nextEvent(1))['commandPort'] as SendPort;
    expect((await nextEvent(2))['connectionId'], 91);

    // RouterBoss wire commands: process, add/remove connection, shutdown.
    commands.send([1, 91, -1]);
    final error = await nextEvent(3);
    expect(error['connectionId'], 91);
    expect(
      error['error'],
      isA<String>().having(
        (value) => value.toLowerCase(),
        'context',
        contains('message'),
      ),
    );
    expect(
      error['stackTrace'],
      isA<String>().having((value) => value.isNotEmpty, 'stack trace', isTrue),
    );
    expect((await nextEvent(2))['connectionId'], 91);

    commands.send([
      3,
      1,
      92,
      {
        'protocol': 'websocket',
        'websocketProtocol': 'wamp.2.msgpack',
        'websocketSerializer': 'msgpack',
      },
    ]);
    final added = await nextEvent(5);
    expect(added['connectionId'], 92);
    expect(added['protocol'], 'websocket');
    expect(added['websocketProtocol'], 'wamp.2.msgpack');
    expect(added['websocketSerializer'], 'msgpack');
    commands.send([4, 92]);
    expect((await nextEvent(6))['connectionId'], 92);
    commands.send([2]);
    expect((await nextEvent(4))['connectionId'], 91);
    stopped = true;
  }, skip: libraryPath == null ? 'Native ct_ffi library not found' : false);
}

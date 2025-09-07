@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:connectanum/src/client.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_io.dart';
import 'package:test/test.dart';

void main() {
  group('Client onOnlineState (VM)', () {
    test('emits periodically while waiting and flips to true when network appears', () async {
      // Prepare a probe port that starts as offline
      final temp = await ServerSocket.bind('127.0.0.1', 0);
      final probePort = temp.port;
      await temp.close();

      // Use an unreachable transport URL to force reconnect
      final transport = WebSocketTransport.withJsonSerializer('ws://127.0.0.1:1/wamp');
      final client = Client(realm: 'com.connectanum', transport: transport);

      final options = ClientConnectOptions(
        reconnectTime: const Duration(milliseconds: 300),
        reconnectCount: 2,
        waitForNetwork: true,
        networkCheckInterval: const Duration(milliseconds: 50),
        networkWaitTimeout: const Duration(seconds: 3),
        connectivityTestAddress: '127.0.0.1:$probePort',
      );

      final emissions = <bool>[];
      final sub = client.onOnlineState.listen(emissions.add);

      // Start connecting; should fail and enter reconnect waiting, starting the ticker
      final completer = Completer<void>();
      client.connect(options: options).listen((_) {}, onError: (_) {
        // We expect eventual failure after retries, but we only care about the stream
        completer.complete();
      });

      // Wait for a few offline emissions
      final sw = Stopwatch()..start();
      while (emissions.length < 2 && sw.elapsedMilliseconds < 1000) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      expect(emissions, isNotEmpty, reason: 'Should emit at least once while waiting');
      expect(emissions.last, isFalse, reason: 'Expected offline initially');

      // Bring the probe online; online should be detected on next ticker tick
      final server = await HttpServer.bind('127.0.0.1', probePort);

      // Await a true emission within a reasonable time
      bool sawTrue = false;
      final trueWaitSw = Stopwatch()..start();
      while (!sawTrue && trueWaitSw.elapsedMilliseconds < 2000) {
        await Future.delayed(const Duration(milliseconds: 25));
        if (emissions.contains(true)) {
          sawTrue = true;
        }
      }
      expect(sawTrue, isTrue, reason: 'Expected to see true after server appears');

      await server.close(force: true);
      await sub.cancel();
      await client.disconnect();
    });

    test('emits multiple times while offline (periodic refresh)', () async {
      // Prepare an unused port for probe (offline)
      final temp = await ServerSocket.bind('127.0.0.1', 0);
      final probePort = temp.port;
      await temp.close();

      final transport = WebSocketTransport.withJsonSerializer('ws://127.0.0.1:1/wamp');
      final client = Client(realm: 'com.connectanum', transport: transport);

      final options = ClientConnectOptions(
        reconnectTime: const Duration(milliseconds: 400),
        reconnectCount: 1,
        waitForNetwork: true,
        networkCheckInterval: const Duration(milliseconds: 50),
        networkWaitTimeout: const Duration(milliseconds: 500),
        connectivityTestAddress: '127.0.0.1:$probePort',
      );

      var count = 0;
      final sub = client.onOnlineState.listen((_) => count++);

      final done = Completer<void>();
      client.connect(options: options).listen((_) {}, onError: (_) => done.complete());

      // Wait for timeout/retry cycle to finish
      await done.future.timeout(const Duration(seconds: 3), onTimeout: () {});

      // With 50ms interval over ~500-800ms waiting windows, expect multiple emissions
      expect(count, greaterThanOrEqualTo(2));

      await sub.cancel();
      await client.disconnect();
    });
  });
}

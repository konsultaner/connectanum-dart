@TestOn('chrome')
library;

import 'dart:async';

import 'package:connectanum/src/client.dart' as connectanum_client;
import 'package:connectanum/src/transport/websocket/websocket_transport_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

void main() {
  group('Client onOnlineState (Web)', () {
    test('emits and reacts to online/offline events during waiting', () async {
      // Use an unreachable URL to force reconnect/waiting
      final transport =
          WebSocketTransport.withJsonSerializer('ws://127.0.0.1:1/wamp');
      final client = connectanum_client.Client(realm: 'com.connectanum', transport: transport);

      final options = connectanum_client.ClientConnectOptions(
        reconnectTime: const Duration(milliseconds: 500),
        reconnectCount: 1,
        waitForNetwork: true,
        networkCheckInterval: const Duration(milliseconds: 100),
      );

      final emissions = <bool>[];
      final sub = client.onOnlineState.listen(emissions.add);

      final done = Completer<void>();
      client
          .connect(options: options)
          .listen((_) {}, onError: (_) => done.complete());

      // Wait until the ticker starts and at least one emission arrives
      final startSw = Stopwatch()..start();
      while (emissions.isEmpty && startSw.elapsedMilliseconds < 3000) {
        await Future.delayed(const Duration(milliseconds: 25));
      }
      expect(emissions, isNotEmpty, reason: 'Should emit while waiting');

      // Simulate going offline -> expect a false emission
      window.dispatchEvent(Event('offline'));
      bool sawFalse = false;
      final offlineSw = Stopwatch()..start();
      while (!sawFalse && offlineSw.elapsedMilliseconds < 2000) {
        await Future.delayed(const Duration(milliseconds: 25));
        if (emissions.contains(false)) sawFalse = true;
      }
      expect(sawFalse, isTrue, reason: 'Expected false after offline event');

      // Simulate going back online -> expect a true emission
      window.dispatchEvent(Event('online'));
      bool sawTrue = false;
      final onlineSw = Stopwatch()..start();
      while (!sawTrue && onlineSw.elapsedMilliseconds < 2000) {
        await Future.delayed(const Duration(milliseconds: 25));
        if (emissions.contains(true) && emissions.last == true) {
          sawTrue = true;
        }
      }
      expect(sawTrue, isTrue, reason: 'Expected true after online event');

      await sub.cancel();
      await client.disconnect();
      await done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    });
  });
}


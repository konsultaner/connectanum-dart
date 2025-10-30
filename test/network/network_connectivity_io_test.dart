@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:connectanum/src/network/network_connectivity_io.dart';

void main() {
  group('NetworkConnectivity IO', () {
    test('isOnline returns true when local server is available, false otherwise', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final port = server.port;

      final online = await NetworkConnectivity.instance
          .isOnline(testAddress: '127.0.0.1:$port');
      expect(online, isTrue);

      await server.close(force: true);

      final offline = await NetworkConnectivity.instance
          .isOnline(testAddress: '127.0.0.1:$port');
      expect(offline, isFalse);
    });

    test('waitUntilOnline completes once server becomes available', () async {
      // Find a free port by binding and immediately releasing it.
      final temp = await ServerSocket.bind('127.0.0.1', 0);
      final port = temp.port;
      await temp.close();

      final sw = Stopwatch()..start();

      final wait = NetworkConnectivity.instance.waitUntilOnline(
        pollInterval: const Duration(milliseconds: 50),
        timeout: const Duration(seconds: 2),
        testAddress: '127.0.0.1:$port',
      );

      // Bring server online after a short delay
      await Future.delayed(const Duration(milliseconds: 200));
      final server = await HttpServer.bind('127.0.0.1', port);

      await wait;
      sw.stop();

      // It should have waited at least ~150ms before becoming online
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(150));
      // And should have completed well before timeout (2s)
      expect(sw.elapsedMilliseconds, lessThan(2000));

      await server.close(force: true);
    });

    test('waitUntilOnline completes after timeout if server never appears', () async {
      // Use an unused port that we do not bind to during the test
      final temp = await ServerSocket.bind('127.0.0.1', 0);
      final port = temp.port;
      await temp.close();

      final sw = Stopwatch()..start();
      await NetworkConnectivity.instance.waitUntilOnline(
        pollInterval: const Duration(milliseconds: 50),
        timeout: const Duration(milliseconds: 300),
        testAddress: '127.0.0.1:$port',
      );
      sw.stop();

      // Should not resolve immediately
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(250));
      // And should not exceed a generous 2s upper bound
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });
}

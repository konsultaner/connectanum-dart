@TestOn('chrome')
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:connectanum/src/network/network_connectivity_web.dart';
import 'package:web/web.dart';

void main() {
  group('NetworkConnectivity Web', () {
    test('isOnline returns a boolean', () async {
      final online = await NetworkConnectivity.instance.isOnline();
      expect(online, anyOf(isTrue, isFalse));
    });

    test('waitUntilOnline completes within timeout', () async {
      final sw = Stopwatch()..start();
      await NetworkConnectivity.instance.waitUntilOnline(
        pollInterval: const Duration(milliseconds: 50),
        timeout: const Duration(seconds: 2),
      );
      sw.stop();
      // Should complete within the given timeout window (allowing some jitter)
      expect(sw.elapsedMilliseconds, lessThan(2500));
    });

    test('waitUntilOnline completes on online event dispatch', () async {
      // Simulate an online event to ensure the event-path resolves promptly
      final wait = NetworkConnectivity.instance.waitUntilOnline(
        pollInterval: const Duration(milliseconds: 50),
        timeout: const Duration(seconds: 2),
      );

      // Fire an online event shortly after starting to wait
      Timer(const Duration(milliseconds: 50), () {
        window.dispatchEvent(Event('online'));
      });

      final sw = Stopwatch()..start();
      await wait;
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(1000));
    });
  });
}

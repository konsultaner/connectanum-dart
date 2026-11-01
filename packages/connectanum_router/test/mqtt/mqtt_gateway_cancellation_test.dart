import 'dart:async';

import 'package:connectanum_router/mqtt.dart';
import 'package:test/test.dart';

void main() {
  test(
    'completed operations remove every connection-lifetime listener',
    () async {
      final lifetime = MqttGatewayCancellation();
      final peer = MqttGatewayCancellation();
      for (var i = 0; i < 1000; i++) {
        expect(await lifetime.waitFor(Future.value(i), other: peer), i);
        expect(lifetime.listenerCount, 0);
        expect(peer.listenerCount, 0);
      }
      expect(lifetime.isCancelled, isFalse);
      lifetime.cancel();
      lifetime.cancel();
      expect(lifetime.isCancelled, isTrue);
    },
  );

  for (final cancelPeer in [false, true]) {
    test(
      'cancellation removes listeners on both lifetimes, peer=$cancelPeer',
      () async {
        final lifetime = MqttGatewayCancellation();
        final peer = MqttGatewayCancellation();
        final work = Completer<int>();
        final done = expectLater(
          lifetime.waitFor(work.future, other: peer),
          throwsStateError,
        );
        expect(lifetime.listenerCount, 1);
        (cancelPeer ? peer : lifetime).cancel();
        await done;
        expect(lifetime.listenerCount, 0);
        expect(peer.listenerCount, 0);
        work.completeError(StateError('late failure is observed'));
      },
    );
  }

  test('already canceled lifetimes still observe late work failures', () async {
    final lifetime = MqttGatewayCancellation()..cancel();
    await expectLater(
      lifetime.waitFor(Future<int>.error(StateError('work'))),
      throwsStateError,
    );
    expect(lifetime.listenerCount, 0);
  });

  test('timeouts release listeners, and late completion is harmless', () async {
    final lifetime = MqttGatewayCancellation();
    final peer = MqttGatewayCancellation();
    final work = Completer<int>();
    await expectLater(
      lifetime.waitFor(
        work.future,
        other: peer,
        timeout: const Duration(milliseconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(lifetime.listenerCount, 0);
    expect(peer.listenerCount, 0);
    work.complete(1);
  });

  test(
    'work errors retain their identity and release the deadline timer',
    () async {
      final lifetime = MqttGatewayCancellation();
      final error = ArgumentError('expected');
      await expectLater(
        lifetime.waitFor(
          Future<int>.error(error),
          timeout: const Duration(seconds: 1),
        ),
        throwsA(same(error)),
      );
      expect(lifetime.listenerCount, 0);
    },
  );
}

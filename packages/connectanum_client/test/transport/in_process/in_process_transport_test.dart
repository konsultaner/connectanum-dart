import 'dart:async';

import 'package:connectanum_client/connectanum.dart';
import 'package:test/test.dart';

void main() {
  group('InProcessTransportPair', () {
    test('delivers WAMP message objects between paired endpoints', () async {
      final pair = InProcessTransportPair();
      addTearDown(pair.client.close);
      addTearDown(pair.server.close);

      await pair.client.open();
      await pair.server.open();

      final received = <AbstractMessage?>[];
      final subscription = pair.server.receive().listen(received.add);
      addTearDown(subscription.cancel);

      final hello = Hello('realm1', Details.forHello());
      pair.client.send(hello);

      await _pumpEventQueue();

      expect(received, [same(hello)]);
    });

    test('keeps queued messages until a receive listener attaches', () async {
      final pair = InProcessTransportPair();
      addTearDown(pair.client.close);
      addTearDown(pair.server.close);

      await pair.client.open();
      await pair.server.open();

      final hello = Hello('realm1', Details.forHello());
      pair.client.send(hello);

      await _pumpEventQueue();
      expect(pair.server.pendingIncomingCount, 1);

      final received = <AbstractMessage?>[];
      final subscription = pair.server.receive().listen(received.add);
      addTearDown(subscription.cancel);

      await _pumpEventQueue();

      expect(pair.server.pendingIncomingCount, 0);
      expect(received, [same(hello)]);
    });

    test('throws instead of growing the peer queue without bound', () async {
      final pair = InProcessTransportPair(queueCapacity: 1);
      addTearDown(pair.client.close);
      addTearDown(pair.server.close);

      await pair.client.open();
      await pair.server.open();

      final received = <AbstractMessage?>[];
      final subscription = pair.server.receive().listen(received.add);
      addTearDown(subscription.cancel);

      final first = Hello('realm1', Details.forHello());
      final second = Hello('realm1', Details.forHello());
      pair.client.send(first);

      expect(
        () => pair.client.send(second),
        throwsA(
          isA<InProcessTransportBackpressureException>()
              .having((error) => error.source, 'source', 'client')
              .having((error) => error.target, 'target', 'server')
              .having((error) => error.capacity, 'capacity', 1)
              .having((error) => error.message, 'message', same(second)),
        ),
      );

      await _pumpEventQueue();
      expect(received, [same(first)]);

      pair.client.send(second);
      await _pumpEventQueue();
      expect(received, [same(first), same(second)]);
    });

    test('can back a normal client session handshake', () async {
      final pair = InProcessTransportPair();
      addTearDown(pair.server.close);

      await pair.server.open();
      final serverSubscription = pair.server.receive().listen((message) {
        if (message is Hello) {
          pair.server.send(
            Welcome(
              42,
              Details.forWelcome(
                realm: message.realm,
                authId: message.details.authid,
                authRole: message.details.authrole ?? 'client',
                authMethod: 'anonymous',
                authProvider: 'in-process',
              ),
            ),
          );
        }
      });
      addTearDown(serverSubscription.cancel);

      final client = Client(
        realm: 'realm1',
        authId: 'embedded-client',
        authRole: 'internal',
        transport: pair.client,
      );
      addTearDown(client.disconnect);

      final session = await client
          .connect(options: ClientConnectOptions(reconnectCount: 0))
          .first
          .timeout(const Duration(seconds: 2));

      expect(session.id, 42);
      expect(session.realm, 'realm1');
      expect(session.authId, 'embedded-client');
      expect(session.authRole, 'internal');
      expect(session.authMethod, 'anonymous');
      expect(session.authProvider, 'in-process');
    });

    test('closing one endpoint closes its peer connection', () async {
      final pair = InProcessTransportPair();
      await pair.client.open();
      await pair.server.open();

      await pair.server.close();

      await expectLater(pair.client.onConnectionLost.future, completes);
      expect(pair.client.isOpen, isFalse);
      expect(
        () => pair.client.send(Hello('realm1', Details.forHello())),
        throwsStateError,
      );
    });
  });
}

Future<void> _pumpEventQueue() => Future<void>.delayed(Duration.zero);

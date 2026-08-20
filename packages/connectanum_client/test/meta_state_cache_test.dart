import 'dart:async';

import 'package:connectanum_client/connectanum.dart';
import 'package:test/test.dart';

void main() {
  group('WampMetaStateCache', () {
    test(
      'replays lifecycle events received synchronously during hydration',
      () async {
        final transport = _MetaTransport();
        final session = await _startSession(transport);

        final cache = await WampMetaStateCache.start(
          session,
          maxConcurrentQueries: 2,
        );

        expect(cache.snapshot.sessions.keys, containsAll(<int>[1, 2]));
        expect(cache.snapshot.sessions[2]!.authId, 'joined-during-subscribe');
        expect(cache.snapshot.registrations[10]!.procedure, 'example.add');
        expect(cache.snapshot.registrations[10]!.callees, <int>{1, 2});
        expect(cache.snapshot.subscriptions[20]!.topic, 'example.events');
        expect(cache.snapshot.subscriptions[20]!.subscribers, <int>{1, 2});

        expect(
          () => cache.snapshot.sessions[3] = WampSessionMeta.fromDetails(
            3,
            <String, dynamic>{'session': 3},
          ),
          throwsUnsupportedError,
        );
        expect(
          () => cache.snapshot.registrations[10]!.callees.add(3),
          throwsUnsupportedError,
        );
        final transportDetails =
            cache.snapshot.sessions[1]!.details['transport'] as Map;
        expect(
          () => transportDetails['connection_id'] = 99,
          throwsUnsupportedError,
        );

        final changed = cache.changes.first;
        transport.emitMeta('wamp.session.on_leave', <dynamic>[
          1,
          'one',
          'user',
        ]);
        final snapshot = await changed;
        expect(snapshot.sessions, isNot(contains(1)));
        expect(snapshot.registrations[10]!.callees, <int>{2});
        expect(snapshot.subscriptions[20]!.subscribers, <int>{2});

        final changesDone = cache.changes.drain<void>();
        await cache.close();
        await changesDone;
        expect(cache.isClosed, isTrue);
        expect(transport.unsubscribeCount, 10);
        await transport.shutdown();
      },
    );

    test(
      'ignores objects that disappear while snapshots are loading',
      () async {
        final transport = _MetaTransport(vanishSnapshotObjects: true);
        final session = await _startSession(transport);

        final cache = await WampMetaStateCache.start(session);

        expect(cache.snapshot.sessions.keys, <int>[1, 2]);
        expect(cache.snapshot.registrations, isEmpty);
        expect(cache.snapshot.subscriptions, isEmpty);

        await cache.close();
        await transport.shutdown();
      },
    );

    test('rejects disconnected sessions and invalid concurrency', () async {
      final transport = _MetaTransport();
      final disconnected = Session('example.realm', transport);

      await expectLater(
        WampMetaStateCache.start(disconnected),
        throwsStateError,
      );

      final session = await _startSession(transport);
      await expectLater(
        WampMetaStateCache.start(session, maxConcurrentQueries: 0),
        throwsArgumentError,
      );
      await transport.shutdown();
    });

    test(
      'fails without hanging when the session drops during hydration',
      () async {
        final transport = _MetaTransport(disconnectDuringHydration: true);
        final session = await _startSession(transport);

        await expectLater(
          WampMetaStateCache.start(session).timeout(const Duration(seconds: 1)),
          throwsA(anything),
        );
      },
    );
  });
}

Future<Session> _startSession(_MetaTransport transport) async {
  await transport.open();
  return Session.start('example.realm', transport);
}

final class _MetaTransport extends AbstractTransport {
  _MetaTransport({
    this.vanishSnapshotObjects = false,
    this.disconnectDuringHydration = false,
  });

  final bool vanishSnapshotObjects;
  final bool disconnectDuringHydration;
  final StreamController<AbstractMessage> _inbound =
      StreamController<AbstractMessage>.broadcast(sync: true);
  final Map<String, int> _subscriptionIds = <String, int>{};
  Completer<void>? _disconnect;
  Completer<void>? _connectionLost;
  var _nextSubscriptionId = 100;
  var _nextPublicationId = 1;
  var _isOpen = false;
  var _sentInitialJoin = false;
  var _sentRegistrationRace = false;
  var _sentSubscriptionRace = false;
  var unsubscribeCount = 0;

  @override
  Completer<void>? get onDisconnect => _disconnect;

  @override
  Completer<void>? get onConnectionLost => _connectionLost;

  @override
  bool get isOpen => _isOpen;

  @override
  bool get isReady => _isOpen;

  @override
  Future<void> get onReady => Future<void>.value();

  @override
  Future<void> open({Duration? pingInterval}) async {
    _isOpen = true;
    _disconnect = Completer<void>();
    _connectionLost = Completer<void>();
  }

  @override
  Future<void> close({dynamic error}) => shutdown();

  Future<void> shutdown() async {
    if (!_isOpen) {
      return;
    }
    _isOpen = false;
    if (!(_disconnect?.isCompleted ?? true)) {
      _disconnect!.complete();
    }
    await _inbound.close();
  }

  @override
  Stream<AbstractMessage> receive() => _inbound.stream;

  @override
  void send(AbstractMessage message) {
    switch (message) {
      case Hello():
        _inbound.add(
          Welcome(
            900,
            Details.forWelcome(
              realm: 'example.realm',
              authId: 'cache-client',
              authRole: 'admin',
            ),
          ),
        );
      case Subscribe():
        final subscriptionId = _nextSubscriptionId++;
        _subscriptionIds[message.topic] = subscriptionId;
        _inbound.add(Subscribed(message.requestId, subscriptionId));
        if (!_sentInitialJoin && message.topic == 'wamp.session.on_join') {
          _sentInitialJoin = true;
          emitMeta(
            message.topic,
            <dynamic>[
              <String, dynamic>{
                'session': 2,
                'authid': 'joined-during-subscribe',
                'authrole': 'user',
              },
            ],
          );
        }
      case Unsubscribe():
        unsubscribeCount++;
        _inbound.add(Unsubscribed(message.requestId, null));
      case Call():
        _respondToCall(message);
      case Goodbye():
        _inbound.add(
          Goodbye(null, Goodbye.reasonGoodbyeAndOut),
        );
      default:
        throw StateError('Unexpected outbound message ${message.runtimeType}');
    }
  }

  void _respondToCall(Call call) {
    switch (call.procedure) {
      case 'wamp.session.list':
        if (disconnectDuringHydration) {
          unawaited(shutdown());
          return;
        }
        _result(call, <dynamic>[
          <int>[1],
        ]);
      case 'wamp.session.get':
        final id = call.arguments!.single as int;
        _result(call, <dynamic>[
          <String, dynamic>{
            'session': id,
            'authid': 'one',
            'authrole': 'user',
            'transport': <String, dynamic>{'connection_id': 1},
          },
        ]);
      case 'wamp.registration.list':
        _result(call, <dynamic>[
          <String, dynamic>{
            'exact': <int>[10],
            'prefix': <int>[],
            'wildcard': <int>[],
          },
        ]);
      case 'wamp.registration.get':
        if (!_sentRegistrationRace) {
          _sentRegistrationRace = true;
          emitMeta('wamp.registration.on_register', <dynamic>[2, 10]);
        }
        if (vanishSnapshotObjects) {
          _error(call, Error.noSuchRegistration);
        } else {
          _result(call, <dynamic>[
            <String, dynamic>{
              'id': 10,
              'uri': 'example.add',
              'match': 'exact',
              'invoke': 'single',
            },
          ]);
        }
      case 'wamp.registration.list_callees':
        _result(call, <dynamic>[
          <int>[1],
        ]);
      case 'wamp.subscription.list':
        _result(call, <dynamic>[
          <String, dynamic>{
            'exact': <int>[20],
            'prefix': <int>[],
            'wildcard': <int>[],
          },
        ]);
      case 'wamp.subscription.get':
        if (!_sentSubscriptionRace) {
          _sentSubscriptionRace = true;
          emitMeta('wamp.subscription.on_subscribe', <dynamic>[2, 20]);
        }
        if (vanishSnapshotObjects) {
          _error(call, Error.noSuchSubscription);
        } else {
          _result(call, <dynamic>[
            <String, dynamic>{
              'id': 20,
              'uri': 'example.events',
              'match': 'exact',
            },
          ]);
        }
      case 'wamp.subscription.list_subscribers':
        _result(call, <dynamic>[
          <int>[1],
        ]);
      default:
        _error(call, Error.noSuchProcedure);
    }
  }

  void _result(Call call, List<dynamic> arguments) {
    _inbound.add(Result(call.requestId, ResultDetails(), arguments: arguments));
  }

  void _error(Call call, String reason) {
    _inbound.add(
      Error(
        MessageTypes.codeCall,
        call.requestId,
        <String, dynamic>{},
        reason,
      ),
    );
  }

  void emitMeta(String topic, List<dynamic> arguments) {
    final subscriptionId = _subscriptionIds[topic];
    if (subscriptionId == null) {
      return;
    }
    _inbound.add(
      Event(
        subscriptionId,
        _nextPublicationId++,
        EventDetails(topic: topic),
        arguments: arguments,
      ),
    );
  }
}

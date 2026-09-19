import 'dart:async';

import 'package:connectanum_client/connectanum.dart';
import 'package:test/test.dart';

void main() {
  _metaRegressionContracts();
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

        final changed = <WampMetaStateSnapshot>[];
        final listener = cache.changes.listen(changed.add);
        addTearDown(listener.cancel);
        transport.emitMeta('wamp.session.on_leave', <dynamic>[
          1,
          'one',
          'user',
        ]);
        await _drainMetaCallbacks();
        expect(changed, hasLength(1));
        final snapshot = changed.single;
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
          WampMetaStateCache.start(session),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Session transport closed',
            ),
          ),
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
    this.emitHydrationEvents = true,
  });

  final bool emitHydrationEvents;
  bool Function(AbstractMessage)? onSend;
  final sentMessages = <AbstractMessage>[];
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

  Future<void> shutdown({Object? error}) async {
    if (!_isOpen) {
      return;
    }
    _isOpen = false;
    if (!(_disconnect?.isCompleted ?? true)) {
      if (error == null) {
        _disconnect!.complete();
      } else {
        _disconnect!.completeError(error);
      }
    }
    await _inbound.close();
  }

  @override
  Stream<AbstractMessage> receive() => _inbound.stream;

  @override
  void send(AbstractMessage message) {
    sentMessages.add(message);
    if (onSend?.call(message) ?? false) return;
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
        if (emitHydrationEvents &&
            !_sentInitialJoin &&
            message.topic == 'wamp.session.on_join') {
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
        if (emitHydrationEvents && !_sentRegistrationRace) {
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
        if (emitHydrationEvents && !_sentSubscriptionRace) {
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

  void emitMeta(String topic, List<dynamic>? arguments) {
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

Future<(_MetaTransport, WampMetaStateCache)> _cacheFixture([
  _MetaTransport? fixture,
]) async {
  final transport = fixture ?? _MetaTransport(emitHydrationEvents: false);
  addTearDown(transport.shutdown);
  final session = await _startSession(transport);
  final cache = await WampMetaStateCache.start(session);
  addTearDown(cache.close);
  return (transport, cache);
}

Future<void> _drainMetaCallbacks() => Future<void>.delayed(Duration.zero);

void _metaRegressionContracts() {
  for (final entry in {
    'wamp.session.get': Error.noSuchSession,
    'wamp.registration.get': Error.noSuchRegistration,
    'wamp.subscription.get': Error.noSuchSubscription,
  }.entries) {
    test(
      'startup explicitly tolerates concurrent disappearance from ${entry.key}',
      () async {
        final transport = _MetaTransport(emitHydrationEvents: false);
        addTearDown(transport.shutdown);
        transport.onSend = (message) {
          if (message is! Call || message.procedure != entry.key) return false;
          transport._error(message, entry.value);
          return true;
        };
        final session = await _startSession(transport);
        WampMetaStateCache? cache;
        Error? disappearance;
        try {
          cache = await WampMetaStateCache.start(session);
        } on Error catch (error) {
          if (error.error != entry.value) rethrow;
          disappearance = error;
        }
        if (cache != null) addTearDown(cache.close);
        expect(
          disappearance,
          isNull,
          reason:
              'An object removed during hydration is omitted, not a failed cache startup',
        );
        expect(cache, isNotNull);
        if (entry.key == 'wamp.session.get') {
          expect(cache!.snapshot.sessions, isEmpty);
        } else if (entry.key == 'wamp.registration.get') {
          expect(cache!.snapshot.registrations, isEmpty);
        } else {
          expect(cache!.snapshot.subscriptions, isEmpty);
        }
        expect(cache.isClosed, isFalse);
      },
    );
  }

  test(
    'failed disconnect notification closes the cache without dead-session writes',
    () async {
      final (transport, cache) = await _cacheFixture();
      final done = cache.changes.drain<void>();
      await transport.shutdown(
        error: StateError('controlled disconnect failure'),
      );
      await done;
      expect(cache.isClosed, isTrue);
      expect(transport.unsubscribeCount, 0);
      await cache.close();
      expect(transport.unsubscribeCount, 0);
    },
  );

  test(
    'change listeners observe the corresponding current snapshot during bursts',
    () async {
      final (transport, cache) = await _cacheFixture();
      final currentAtDelivery = <bool>[];
      final snapshots = <WampMetaStateSnapshot>[];
      final listener = cache.changes.listen((snapshot) {
        currentAtDelivery.add(identical(cache.snapshot, snapshot));
        snapshots.add(snapshot);
      });
      addTearDown(listener.cancel);
      transport.emitMeta('wamp.session.on_join', [
        {'session': 2},
      ]);
      transport.emitMeta('wamp.session.on_join', [
        {'session': 3},
      ]);
      await _drainMetaCallbacks();
      expect(currentAtDelivery, [true, true]);
      expect(snapshots.map((s) => s.sessions.keys.toList()), [
        [1, 2],
        [1, 2, 3],
      ]);
    },
  );

  for (final registration in [true, false]) {
    final kind = registration ? 'registration' : 'subscription';
    final id = registration ? 10 : 20;
    for (final adding in [true, false]) {
      final action = registration
          ? (adding ? 'register' : 'unregister')
          : (adding ? 'subscribe' : 'unsubscribe');
      test(
        '$kind no-op $action preserves immutable metadata identity',
        () async {
          final (transport, cache) = await _cacheFixture();
          final before = cache.snapshot;
          final events = <WampMetaStateSnapshot>[];
          final listener = cache.changes.listen(events.add);
          addTearDown(listener.cancel);
          transport.emitMeta('wamp.$kind.on_$action', [adding ? 1 : 999, id]);
          await _drainMetaCallbacks();
          expect(events, isEmpty);
          expect(cache.snapshot, same(before));
          transport.emitMeta('wamp.session.on_join', [
            {'session': 2},
          ]);
          await _drainMetaCallbacks();
          expect(events, hasLength(1));
          expect(
            cache.snapshot.registrations[10],
            same(before.registrations[10]),
          );
          expect(
            cache.snapshot.subscriptions[20],
            same(before.subscriptions[20]),
          );
        },
      );
    }
  }

  test(
    'unrelated session departure retains metadata identity and membership',
    () async {
      final (transport, cache) = await _cacheFixture();
      final before = cache.snapshot;
      final events = <WampMetaStateSnapshot>[];
      final listener = cache.changes.listen(events.add);
      addTearDown(listener.cancel);
      transport.emitMeta('wamp.session.on_leave', [999]);
      await _drainMetaCallbacks();
      expect(events, hasLength(1));
      expect(cache.snapshot.registrations[10], same(before.registrations[10]));
      expect(cache.snapshot.subscriptions[20], same(before.subscriptions[20]));
      expect(cache.snapshot.registrations[10]!.callees, {1});
      expect(cache.snapshot.subscriptions[20]!.subscribers, {1});
    },
  );

  group('Meta cache behavioral boundaries', () {
    test(
      'subscription failure releases partial ownership and allows retry',
      () async {
        final transport = _MetaTransport(emitHydrationEvents: false);
        addTearDown(transport.shutdown);
        transport.onSend = (message) {
          if (message is! Subscribe || transport._subscriptionIds.length != 3) {
            return false;
          }
          transport._inbound.add(
            Error(
              MessageTypes.codeSubscribe,
              message.requestId,
              {},
              Error.notAuthorized,
            ),
          );
          return true;
        };
        final session = await _startSession(transport);
        await expectLater(
          WampMetaStateCache.start(session),
          throwsA(
            isA<Error>().having(
              (error) => error.error,
              'reason',
              Error.notAuthorized,
            ),
          ),
        );
        expect(transport.unsubscribeCount, 3);
        expect(
          transport.sentMessages.whereType<Unsubscribe>().map(
            (m) => m.subscriptionId,
          ),
          [102, 101, 100],
        );
        transport.onSend = null;
        final cache = await WampMetaStateCache.start(session);
        addTearDown(cache.close);
        expect(cache.snapshot.sessions.keys, [1]);
        expect(cache.snapshot.registrations.keys, [10]);
        await cache.close();
        expect(transport.unsubscribeCount, 13);
      },
    );

    test(
      'disposal continues when one remote subscription already disappeared',
      () async {
        final (transport, cache) = await _cacheFixture();
        var rejected = false;
        transport.onSend = (message) {
          if (message is! Unsubscribe || rejected) return false;
          rejected = true;
          transport.unsubscribeCount++;
          transport._inbound.add(
            Error(
              MessageTypes.codeUnsubscribe,
              message.requestId,
              {},
              Error.noSuchSubscription,
            ),
          );
          return true;
        };
        final done = cache.changes.drain<void>();
        await cache.close();
        await done;
        expect(rejected, isTrue);
        expect(cache.isClosed, isTrue);
        expect(transport.unsubscribeCount, 10);
        expect(transport.sentMessages.whereType<Unsubscribe>(), hasLength(10));
      },
    );

    test(
      'disconnect after the last reply cannot publish a hydrated cache',
      () async {
        final transport = _MetaTransport(emitHydrationEvents: false);
        addTearDown(transport.shutdown);
        transport.onSend = (message) {
          if (message is! Call ||
              message.procedure != 'wamp.subscription.list_subscribers') {
            return false;
          }
          transport._result(message, [
            <int>[1],
          ]);
          unawaited(transport.shutdown());
          return true;
        };
        final session = await _startSession(transport);
        await expectLater(
          WampMetaStateCache.start(session),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'The WAMP session disconnected during Meta hydration',
            ),
          ),
        );
        expect(transport.isOpen, isFalse);
        expect(transport.unsubscribeCount, 0);
      },
    );

    for (final concurrency in [1, 2, 10]) {
      test(
        'hydration bounds concurrency=$concurrency and preserves out-of-order replies',
        () async {
          final transport = _MetaTransport(emitHydrationEvents: false);
          addTearDown(transport.shutdown);
          final pending = <int, Call>{};
          final requested = <int>[];
          transport.onSend = (message) {
            if (message is! Call) return false;
            if (message.procedure == 'wamp.session.list') {
              transport._result(message, [
                <int>[1, 2, 3, 4, 5],
              ]);
              return true;
            }
            if (message.procedure != 'wamp.session.get') return false;
            final id = message.arguments!.single as int;
            pending[id] = message;
            requested.add(id);
            return true;
          };
          final session = await _startSession(transport);
          final starting = WampMetaStateCache.start(
            session,
            maxConcurrentQueries: concurrency,
          );
          await _drainMetaCallbacks();
          final limit = concurrency < 5 ? concurrency : 5;
          expect(pending.length, limit);
          while (pending.isNotEmpty) {
            final id = pending.keys.last;
            transport._result(pending.remove(id)!, [
              {'session': id, 'authid': 'user-$id'},
            ]);
            await _drainMetaCallbacks();
            expect(pending.length, lessThanOrEqualTo(limit));
          }
          final cache = await starting;
          addTearDown(cache.close);
          expect(requested, [1, 2, 3, 4, 5]);
          expect(cache.snapshot.sessions.keys, [1, 2, 3, 4, 5]);
          expect(cache.snapshot.sessions.values.map((value) => value.authId), [
            'user-1',
            'user-2',
            'user-3',
            'user-4',
            'user-5',
          ]);
        },
      );
    }

    for (final registration in [true, false]) {
      final kind = registration ? 'registration' : 'subscription';
      final add = registration ? 'register' : 'subscribe';
      final remove = registration ? 'unregister' : 'unsubscribe';
      test(
        '$kind lifecycle retains old snapshots and deduplicates membership',
        () async {
          final (transport, cache) = await _cacheFixture();
          final before = cache.snapshot;
          final observed = <WampMetaStateSnapshot>[];
          final listener = cache.changes.listen(observed.add);
          addTearDown(listener.cancel);
          Set<int> members(WampMetaStateSnapshot state) => registration
              ? state.registrations[77]!.callees
              : state.subscriptions[77]!.subscribers;
          bool contains(WampMetaStateSnapshot state) => registration
              ? state.registrations.containsKey(77)
              : state.subscriptions.containsKey(77);
          transport.emitMeta('wamp.$kind.on_create', [
            1,
            {'id': 77, 'uri': 'app.item', 'match': 'prefix'},
          ]);
          await _drainMetaCallbacks();
          expect(observed, hasLength(1));
          expect(contains(before), isFalse);
          expect(members(cache.snapshot), isEmpty);
          final created = cache.snapshot;
          transport.emitMeta('wamp.$kind.on_$add', [2, 77]);
          transport.emitMeta('wamp.$kind.on_$add', [2, 77]);
          await _drainMetaCallbacks();
          expect(observed, hasLength(2));
          expect(members(created), isEmpty);
          expect(members(cache.snapshot), {2});
          final populated = cache.snapshot;
          transport.emitMeta('wamp.$kind.on_$remove', [2, 77]);
          transport.emitMeta('wamp.$kind.on_$remove', [2, 77]);
          await _drainMetaCallbacks();
          expect(observed, hasLength(3));
          expect(members(populated), {2});
          expect(members(cache.snapshot), isEmpty);
          expect(contains(cache.snapshot), isTrue);
          transport.emitMeta('wamp.$kind.on_delete', [1, 77]);
          await _drainMetaCallbacks();
          expect(observed, hasLength(4));
          expect(contains(cache.snapshot), isFalse);
          final deleted = cache.snapshot;
          transport.emitMeta('wamp.$kind.on_delete', [1, 77]);
          await _drainMetaCallbacks();
          expect(observed, hasLength(4));
          expect(contains(cache.snapshot), isFalse);
          expect(contains(created), isTrue);
          expect(cache.snapshot, same(deleted));
        },
      );
    }

    final malformed = <(String, List<dynamic>?)>[
      ('wamp.session.on_join', null),
      ('wamp.session.on_join', []),
      ('wamp.session.on_join', [true]),
      (
        'wamp.session.on_join',
        [
          <Object?, Object?>{1: 'not a string key'},
        ],
      ),
      ('wamp.session.on_join', [{}]),
      (
        'wamp.session.on_join',
        [
          {'session': '1'},
        ],
      ),
      (
        'wamp.session.on_join',
        [
          {'session': 1.5},
        ],
      ),
      ('wamp.session.on_leave', []),
      ('wamp.session.on_leave', ['1']),
      for (final kind in ['registration', 'subscription']) ...[
        ('wamp.$kind.on_create', [1]),
        ('wamp.$kind.on_create', [1, true]),
        ('wamp.$kind.on_create', [1, {}]),
        (
          'wamp.$kind.on_create',
          [
            1,
            {'id': '77'},
          ],
        ),
        ('wamp.$kind.on_delete', []),
        ('wamp.$kind.on_delete', [1, '77']),
      ],
      for (final action in ['register', 'unregister']) ...[
        ('wamp.registration.on_$action', []),
        ('wamp.registration.on_$action', ['2', 10]),
        ('wamp.registration.on_$action', [2, '10']),
        ('wamp.registration.on_$action', [2, 999]),
      ],
      for (final action in ['subscribe', 'unsubscribe']) ...[
        ('wamp.subscription.on_$action', []),
        ('wamp.subscription.on_$action', ['2', 20]),
        ('wamp.subscription.on_$action', [2, '20']),
        ('wamp.subscription.on_$action', [2, 999]),
      ],
    ];
    for (var index = 0; index < malformed.length; index++) {
      final (topic, arguments) = malformed[index];
      test(
        'ignores malformed or unknown-target event $index: $topic',
        () async {
          final (transport, cache) = await _cacheFixture();
          final observed = <WampMetaStateSnapshot>[];
          final listener = cache.changes.listen(observed.add);
          addTearDown(listener.cancel);
          transport.emitMeta(topic, arguments);
          await _drainMetaCallbacks();
          expect(observed, isEmpty);
          expect(cache.snapshot.sessions.keys, [1]);
          expect(cache.snapshot.registrations[10]!.callees, {1});
          expect(cache.snapshot.subscriptions[20]!.subscribers, {1});
          transport.emitMeta('wamp.session.on_join', [
            {'id': 2, 'authid': 'new-user'},
          ]);
          await _drainMetaCallbacks();
          expect(observed, hasLength(1));
          expect(cache.snapshot.sessions[2]!.authId, 'new-user');
        },
      );
    }

    test(
      'disposal ignores queued events and releases ownership only once',
      () async {
        final (transport, cache) = await _cacheFixture();
        final observed = <WampMetaStateSnapshot>[];
        final done = Completer<void>();
        cache.changes.listen(observed.add, onDone: done.complete);
        final closing = cache.close();
        transport.emitMeta('wamp.session.on_join', [
          {'session': 8},
        ]);
        await closing;
        await done.future;
        await cache.close();
        expect(observed, isEmpty);
        expect(cache.snapshot.sessions.keys, [1]);
        expect(cache.isClosed, isTrue);
        expect(transport.unsubscribeCount, 10);
        expect(
          transport.sentMessages.whereType<Unsubscribe>().map(
            (m) => m.subscriptionId,
          ),
          transport._subscriptionIds.values.toList().reversed,
        );
      },
    );

    test(
      'disconnect closes changes without sending unsubscribe on a dead session',
      () async {
        final (transport, cache) = await _cacheFixture();
        final done = cache.changes.drain<void>();
        await transport.shutdown();
        await done;
        expect(cache.isClosed, isTrue);
        expect(transport.unsubscribeCount, 0);
        await cache.close();
        expect(transport.unsubscribeCount, 0);
      },
    );

    for (final procedure in [
      'wamp.session.list',
      'wamp.registration.list',
      'wamp.subscription.list',
      'wamp.session.get',
      'wamp.registration.get',
      'wamp.registration.list_callees',
      'wamp.subscription.get',
      'wamp.subscription.list_subscribers',
    ]) {
      test(
        'preserves authorization failure from $procedure and cleans subscriptions',
        () async {
          final transport = _MetaTransport(emitHydrationEvents: false);
          addTearDown(transport.shutdown);
          late Error rejection;
          transport.onSend = (message) {
            if (message is! Call || message.procedure != procedure) {
              return false;
            }
            rejection = Error(
              MessageTypes.codeCall,
              message.requestId,
              {},
              Error.notAuthorized,
            );
            transport._inbound.add(rejection);
            return true;
          };
          final session = await _startSession(transport);
          await expectLater(
            WampMetaStateCache.start(session),
            throwsA(
              predicate<Object>(
                (error) => identical(error, rejection),
                'the original authorization error',
              ),
            ),
          );
          expect(transport.unsubscribeCount, 10);
          expect(
            transport.sentMessages.whereType<Unsubscribe>(),
            hasLength(10),
          );
          expect(session.isConnected(), isTrue);
        },
      );
    }

    test(
      'disappearing session is omitted rather than failing hydration',
      () async {
        final transport = _MetaTransport(emitHydrationEvents: false);
        transport.onSend = (message) {
          if (message is! Call || message.procedure != 'wamp.session.get') {
            return false;
          }
          transport._error(message, Error.noSuchSession);
          return true;
        };
        final (_, cache) = await _cacheFixture(transport);
        expect(cache.snapshot.sessions, isEmpty);
        expect(cache.snapshot.registrations.keys, [10]);
        expect(cache.snapshot.subscriptions.keys, [20]);
      },
    );

    test(
      'empty initial catalogs produce an empty immutable snapshot',
      () async {
        final transport = _MetaTransport(emitHydrationEvents: false);
        transport.onSend = (message) {
          if (message is! Call) return false;
          if (message.procedure == 'wamp.session.list') {
            transport._result(message, [<int>[]]);
          } else if (message.procedure == 'wamp.registration.list' ||
              message.procedure == 'wamp.subscription.list') {
            transport._result(message, [
              {'exact': <int>[], 'prefix': <int>[], 'wildcard': <int>[]},
            ]);
          } else {
            return false;
          }
          return true;
        };
        final (_, cache) = await _cacheFixture(transport);
        expect(cache.snapshot.sessions, isEmpty);
        expect(cache.snapshot.registrations, isEmpty);
        expect(cache.snapshot.subscriptions, isEmpty);
        expect(
          transport.sentMessages.whereType<Call>().map((m) => m.procedure),
          [
            'wamp.session.list',
            'wamp.registration.list',
            'wamp.subscription.list',
          ],
        );
        expect(() => cache.snapshot.sessions.clear(), throwsUnsupportedError);
        expect(
          () => cache.snapshot.registrations.clear(),
          throwsUnsupportedError,
        );
        expect(
          () => cache.snapshot.subscriptions.clear(),
          throwsUnsupportedError,
        );
      },
    );

    final invalidResults = <(String, Object?)>[
      ('wamp.session.list', {}),
      ('wamp.session.list', [1, '2']),
      ('wamp.session.get', []),
      ('wamp.session.get', null),
      ('wamp.session.get', <Object?, Object?>{1: 'invalid key'}),
      for (final kind in ['registration', 'subscription']) ...[
        ('wamp.$kind.list', {'exact': [], 'prefix': []}),
        ('wamp.$kind.list', {'exact': true, 'prefix': [], 'wildcard': []}),
        (
          'wamp.$kind.list',
          {
            'exact': [1],
            'prefix': ['2'],
            'wildcard': [],
          },
        ),
        ('wamp.$kind.get', true),
      ],
      ('wamp.registration.list_callees', [1, true]),
      ('wamp.subscription.list_subscribers', {}),
    ];
    for (var index = 0; index < invalidResults.length; index++) {
      final (procedure, value) = invalidResults[index];
      test(
        'rejects malformed hydration result $index from $procedure',
        () async {
          final transport = _MetaTransport(emitHydrationEvents: false);
          addTearDown(transport.shutdown);
          transport.onSend = (message) {
            if (message is! Call || message.procedure != procedure) {
              return false;
            }
            transport._result(message, [value]);
            return true;
          };
          final session = await _startSession(transport);
          await expectLater(
            WampMetaStateCache.start(session),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'procedure diagnostic',
                contains(procedure),
              ),
            ),
          );
          expect(transport.unsubscribeCount, 10);
        },
      );
    }

    for (final arguments in <List<dynamic>?>[null, []]) {
      for (final keywords in <Map<String, dynamic>?>[null, {}]) {
        test(
          'rejects missing result value args=$arguments kwargs=$keywords',
          () async {
            final transport = _MetaTransport(emitHydrationEvents: false);
            addTearDown(transport.shutdown);
            transport.onSend = (message) {
              if (message is! Call ||
                  message.procedure != 'wamp.session.list') {
                return false;
              }
              transport._inbound.add(
                Result(
                  message.requestId,
                  ResultDetails(),
                  arguments: arguments,
                  argumentsKeywords: keywords,
                ),
              );
              return true;
            };
            final session = await _startSession(transport);
            await expectLater(
              WampMetaStateCache.start(session),
              throwsA(
                isA<FormatException>().having(
                  (error) => error.message,
                  'message',
                  'wamp.session.list returned no result value',
                ),
              ),
            );
            expect(transport.unsubscribeCount, 10);
          },
        );
      }
    }

    test(
      'accepts keyword-map metadata and preserves all convenience properties',
      () async {
        final transport = _MetaTransport(emitHydrationEvents: false);
        transport.onSend = (message) {
          if (message is! Call || !message.procedure.endsWith('.get')) {
            return false;
          }
          final values = switch (message.procedure) {
            'wamp.session.get' => <String, dynamic>{
              'session': 1,
              'authid': 'alice',
              'authrole': 'reader',
              'authmethod': 'ticket',
              'authprovider': 'static',
            },
            'wamp.registration.get' => <String, dynamic>{
              'id': 10,
              'uri': 'app.call',
              'match': 'prefix',
              'invoke': 'roundrobin',
            },
            'wamp.subscription.get' => <String, dynamic>{
              'id': 20,
              'uri': 'app.events',
              'match': 'wildcard',
            },
            _ => throw StateError('Unexpected metadata query'),
          };
          transport._inbound.add(
            Result(
              message.requestId,
              ResultDetails(),
              argumentsKeywords: values,
            ),
          );
          return true;
        };
        final (_, cache) = await _cacheFixture(transport);
        final user = cache.snapshot.sessions[1]!;
        expect(
          [
            user.id,
            user.authId,
            user.authRole,
            user.authMethod,
            user.authProvider,
          ],
          [1, 'alice', 'reader', 'ticket', 'static'],
        );
        final registration = cache.snapshot.registrations[10]!;
        expect(
          [
            registration.id,
            registration.procedure,
            registration.match,
            registration.invoke,
          ],
          [10, 'app.call', 'prefix', 'roundrobin'],
        );
        final subscription = cache.snapshot.subscriptions[20]!;
        expect(
          [subscription.id, subscription.topic, subscription.match],
          [20, 'app.events', 'wildcard'],
        );
      },
    );

    test(
      'metadata deeply freezes maps lists and sets without sharing mutable input',
      () {
        final sequence = <Object?>[
          {
            'values': <int>[1, 2],
          },
        ];
        final set = <int>{3, 4};
        final input = <String, dynamic>{'nested': sequence, 'set': set};
        final user = WampSessionMeta.fromDetails(1, input);
        input['other'] = 'later';
        (sequence.single as Map)['values'] = <int>[9];
        sequence.clear();
        set.clear();
        expect(user.details, {
          'nested': [
            {
              'values': [1, 2],
            },
          ],
          'set': {3, 4},
        });
        expect(
          () => (user.details['nested'] as List).clear(),
          throwsUnsupportedError,
        );
        expect(
          () => ((user.details['nested'] as List).single as Map).clear(),
          throwsUnsupportedError,
        );
        expect(
          () =>
              (((user.details['nested'] as List).single as Map)['values']
                      as List)
                  .clear(),
          throwsUnsupportedError,
        );
        expect(
          () => (user.details['set'] as Set).clear(),
          throwsUnsupportedError,
        );
        expect([
          user.authId,
          user.authRole,
          user.authMethod,
          user.authProvider,
        ], everyElement(isNull));
        final members = <int>{1, 2};
        final registration = WampRegistrationMeta.fromDetails(
          10,
          {},
          callees: members,
        );
        final registrationCopy = registration.copyWith(callees: [3]);
        final subscription = WampSubscriptionMeta.fromDetails(
          20,
          {},
          subscribers: members,
        );
        final subscriptionCopy = subscription.copyWith(subscribers: [3]);
        members.clear();
        expect(registration.callees, {1, 2});
        expect(subscription.subscribers, {1, 2});
        expect(registrationCopy.callees, {3});
        expect(subscriptionCopy.subscribers, {3});
        expect(() => registrationCopy.callees.clear(), throwsUnsupportedError);
        expect(
          () => subscriptionCopy.subscribers.clear(),
          throwsUnsupportedError,
        );
        expect([
          registration.procedure,
          registration.match,
          registration.invoke,
          subscription.topic,
          subscription.match,
        ], everyElement(isNull));
      },
    );
  });
}

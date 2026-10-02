import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:connectanum_router/src/router/state/commands.dart';
import 'package:connectanum_router/src/router/state/session.dart';
import 'package:connectanum_router/src/router/state/store.dart';
import 'package:connectanum_router/src/router/state/subscription.dart';
import 'package:test/test.dart';

void main() {
  const realm = 'subscriptions';
  const topic = 'com.example.updates';
  late RouterStateStore store;
  late RealmContextCache contexts;
  late RealmContext context;

  setUp(() async {
    final settings = RouterSettingsBuilder()
      ..addRealmFromBuilder(RealmSettingsBuilder(realm))
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('rawsocket', '127.0.0.1:0'),
      );
    store = RouterStateStore(settings: settings.build())..start();
    contexts = RealmContextCache(statePort: store.commandPort);
    context = contexts.contextFor(realm);
    final listener = RouterListener(
      listenerId: -1,
      endpoint: Endpoint(
        host: '127.0.0.1',
        port: 0,
        tlsMode: TlsMode.disabled,
        maxRawSocketSizeExponent: 16,
      ),
      port: 0,
      http3Port: 0,
    );
    for (final (id, authId, role) in <(int, String?, String?)>[
      (1, 'alice', 'member'),
      (2, 'bob', 'member'),
      (3, 'carol', 'admin'),
      (4, null, null),
    ]) {
      store.commandPort.send(
        SessionOpenCommand(
          realmUri: realm,
          session: SessionRecord(
            id: id,
            authId: authId,
            authRole: role,
            roles: const {},
            workerId: 0,
            connectionId: id + 100,
            lastActivity: DateTime.now(),
            listener: listener,
          ),
        ),
      );
    }
    await context.ensureSnapshot(forceRefresh: true);
  });

  tearDown(() {
    contexts.dispose();
    store.dispose();
  });

  Future<int> subscribe(int sessionId) => context.addSubscription(
    sessionId: sessionId,
    topic: topic,
    matchPolicy: TopicMatchPolicy.exact,
    details: {'label': 'subscriber-$sessionId'},
  );

  Future<PublicationRouting> route([Map<String, Object?> options = const {}]) =>
      context.matchSubscriptions(
        publisherSessionId: 1,
        topic: topic,
        options: options,
      );

  test(
    'shared subscription preserves owners and emits exact lifecycle events',
    () async {
      final events = <SubscriptionMetaEvent>[];
      final listener = store.subscriptionMetaEvents.listen(events.add);
      addTearDown(listener.cancel);
      final id = await subscribe(1);
      expect(await subscribe(2), id);
      expect(events.map((event) => (event.type, event.sessionId)), [
        (SubscriptionMetaEventType.created, 1),
        (SubscriptionMetaEventType.subscribed, 1),
        (SubscriptionMetaEventType.subscribed, 2),
      ]);
      for (final event in events) {
        expect(event.realmUri, realm);
        expect(event.subscriptionId, id);
        expect(event.topic, topic);
        expect(event.matchPolicy, TopicMatchPolicy.exact);
        expect(event.created, events.first.created);
      }
      expect(
        (await route()).matches.map((match) => match.sessionId),
        unorderedEquals([1, 2]),
      );
      await context.removeSubscription(sessionId: 3, subscriptionId: id);
      expect(events, hasLength(3));
      expect(
        (await route()).matches.map((match) => match.sessionId),
        unorderedEquals([1, 2]),
      );
      await context.removeSubscription(sessionId: 1, subscriptionId: id);
      expect((await route()).matches.map((match) => match.sessionId), [2]);
      expect(events.last.type, SubscriptionMetaEventType.unsubscribed);
      expect(events.last.sessionId, 1);
      expect(events, hasLength(4));
      await context.removeSubscription(sessionId: 1, subscriptionId: id);
      expect(events, hasLength(4));
      await context.removeSubscription(sessionId: 2, subscriptionId: id);
      expect((await route()).matches, isEmpty);
      expect(events.skip(4).map((event) => (event.type, event.sessionId)), [
        (SubscriptionMetaEventType.unsubscribed, 2),
        (SubscriptionMetaEventType.deleted, 2),
      ]);
      final replacement = await subscribe(1);
      expect(replacement, isNot(id));
      expect((await route()).matches.single.subscriptionId, replacement);
    },
  );

  test(
    'unknown subscriber fails without poisoning later subscriptions',
    () async {
      await expectLater(
        subscribe(999),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Bad state: Session 999 not found in realm subscriptions',
          ),
        ),
      );
      expect((await route()).matches, isEmpty);
      final id = await subscribe(1);
      final matches = (await route()).matches;
      expect(matches, hasLength(1));
      expect(matches.single.subscriptionId, id);
      expect(matches.single.sessionId, 1);
    },
  );

  test(
    'resubscription has one recipient and routing details are detached',
    () async {
      final id = await subscribe(1);
      expect(await subscribe(1), id);
      final first = (await route()).matches;
      expect(first, hasLength(1));
      expect(first.single.connectionId, 101);
      expect(first.single.authRole, 'member');
      expect(first.single.details, {'label': 'subscriber-1'});
      first.single.details['label'] = 'changed';
      expect((await route()).matches.single.details, {'label': 'subscriber-1'});
    },
  );

  for (final (options, recipients) in <(Map<String, Object?>, List<int>)>[
    ({'exclude_me': false}, [1, 2, 3, 4]),
    ({'exclude_me': true}, [2, 3, 4]),
    ({'exclude_me': 'true'}, [1, 2, 3, 4]),
    (
      {
        'exclude': [1, 3],
      },
      [2, 4],
    ),
    ({'exclude': <int>[]}, [1, 2, 3, 4]),
    (
      {
        'eligible': [1, 3],
      },
      [1, 3],
    ),
    ({'eligible': <int>[]}, []),
    (
      {
        'eligible': ['1', '3', '3'],
      },
      [1, 3],
    ),
    (
      {
        'eligible': [1, '3', 'invalid', null, 2.0],
      },
      [1, 3],
    ),
    (
      {
        'exclude': ['1', '3', 'invalid', null, 2.0],
      },
      [2, 4],
    ),
    (
      {
        'eligible': ['invalid', null, 2.0],
      },
      [],
    ),
    (
      {
        'exclude': [1],
        'eligible': [1, 2],
      },
      [2],
    ),
    (
      {
        'exclude_authid': ['alice'],
      },
      [2, 3, 4],
    ),
    (
      {
        'exclude_authids': ['alice'],
      },
      [2, 3, 4],
    ),
    (
      {
        'eligible_authid': ['alice'],
      },
      [1],
    ),
    (
      {
        'eligible_authids': ['alice'],
      },
      [1],
    ),
    (
      {
        'exclude_authrole': ['member'],
      },
      [3, 4],
    ),
    (
      {
        'exclude_authroles': ['member'],
      },
      [3, 4],
    ),
    (
      {
        'eligible_authrole': ['member'],
      },
      [1, 2],
    ),
    (
      {
        'eligible_authroles': ['member'],
      },
      [1, 2],
    ),
    (
      {
        'eligible_authid': ['alice', 'carol'],
        'eligible_authrole': ['member'],
      },
      [1],
    ),
    (
      {
        'eligible_authrole': ['member'],
        'exclude_authid': ['alice'],
      },
      [2],
    ),
    ({'eligible_authid': <String>[]}, []),
    ({'eligible_authrole': <String>[]}, []),
    (
      {
        'eligible_authid': [null, '', 'alice', 'alice'],
      },
      [1],
    ),
    (
      {
        'eligible_authrole': [null, '', 'admin'],
      },
      [3],
    ),
    (
      {
        'exclude_authid': <String>[],
        'exclude_authids': ['alice'],
      },
      [1, 2, 3, 4],
    ),
    (
      {
        'eligible_authid': <String>[],
        'eligible_authids': ['alice'],
      },
      [],
    ),
  ]) {
    test('recipient filtering respects $options', () async {
      for (var sessionId = 1; sessionId <= 4; sessionId++) {
        await subscribe(sessionId);
      }
      final routing = await route(options);
      expect(
        routing.matches.map((match) => match.sessionId),
        unorderedEquals(recipients),
      );
      for (final match in routing.matches) {
        expect(match.connectionId, match.sessionId + 100);
        expect(match.details, {'label': 'subscriber-${match.sessionId}'});
      }
    });
  }
}

import 'dart:async';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

Event _event([int publicationId = 31]) => Event(
  23,
  publicationId,
  EventDetails(topic: 'com.example.updates', publisher: 41, trustlevel: 0),
  arguments: ['message'],
  argumentsKeywords: {'sequence': publicationId},
);

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  for (final replaceAfterDelivery in [false, true]) {
    test(
      'override uses replacement handler afterDelivery=$replaceAfterDelivery',
      () async {
        final source = StreamController<Event>.broadcast(sync: true);
        final subscribed = Subscribed(17, 23)..eventStream = source.stream;
        addTearDown(() async {
          await subscribed.closeEventStream();
          await source.close();
        });
        final first = <int>[];
        final second = <int>[];
        subscribed.onEvent((event) => first.add(event.publicationId));
        if (replaceAfterDelivery) source.add(_event(29));
        subscribed.onEvent((event) => second.add(event.publicationId));
        source.add(_event());
        expect(first, replaceAfterDelivery ? [29] : isEmpty);
        expect(second, [31]);
      },
    );
  }

  test('handler installed before override attaches exactly once', () async {
    final subscribed = Subscribed(17, 23);
    final source = StreamController<Event>.broadcast(sync: true);
    final received = <Event>[];
    addTearDown(() async {
      await subscribed.closeEventStream();
      await source.close();
    });
    expect(() => subscribed.onEvent(received.add), returnsNormally);
    final stream = source.stream;
    subscribed.eventStream = stream;
    subscribed.onEvent(received.add);
    final event = _event();
    source.add(event);
    expect(received, [same(event)]);
    expect(subscribed.eventStream, same(stream));
  });

  test(
    'internal broadcast delivers synchronously to independent listeners',
    () async {
      final subscribed = Subscribed(17, 23);
      final direct = <int>[];
      final first = <int>[];
      final second = <int>[];
      expect(
        () => subscribed.onEvent((event) => direct.add(event.publicationId)),
        returnsNormally,
      );
      final stream = subscribed.eventStream!;
      expect(stream.isBroadcast, isTrue);
      final a = stream.listen((event) => first.add(event.publicationId));
      final b = subscribed.eventStream!.listen(
        (event) => second.add(event.publicationId),
      );
      addTearDown(() async {
        await a.cancel();
        await b.cancel();
        await subscribed.closeEventStream();
      });
      subscribed.addEvent(_event(29));
      expect(direct, [29]);
      expect(first, [29]);
      expect(second, [29]);
      await a.cancel();
      subscribed.addEvent(_event());
      expect(direct, [29, 31]);
      expect(first, [29]);
      expect(second, [29, 31]);
    },
  );

  test(
    'closing internal stream completes listeners without creating a stream',
    () async {
      final subscribed = Subscribed(17, 23);
      await subscribed.closeEventStream();
      expect(subscribed.hasMaterializedEventConsumers, isFalse);
      var done = false;
      final subscription = subscribed.eventStream!.listen(
        (_) {},
        onDone: () => done = true,
      );
      addTearDown(subscription.cancel);
      await subscribed.closeEventStream();
      expect(done, isTrue);
      expect(subscribed.hasMaterializedEventConsumers, isFalse);
      await subscribed.closeEventStream();
    },
  );

  test('closing waits for override cancellation', () async {
    final release = Completer<void>();
    var cancelled = false;
    var listened = false;
    final source = StreamController<Event>(
      onListen: () => listened = true,
      onCancel: () {
        cancelled = true;
        return release.future;
      },
    );
    final subscribed = Subscribed(17, 23)..eventStream = source.stream;
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await subscribed.closeEventStream();
      if (!listened) await source.stream.listen((_) {}).cancel();
      await source.close();
    });
    final received = <int>[];
    subscribed.onEvent((event) => received.add(event.publicationId));
    expect(source.hasListener, isTrue);
    source.add(_event(29));
    await _pump();
    expect(received, [29]);
    var closed = false;
    final closing = subscribed.closeEventStream().then((_) => closed = true);
    await _pump();
    expect(cancelled, isTrue);
    expect(closed, isFalse);
    source.add(_event());
    release.complete();
    await _pump();
    expect(closed, isTrue);
    await closing;
    expect(received, [29]);
  });

  test('revocation completes all observers with the exact reason', () async {
    final subscribed = Subscribed(17, 23);
    final reason = subscribed.onRevoke;
    expect(subscribed.onRevoke, same(reason));
    subscribed.revoke('wamp.error.not_authorized');
    expect(await reason, 'wamp.error.not_authorized');
    expect(await subscribed.onRevoke, 'wamp.error.not_authorized');
  });

  for (var mask = 0; mask < 8; mask++) {
    for (final route in ['event', 'payload', 'lazy']) {
      test('delivery route=$route handlerMask=$mask', () {
        final subscribed = Subscribed(17, 23)..topic = 'com.example.updates';
        expect(subscribed.id, MessageTypes.codeSubscribed);
        expect(subscribed.subscribeRequestId, 17);
        expect(subscribed.subscriptionId, 23);
        expect(subscribed.topic, 'com.example.updates');
        expect(subscribed.hasMaterializedEventConsumers, isFalse);
        expect(subscribed.hasPayloadEventHandler, isFalse);
        expect(subscribed.hasLazyPayloadEventHandler, isFalse);
        final materialized = <Event>[];
        final payloads = <EventPayload>[];
        final lazy = <LazyEventPayload>[];
        if (mask & 1 != 0) {
          expect(() => subscribed.onEvent(materialized.add), returnsNormally);
        }
        if (mask & 2 != 0) subscribed.onEventPayload(payloads.add);
        if (mask & 4 != 0) subscribed.onLazyEventPayload(lazy.add);
        expect(subscribed.hasMaterializedEventConsumers, mask & 1 != 0);
        expect(subscribed.hasPayloadEventHandler, mask & 2 != 0);
        expect(subscribed.hasLazyPayloadEventHandler, mask & 4 != 0);
        final event = _event();
        switch (route) {
          case 'event':
            subscribed.addEvent(event);
          case 'payload':
            subscribed.addEventPayload(event.toPayload());
          case 'lazy':
            subscribed.addLazyEventPayload(event.toLazyEventPayload());
        }
        expect(
          materialized,
          mask & 1 != 0 && route == 'event' ? [same(event)] : isEmpty,
        );
        expect(payloads, hasLength(mask & 2 != 0 ? 1 : 0));
        expect(lazy, hasLength(mask & 4 != 0 && route != 'payload' ? 1 : 0));
        for (final payload in [
          ...payloads,
          ...lazy.map((item) => item.toPayload()),
        ]) {
          expect(payload.subscriptionId, 23);
          expect(payload.publicationId, 31);
          expect(payload.publisher, 41);
          expect(payload.trustlevel, 0);
          expect(payload.topic, 'com.example.updates');
          expect(payload.arguments, ['message']);
          expect(payload.argumentsKeywords, {'sequence': 31});
        }
      });
    }
  }
}

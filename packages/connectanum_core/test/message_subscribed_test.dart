import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  group('Subscribed', () {
    test('onEvent receives added events without creating an event stream', () {
      final subscribed = Subscribed(1, 2);
      final received = <Event>[];

      subscribed.onEvent(received.add);
      subscribed.addEvent(Event(2, 3, EventDetails(), arguments: const ['ok']));

      expect(received, hasLength(1));
      expect(received.single.arguments, equals(const ['ok']));
    });

    test('onEventPayload receives payloads without Event allocation', () {
      final subscribed = Subscribed(1, 2);
      EventPayload? received;

      subscribed.onEventPayload((event) {
        received = event;
      });
      subscribed.addEventPayload((
        subscriptionId: 2,
        publicationId: 3,
        publisher: null,
        trustlevel: null,
        topic: 'bench.topic',
        pptScheme: null,
        pptSerializer: null,
        pptCipher: null,
        pptKeyId: null,
        customDetails: null,
        arguments: const ['ok'],
        argumentsKeywords: const {'worker': 1},
      ));

      expect(received, isNotNull);
      expect(received!.publicationId, 3);
      expect(received!.topic, 'bench.topic');
      expect(received!.argumentsKeywords, equals(const {'worker': 1}));
    });

    test('onEventPayload unpacks PPT payloads from materialized events', () {
      final subscribed = Subscribed(1, 2);
      EventPayload? received;

      subscribed.onEventPayload((event) {
        received = event;
      });
      subscribed.addEvent(
        Event(
          2,
          3,
          EventDetails(pptScheme: 'x_custom_scheme', pptSerializer: 'cbor'),
          arguments: PPTPayload.packPPTPayload(
            const ['ppt-event'],
            const {'worker': 4},
            EventDetails(pptScheme: 'x_custom_scheme', pptSerializer: 'cbor'),
          ),
        ),
      );

      expect(received, isNotNull);
      expect(received!.arguments, equals(const ['ppt-event']));
      expect(received!.argumentsKeywords, equals(const {'worker': 4}));
    });

    test('onLazyEventPayload preserves encoded payload bytes until needed', () {
      final subscribed = Subscribed(1, 2);
      LazyEventPayload? received;
      final event = Event(2, 3, EventDetails(topic: 'bench.topic'));
      event.setLazyPayload(
        argumentsBytes: Uint8List.fromList(utf8.encode('["ok"]')),
        argumentsDecoder: (bytes) =>
            (jsonDecode(utf8.decode(bytes)) as List<dynamic>),
        argumentsKeywordsBytes: Uint8List.fromList(utf8.encode('{"worker":1}')),
        argumentsKeywordsDecoder: (bytes) => Map<String, dynamic>.from(
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
        ),
      );

      subscribed.onLazyEventPayload((lazyEvent) {
        received = lazyEvent;
      });
      subscribed.addEvent(event);

      expect(received, isNotNull);
      expect(received!.topic, 'bench.topic');
      expect(received!.argumentsBytes, isNotNull);
      expect(received!.argumentsKeywordsBytes, isNotNull);
      expect(received!.arguments, equals(const ['ok']));
      expect(received!.argumentsKeywords, equals(const {'worker': 1}));
    });

    test('onEvent can consume an override event stream', () async {
      final subscribed = Subscribed(1, 2);
      final controller = StreamController<Event>.broadcast(sync: true);
      final received = <Event>[];

      subscribed.eventStream = controller.stream;
      subscribed.onEvent(received.add);
      controller.add(
        Event(2, 4, EventDetails(), argumentsKeywords: const {'worker': 1}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.argumentsKeywords, equals(const {'worker': 1}));

      await subscribed.closeEventStream();
      await controller.close();
    });
  });
}

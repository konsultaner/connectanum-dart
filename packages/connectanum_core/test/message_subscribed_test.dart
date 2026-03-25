import 'dart:async';

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

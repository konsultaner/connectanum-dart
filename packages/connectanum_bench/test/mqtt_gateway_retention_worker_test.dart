@TestOn('vm')
library;

import 'dart:async';

import 'package:test/test.dart';

import 'support/mqtt_gateway_retention_worker.dart' as retention;

void main() {
  test('internal collection is restricted to the verified SDK', () {
    retention.RetentionCollector.validateSdk('3.13.1 (stable) (build)');
    for (final version in [
      '3.13.10 (stable)',
      '3.13.1 (dev)',
      '3.14.0 (stable)',
      '',
    ]) {
      expect(
        () => retention.RetentionCollector.validateSdk(version),
        throwsUnsupportedError,
      );
    }
  });

  test('both fixed collection passes finish before cache release', () async {
    final events = <String>[];
    final collector = retention.RetentionCollector(
      collect: () {
        events.add('collect');
        scheduleMicrotask(() => events.add('finalizer'));
      },
      clearCaches: () => events.add('clear'),
      witnessFactory: () =>
          () => true,
      settle: Duration.zero,
    );
    await collector.collect();
    expect(events, [
      'collect',
      'finalizer',
      'clear',
      'collect',
      'finalizer',
      'clear',
    ]);
    expect(collector.collections, 2);
  });

  test('failed collection is never reported as complete', () async {
    var clears = 0;
    final collector = retention.RetentionCollector(
      collect: () => throw StateError('unavailable'),
      clearCaches: () => clears++,
      settle: Duration.zero,
    );
    await expectLater(collector.collect(), throwsStateError);
    expect(collector.collections, 0);
    expect(clears, 0);
  });

  test('an incomplete collection cannot produce a memory reading', () async {
    final collector = retention.RetentionCollector(
      collect: () {},
      clearCaches: () {},
      witnessFactory: () =>
          () => false,
      settle: Duration.zero,
    );
    await expectLater(collector.collect(), throwsStateError);
  });
}

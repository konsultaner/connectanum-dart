@TestOn('vm')
library;

import 'dart:async';

import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

void main() {
  const idle = Duration(hours: 1);

  test(
    'queued wake consumed by busy work does not force an idle event turn',
    () async {
      final pacer = RouterBossLoopPacer();
      var idleTimers = 0;
      Future<void>? pending;
      try {
        await runZoned(
          () async {
            pacer.requestWake();
            await pacer.waitForNextTick(didWork: true, pollInterval: idle);
            pending = pacer.waitForNextTick(didWork: false, pollInterval: idle);
            expect(
              idleTimers,
              1,
              reason: 'queued wake was not consumed during busy pass',
            );
          },
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, delay, callback) {
              if (delay == idle) idleTimers++;
              return parent.createTimer(zone, delay, callback);
            },
          ),
        );
      } finally {
        pacer.requestWake();
        await pending;
        pacer.close();
      }
    },
  );

  test('new wake arriving during a busy event turn remains pending', () async {
    final pacer = RouterBossLoopPacer();
    var idleTimers = 0;
    Future<void>? pending;
    try {
      await runZoned(
        () async {
          final busy = pacer.waitForNextTick(didWork: true, pollInterval: idle);
          pacer.requestWake();
          await busy;
          pending = pacer.waitForNextTick(didWork: false, pollInterval: idle);
          expect(idleTimers, 0);
          await pending;
          pending = pacer.waitForNextTick(didWork: false, pollInterval: idle);
          expect(idleTimers, 1);
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, delay, callback) {
            if (delay == idle) idleTimers++;
            return parent.createTimer(zone, delay, callback);
          },
        ),
      );
    } finally {
      pacer.requestWake();
      await pending;
      pacer.close();
    }
  });
}

@TestOn('vm')
library;

import 'dart:async';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  for (final timeoutMs in [15, 75]) {
    test(
      'file receiver registration has the $timeoutMs ms scenario deadline',
      () async {
        final receiver = _RegistrationSession();
        final sender = _RegistrationSession();
        final timers = <_ControlledTimer>[];
        final cancelled = Completer<void>();
        var cancelCount = 0;
        var opened = 0;
        final pending = runZoned(
          () =>
              WampWorkloadRunner(
                sessionFactory: (_) async => opened++ == 0 ? sender : receiver,
              ).run(
                WampScenario(
                  transport: WampTransport.rawsocket,
                  serializer: WampSerializer.cbor,
                  mode: WampMode.fileTransfer,
                  uri: 'bench.file_deadline',
                  iterations: 1,
                  concurrency: 1,
                  payloadBytes: 1,
                  eventTimeoutMs: timeoutMs,
                ),
              ),
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              final timer = _ControlledTimer(duration, callback);
              timers.add(timer);
              return timer;
            },
          ),
        ).then<Object>((value) => value, onError: (Object error) => error);
        await receiver.entered.future;
        try {
          final active = timers.where((timer) => timer.isActive).toList();
          expect(
            active,
            hasLength(1),
            reason: 'Registration must own a deadline.',
          );
          expect(active.single.duration, Duration(milliseconds: timeoutMs));
          active.single.fire();
          expect(
            await pending,
            isA<TimeoutException>().having(
              (error) => error.message,
              'message',
              'file_receiver_registration',
            ),
          );
          expect(sender.sendCount, 0);
          expect(receiver.sendCount, 0);
          expect(sender.closeCount, 1);
          expect(receiver.closeCount, 1);
          expect(timers.where((timer) => timer.isActive), isEmpty);
        } finally {
          // Let a missing-deadline implementation finish too, without leaving
          // a registration, file, or unobserved Future behind after the assertion.
          receiver.registration.complete(
            WampRegistration(
              cancel: () async {
                cancelCount++;
                if (!cancelled.isCompleted) cancelled.complete();
              },
            ),
          );
          await pending;
          await cancelled.future;
          expect(cancelCount, 1);
        }
      },
    );
  }

  test(
    'successful registration cancels its deadline and receiver once',
    () async {
      final fixture = _RegistrationFixture();
      var cancelled = 0;
      await fixture.receiver.entered.future;
      fixture.receiver.registration.complete(
        WampRegistration(cancel: () async => cancelled++),
      );
      final result = await fixture.pending;
      expect(result, isA<List<WampSample>>());
      expect((result as List<WampSample>).single.requestBytes, 1);
      expect(fixture.sender.sendCount, 1);
      expect(fixture.sender.closeCount, 1);
      expect(fixture.receiver.closeCount, 1);
      expect(cancelled, 1);
      expect(fixture.activeTimers, isEmpty);
    },
  );

  test(
    'registration failure preserves its error and closes both sessions',
    () async {
      final fixture = _RegistrationFixture();
      final error = StateError('registration rejected');
      await fixture.receiver.entered.future;
      fixture.receiver.registration.completeError(error);
      expect(await fixture.pending, same(error));
      expect(fixture.sender.sendCount, 0);
      expect(fixture.sender.closeCount, 1);
      expect(fixture.receiver.closeCount, 1);
      expect(fixture.activeTimers, isEmpty);
    },
  );

  test(
    'late registration failure does not replace the timeout or escape',
    () async {
      final fixture = _RegistrationFixture();
      final lateError = StateError('late registration rejection');
      await fixture.receiver.entered.future;
      try {
        expect(fixture.activeTimers, hasLength(1));
        fixture.activeTimers.single.fire();
        final result = await fixture.pending;
        expect(result, isA<TimeoutException>());
        fixture.receiver.registration.completeError(lateError);
        await fixture.receiver.registration.future.then<void>(
          (_) => fail('The controlled registration must fail.'),
          onError: (Object error) => expect(error, same(lateError)),
        );
        expect(await fixture.pending, same(result));
        expect(fixture.sender.closeCount, 1);
        expect(fixture.receiver.closeCount, 1);
        expect(fixture.sender.sendCount, 0);
        expect(fixture.activeTimers, isEmpty);
      } finally {
        await fixture.release();
      }
    },
  );

  test(
    'failed late cancellation is contained and logged without error data',
    () async {
      final logger = Logger.detached('file_registration_late_cleanup');
      logger.level = Level.ALL;
      final warning = Completer<LogRecord>();
      final subscription = logger.onRecord.listen((record) {
        if (record.message ==
            'late file receiver registration cleanup failed') {
          warning.complete(record);
        }
      });
      addTearDown(subscription.cancel);
      final fixture = _RegistrationFixture(logger: logger);
      await fixture.receiver.entered.future;
      try {
        expect(fixture.activeTimers, hasLength(1));
        fixture.activeTimers.single.fire();
        expect(await fixture.pending, isA<TimeoutException>());
        var cancelled = 0;
        fixture.receiver.registration.complete(
          WampRegistration(
            cancel: () async {
              cancelled++;
              throw StateError('synthetic private cancellation detail');
            },
          ),
        );
        final record = await warning.future;
        expect(record.level, Level.WARNING);
        expect(record.error, isNull);
        expect(record.stackTrace, isNull);
        expect(record.message, isNot(contains('synthetic private')));
        expect(cancelled, 1);
        expect(fixture.sender.closeCount, 1);
        expect(fixture.receiver.closeCount, 1);
        expect(fixture.activeTimers, isEmpty);
      } finally {
        await fixture.release();
      }
    },
  );
}

class _RegistrationFixture {
  _RegistrationFixture({Logger? logger}) {
    var opened = 0;
    pending = runZoned(
      () =>
          WampWorkloadRunner(
            sessionFactory: (_) async => opened++ == 0 ? sender : receiver,
            logger: logger,
          ).run(
            WampScenario(
              transport: WampTransport.rawsocket,
              serializer: WampSerializer.cbor,
              mode: WampMode.fileTransfer,
              uri: 'bench.file_registration_lifecycle',
              iterations: 1,
              concurrency: 1,
              payloadBytes: 1,
              eventTimeoutMs: 25,
            ),
          ),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = _ControlledTimer(duration, callback);
          timers.add(timer);
          return timer;
        },
      ),
    ).then<Object>((value) => value, onError: (Object error) => error);
  }

  final receiver = _RegistrationSession();
  final sender = _RegistrationSession();
  final timers = <_ControlledTimer>[];
  late final Future<Object> pending;
  List<_ControlledTimer> get activeTimers =>
      timers.where((timer) => timer.isActive).toList();

  Future<void> release() async {
    if (!receiver.registration.isCompleted) {
      receiver.registration.complete(WampRegistration(cancel: () async {}));
    }
    await pending;
  }
}

class _ControlledTimer implements Timer {
  _ControlledTimer(this.duration, this.callback);
  final Duration duration;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }
}

class _RegistrationSession implements WampSession, WampFileSession {
  final entered = Completer<void>();
  final registration = Completer<WampRegistration>();
  int sendCount = 0;
  int closeCount = 0;

  @override
  int get id => 11;
  @override
  Future<dynamic> get onDisconnect => Completer<void>().future;
  @override
  Future<void> close() async => closeCount++;

  @override
  Future<WampRegistration> registerFileReceiver(
    String procedure, {
    required int maxConcurrentTransfers,
    required int maxChunkSize,
    required Duration idleTimeout,
  }) {
    entered.complete();
    return registration.future;
  }

  @override
  Future<void> sendFile(
    String procedure,
    client.WampFileSource source, {
    required int chunkSize,
    required Duration timeout,
    core.CallOptions? options,
  }) async => sendCount++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

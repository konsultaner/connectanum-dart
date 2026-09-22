part of '../router_runtime_test.dart';

const _watchInterval = Duration(hours: 1);

class _WatchTimer implements Timer {
  _WatchTimer(this.callback);

  final void Function() callback;
  bool active = true;
  int ticks = 0;

  @override
  bool get isActive => active;

  @override
  int get tick => ticks;

  @override
  void cancel() => active = false;

  void fire() {
    if (!active) return;
    active = false;
    ticks++;
    callback();
  }
}

class _WatchRuntime extends _FakeRuntime {
  Object? failure;
  int? failAt;
  int polls = 0;
  void Function()? onPoll;

  @override
  NativeIncomingMessage? pollMessage(int connectionId) {
    polls++;
    onPoll?.call();
    final error = failure;
    if (error != null && (failAt == null || failAt == polls)) throw error;
    return super.pollMessage(connectionId);
  }
}

class _WatchMessage implements NativeIncomingMessage {
  _WatchMessage([this.failure]);

  final Object? failure;
  int releases = 0;

  @override
  void dispose() {
    releases++;
    final error = failure;
    if (error != null) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

T _withWatchTimers<T>(List<_WatchTimer> timers, T Function() body) => runZoned(
  body,
  zoneSpecification: ZoneSpecification(
    createTimer: (self, parent, zone, duration, callback) {
      if (duration != _watchInterval) {
        return parent.createTimer(zone, duration, callback);
      }
      final timer = _WatchTimer(zone.bindCallbackGuarded(callback));
      timers.add(timer);
      return timer;
    },
  ),
);

RouterBinding _watchBinding(_FakeRuntime runtime) {
  final binding = Router(
    RouterConfig(
      endpoints: [
        Endpoint(
          host: '127.0.0.1',
          port: 0,
          tlsMode: TlsMode.native,
          maxRawSocketSizeExponent: 16,
          sniCertificates: [_cert('localhost')],
        ),
      ],
    ),
  ).start(runtime);
  runtime.enqueueConnection(binding.listeners.single.listenerId, 84);
  return binding;
}

void _nativeMessageWatchCases() {
  test(
    'native watch disposal during timer creation cancels the returned timer',
    () async {
      final runtime = _WatchRuntime();
      final binding = _watchBinding(runtime);
      final timers = <_WatchTimer>[];
      Future<void>? disposal;
      var done = false;
      final subscription = runZoned(
        () => binding
            .watchNativeMessages(pollInterval: _watchInterval)
            .listen(
              (message) => message.message.dispose(),
              onDone: () => done = true,
            ),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration != _watchInterval) {
              return parent.createTimer(zone, duration, callback);
            }
            disposal = binding.dispose();
            final timer = _WatchTimer(zone.bindCallbackGuarded(callback));
            timers.add(timer);
            return timer;
          },
        ),
      );
      addTearDown(subscription.cancel);
      await disposal;
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
      expect(timers, hasLength(1));
      expect(timers.single.isActive, isFalse);
      expect(runtime.polls, 1);
    },
  );

  test('native watch resume timer failure is a stream error', () async {
    final runtime = _WatchRuntime();
    final binding = _watchBinding(runtime);
    addTearDown(binding.dispose);
    final failure = StateError('timer setup failed');
    final errors = <Object>[];
    final escaped = <Object>[];
    final timers = <_WatchTimer>[];
    var done = false;
    final subscription = _withWatchTimers(
      timers,
      () => binding
          .watchNativeMessages(pollInterval: _watchInterval)
          .listen(
            (message) => message.message.dispose(),
            onError: (Object error) => errors.add(error),
            onDone: () => done = true,
          ),
    );
    addTearDown(subscription.cancel);
    subscription.pause();
    runZonedGuarded(
      subscription.resume,
      (error, stack) => escaped.add(error),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration == _watchInterval) throw failure;
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(errors, [same(failure)]);
    expect(escaped, isEmpty);
    expect(done, isTrue);
    expect(runtime.polls, 1);
    expect(timers.where((timer) => timer.isActive), isEmpty);
  });

  test(
    'native watch cancellation during polling releases the whole batch',
    () async {
      final runtime = _WatchRuntime();
      final binding = _watchBinding(runtime);
      addTearDown(binding.dispose);
      final timers = <_WatchTimer>[];
      final delivered = <RouterMessage>[];
      final subscription = _withWatchTimers(
        timers,
        () => binding
            .watchNativeMessages(pollInterval: _watchInterval)
            .listen(delivered.add),
      );
      addTearDown(subscription.cancel);
      final messages = [
        _WatchMessage(StateError('release failed')),
        _WatchMessage(),
        _WatchMessage(),
      ];
      for (final message in messages) {
        runtime.enqueueMessage(
          binding.listeners.single.listenerId,
          84,
          message,
        );
      }
      Future<void>? cancelling;
      runtime.onPoll = () {
        runtime.onPoll = null;
        cancelling = subscription.cancel();
      };
      timers.single.fire();
      await cancelling;
      expect(delivered, isEmpty);
      expect(messages.map((message) => message.releases), [1, 1, 1]);
      expect(timers.where((timer) => timer.isActive), isEmpty);
    },
  );

  test(
    'native watch partial batch cleanup preserves polling failure',
    () async {
      final runtime = _WatchRuntime()
        ..failure = StateError('poll failure')
        ..failAt = 3;
      final binding = _watchBinding(runtime);
      addTearDown(binding.dispose);
      final messages = [
        _WatchMessage(StateError('release failure')),
        _WatchMessage(),
      ];
      for (final message in messages) {
        runtime.enqueueMessage(
          binding.listeners.single.listenerId,
          84,
          message,
        );
      }
      expect(binding.pollNativeMessages, throwsA(same(runtime.failure)));
      expect(messages.map((message) => message.releases), [1, 1]);
    },
  );

  test(
    'native watch cancel releases all queued messages if disposal fails',
    () async {
      final runtime = _WatchRuntime();
      final binding = _watchBinding(runtime);
      addTearDown(binding.dispose);
      final failure = StateError('release failure');
      final messages = [
        _WatchMessage(failure),
        _WatchMessage(),
        _WatchMessage(),
      ];
      for (final message in messages) {
        runtime.enqueueMessage(
          binding.listeners.single.listenerId,
          84,
          message,
        );
      }
      final timers = <_WatchTimer>[];
      final delivered = <RouterMessage>[];
      final subscription = _withWatchTimers(
        timers,
        () => binding
            .watchNativeMessages(pollInterval: _watchInterval)
            .listen(delivered.add),
      );
      await expectLater(subscription.cancel(), throwsA(same(failure)));
      expect(messages.map((message) => message.releases), [1, 1, 1]);
      expect(delivered, isEmpty);
      expect(timers.where((timer) => timer.isActive), isEmpty);
    },
  );

  test(
    'native watch disposing paused consumers does not wait for resume',
    () async {
      final runtime = _WatchRuntime();
      final binding = _watchBinding(runtime);
      final timers = <_WatchTimer>[];
      final done = <int>[];
      final subscriptions = [
        for (var index = 0; index < 2; index++)
          _withWatchTimers(
            timers,
            () => binding
                .watchNativeMessages(pollInterval: _watchInterval)
                .listen(
                  (message) => message.message.dispose(),
                  onDone: () => done.add(index),
                ),
          ),
      ];
      addTearDown(() async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        await binding.dispose();
      });
      for (final subscription in subscriptions) {
        subscription.pause();
      }
      var disposed = false;
      final disposal = binding.dispose().then((_) => disposed = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, isTrue);
      expect(done, isEmpty);
      expect(timers.where((timer) => timer.isActive), isEmpty);
      for (final subscription in subscriptions) {
        _withWatchTimers(timers, subscription.resume);
      }
      await Future<void>.delayed(Duration.zero);
      expect(done, unorderedEquals([0, 1]));
      expect(timers.where((timer) => timer.isActive), isEmpty);
      await disposal;
    },
  );

  for (final cancelAfterFirst in [false, true]) {
    test(
      'native watch cancellation releases queued messages ($cancelAfterFirst)',
      () async {
        final runtime = _WatchRuntime();
        final binding = _watchBinding(runtime);
        addTearDown(binding.dispose);
        final messages = List.generate(3, (_) => _WatchMessage());
        for (final message in messages) {
          runtime.enqueueMessage(
            binding.listeners.single.listenerId,
            84,
            message,
          );
        }
        final delivered = <RouterMessage>[];
        late StreamSubscription<RouterMessage> subscription;
        final cancelled = Completer<void>();
        subscription = binding.watchNativeMessages().listen((message) {
          delivered.add(message);
          if (cancelAfterFirst) cancelled.complete(subscription.cancel());
        });
        addTearDown(subscription.cancel);
        if (cancelAfterFirst) {
          await cancelled.future;
        } else {
          await subscription.cancel();
        }
        expect(delivered, hasLength(cancelAfterFirst ? 1 : 0));
        expect(
          messages.map((message) => message.releases),
          cancelAfterFirst ? [0, 1, 1] : [1, 1, 1],
        );
        for (final message in delivered) {
          message.message.dispose();
        }
        expect(messages.map((message) => message.releases), [1, 1, 1]);
      },
    );
  }

  test(
    'native watch poll failure releases a partially accumulated batch',
    () async {
      final runtime = _WatchRuntime()
        ..failure = StateError('third poll failed')
        ..failAt = 3;
      final binding = _watchBinding(runtime);
      addTearDown(binding.dispose);
      final messages = List.generate(2, (_) => _WatchMessage());
      for (final message in messages) {
        runtime.enqueueMessage(
          binding.listeners.single.listenerId,
          84,
          message,
        );
      }
      expect(binding.pollNativeMessages, throwsA(same(runtime.failure)));
      expect(messages.map((message) => message.releases), [1, 1]);
    },
  );

  test(
    'native watch pause resumes exactly one timer without polling while paused',
    () async {
      final runtime = _WatchRuntime();
      final binding = _watchBinding(runtime);
      addTearDown(binding.dispose);
      final timers = <_WatchTimer>[];
      final subscription = _withWatchTimers(
        timers,
        () => binding
            .watchNativeMessages(pollInterval: _watchInterval)
            .listen((message) => message.message.dispose()),
      );
      addTearDown(subscription.cancel);
      expect(runtime.polls, 1);
      subscription.pause();
      expect(timers.where((timer) => timer.isActive), isEmpty);
      for (final timer in timers.toList()) {
        timer.fire();
      }
      await Future<void>.delayed(Duration.zero);
      expect(runtime.polls, 1);
      _withWatchTimers(timers, subscription.resume);
      await Future<void>.delayed(Duration.zero);
      expect(timers.where((timer) => timer.isActive), hasLength(1));
      final beforeTick = runtime.polls;
      timers.last.fire();
      await Future<void>.delayed(Duration.zero);
      expect(runtime.polls, beforeTick + 1);
      expect(timers.where((timer) => timer.isActive), hasLength(1));
      await subscription.cancel();
      expect(timers.where((timer) => timer.isActive), isEmpty);
    },
  );

  test(
    'native watch created before disposal does not poll on late listen',
    () async {
      final runtime = _WatchRuntime();
      final binding = _watchBinding(runtime);
      final timers = <_WatchTimer>[];
      final stream = binding.watchNativeMessages(pollInterval: _watchInterval);
      await binding.dispose();
      var done = false;
      final subscription = _withWatchTimers(
        timers,
        () => stream.listen(
          (message) => message.message.dispose(),
          onDone: () => done = true,
        ),
      );
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(runtime.polls, 0);
      expect(timers.where((timer) => timer.isActive), isEmpty);
      expect(done, isTrue);
    },
  );

  test('native watch reports poll failure to its stream and closes', () async {
    final runtime = _WatchRuntime();
    final failure = StateError('poll failed');
    runtime.failure = failure;
    final binding = _watchBinding(runtime);
    addTearDown(binding.dispose);
    final errors = <Object>[];
    final uncaught = <Object>[];
    var done = false;
    final subscription = runZonedGuarded(
      () => binding.watchNativeMessages().listen(
        (message) => message.message.dispose(),
        onError: (Object error) => errors.add(error),
        onDone: () => done = true,
      ),
      (error, stack) => uncaught.add(error),
    )!;
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);
    expect(runtime.polls, 1);
    expect(errors, [same(failure)]);
    expect(uncaught, isEmpty);
    expect(done, isTrue);
  });

  for (final stop in ['cancel', 'dispose']) {
    test('native watch $stop stops the polling timer', () async {
      final runtime = _WatchRuntime();
      final binding = _watchBinding(runtime);
      addTearDown(binding.dispose);
      final timers = <_WatchTimer>[];
      var done = false;
      final subscription = runZoned(
        () => binding
            .watchNativeMessages(pollInterval: _watchInterval)
            .listen(
              (message) => message.message.dispose(),
              onDone: () => done = true,
            ),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration != _watchInterval) {
              return parent.createTimer(zone, duration, callback);
            }
            final timer = _WatchTimer(zone.bindCallbackGuarded(callback));
            timers.add(timer);
            return timer;
          },
        ),
      );
      addTearDown(subscription.cancel);
      expect(runtime.polls, 1);
      expect(timers.where((timer) => timer.isActive), hasLength(1));
      if (stop == 'cancel') {
        await subscription.cancel();
      } else {
        await binding.dispose();
      }
      await Future<void>.delayed(Duration.zero);
      expect(timers.where((timer) => timer.isActive), isEmpty);
      expect(done, stop == 'dispose');
      final polls = runtime.polls;
      for (final timer in timers.toList()) {
        timer.fire();
      }
      await Future<void>.delayed(Duration.zero);
      expect(runtime.polls, polls);
    });
  }
}

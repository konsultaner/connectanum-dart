import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/platform_push_registration.dart';
import 'package:wamp_app/src/infrastructure/platform_push_token_source.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('serializes initial and refreshed token registration', () async {
    final source = _FakeTokenSource();
    final session = source.addSession();
    final firstRegistration = Completer<PlatformPushSubscriptionReceipt>();
    final requests = <PlatformPushSubscriptionRequest>[];
    final coordinator = PlatformPushRegistrationCoordinator(source: source);

    final replacement = coordinator.replace(
      deviceId: _deviceOne,
      register: (request) {
        requests.add(request);
        if (requests.length == 1) return firstRegistration.future;
        return Future.value(_receiptFor(request));
      },
      unregister: (_) async => true,
    );
    await session.waitUntilListened();
    session.emit(const PlatformPushToken(provider: 'fcm', token: 'token-1'));
    session.emit(const PlatformPushToken(provider: 'fcm', token: 'token-2'));

    await _waitFor(() => requests.length == 1);
    firstRegistration.complete(_receiptFor(requests.single));
    await _waitFor(() => requests.length == 2);
    expect(requests.map((request) => request.token), ['token-1', 'token-2']);
    await replacement;

    await coordinator.dispose();
  });

  test('registers and refreshes the current mute policy', () async {
    final source = _FakeTokenSource();
    final session = source.addSession();
    final requests = <PlatformPushSubscriptionRequest>[];
    final coordinator = PlatformPushRegistrationCoordinator(source: source);

    await coordinator.replace(
      deviceId: _deviceOne,
      mutedConversationIds: const ['conversation-b', 'conversation-a'],
      register: (request) async {
        requests.add(request);
        return _receiptFor(request);
      },
      unregister: (_) async => true,
    );
    await session.waitUntilListened();
    session.emit(const PlatformPushToken(provider: 'fcm', token: 'token-1'));
    await _waitFor(() => requests.length == 1);
    expect(requests.single.mutedConversationIds, [
      'conversation-a',
      'conversation-b',
    ]);

    await coordinator.updateMutedConversationIds(const ['conversation-c']);
    await _waitFor(() => requests.length == 2);
    expect(requests.last.token, 'token-1');
    expect(requests.last.mutedConversationIds, ['conversation-c']);

    await coordinator.updateMutedConversationIds(const ['conversation-c']);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(requests, hasLength(2));
    await coordinator.dispose();
  });

  test(
    'mute changes before the first token apply to initial registration',
    () async {
      final source = _FakeTokenSource();
      final session = source.addSession();
      final requests = <PlatformPushSubscriptionRequest>[];
      final coordinator = PlatformPushRegistrationCoordinator(source: source);

      await coordinator.replace(
        deviceId: _deviceOne,
        register: (request) async {
          requests.add(request);
          return _receiptFor(request);
        },
        unregister: (_) async => true,
      );
      await session.waitUntilListened();
      await coordinator.updateMutedConversationIds(const ['conversation-a']);
      session.emit(const PlatformPushToken(provider: 'fcm', token: 'token-1'));
      await _waitFor(() => requests.isNotEmpty);

      expect(requests.single.mutedConversationIds, ['conversation-a']);
      await coordinator.dispose();
    },
  );

  test(
    'stale in-flight registration unregisters itself before clear',
    () async {
      final source = _FakeTokenSource();
      final session = source.addSession();
      final registration = Completer<PlatformPushSubscriptionReceipt>();
      final requests = <PlatformPushSubscriptionRequest>[];
      final removed = <PlatformPushSubscriptionKey>[];
      final coordinator = PlatformPushRegistrationCoordinator(source: source);

      unawaited(
        coordinator.replace(
          deviceId: _deviceOne,
          register: (request) {
            requests.add(request);
            return registration.future;
          },
          unregister: (key) async {
            removed.add(key);
            return true;
          },
        ),
      );
      await session.waitUntilListened();
      session.emit(const PlatformPushToken(provider: 'fcm', token: 'token-1'));
      await _waitFor(() => requests.length == 1);

      final clearing = coordinator.clear();
      registration.complete(_receiptFor(requests.single));
      await clearing;

      expect(session.closed, isTrue);
      expect(removed, hasLength(1));
      expect(removed.single.deviceId, _deviceOne);
      expect(removed.single.provider, 'fcm');

      await coordinator.dispose();
    },
  );

  test(
    'replacement unregisters old binding and ignores old refreshes',
    () async {
      final source = _FakeTokenSource();
      final first = source.addSession();
      final second = source.addSession();
      final requests = <PlatformPushSubscriptionRequest>[];
      final removed = <PlatformPushSubscriptionKey>[];
      final coordinator = PlatformPushRegistrationCoordinator(source: source);

      unawaited(
        coordinator.replace(
          deviceId: _deviceOne,
          register: (request) async {
            requests.add(request);
            return _receiptFor(request);
          },
          unregister: (key) async {
            removed.add(key);
            return true;
          },
        ),
      );
      await first.waitUntilListened();
      first.emit(const PlatformPushToken(provider: 'fcm', token: 'token-1'));
      await _waitFor(() => requests.length == 1);

      unawaited(
        coordinator.replace(
          deviceId: _deviceTwo,
          register: (request) async {
            requests.add(request);
            return _receiptFor(request);
          },
          unregister: (key) async {
            removed.add(key);
            return true;
          },
        ),
      );
      await second.waitUntilListened();
      expect(first.closed, isTrue);
      expect(removed.single.deviceId, _deviceOne);

      first.emit(
        const PlatformPushToken(provider: 'fcm', token: 'stale-token'),
      );
      second.emit(const PlatformPushToken(provider: 'fcm', token: 'token-2'));
      await _waitFor(() => requests.length == 2);
      expect(requests.last.deviceId, _deviceTwo);
      expect(requests.last.token, 'token-2');

      await coordinator.dispose();
    },
  );

  test(
    'mute update during replacement never reaches the old binding',
    () async {
      final source = _FakeTokenSource();
      final first = source.addSession();
      final second = source.addSession();
      final requests = <PlatformPushSubscriptionRequest>[];
      final coordinator = PlatformPushRegistrationCoordinator(source: source);

      await coordinator.replace(
        deviceId: _deviceOne,
        register: (request) async {
          requests.add(request);
          return _receiptFor(request);
        },
        unregister: (_) async => true,
      );
      await first.waitUntilListened();
      first.emit(const PlatformPushToken(provider: 'fcm', token: 'token-1'));
      await _waitFor(() => requests.length == 1);

      final gate = Completer<void>();
      source.nextOpenGate = gate;
      final replacement = coordinator.replace(
        deviceId: _deviceTwo,
        register: (request) async {
          requests.add(request);
          return _receiptFor(request);
        },
        unregister: (_) async => true,
      );
      final muteUpdate = coordinator.updateMutedConversationIds(const [
        'conversation-new-account',
      ]);
      await source.waitUntilOpenStarted();
      expect(requests, hasLength(1));

      gate.complete();
      await replacement;
      await muteUpdate;
      await second.waitUntilListened();
      second.emit(const PlatformPushToken(provider: 'fcm', token: 'token-2'));
      await _waitFor(() => requests.length == 2);
      expect(requests.last.deviceId, _deviceTwo);
      expect(requests.last.mutedConversationIds, ['conversation-new-account']);

      await coordinator.dispose();
    },
  );

  test(
    'concurrent replacements leave only the latest binding active',
    () async {
      final source = _FakeTokenSource();
      final first = source.addSession();
      final second = source.addSession();
      final gate = Completer<void>();
      source.nextOpenGate = gate;
      final requests = <PlatformPushSubscriptionRequest>[];
      final coordinator = PlatformPushRegistrationCoordinator(source: source);

      final firstReplacement = coordinator.replace(
        deviceId: _deviceOne,
        register: (request) async {
          requests.add(request);
          return _receiptFor(request);
        },
        unregister: (_) async => true,
      );
      await source.waitUntilOpenStarted();
      final secondReplacement = coordinator.replace(
        deviceId: _deviceTwo,
        register: (request) async {
          requests.add(request);
          return _receiptFor(request);
        },
        unregister: (_) async => true,
      );
      gate.complete();
      await firstReplacement;
      await second.waitUntilListened();
      await secondReplacement;

      expect(first.closed, isTrue);
      first.emit(
        const PlatformPushToken(provider: 'fcm', token: 'stale-token'),
      );
      second.emit(const PlatformPushToken(provider: 'fcm', token: 'token-2'));
      await _waitFor(() => requests.isNotEmpty);
      expect(requests.single.deviceId, _deviceTwo);

      await coordinator.dispose();
    },
  );

  test('provider setup and stream failures stay isolated', () async {
    final source = _FakeTokenSource()..openFailure = StateError('offline');
    final errors = <Object>[];
    final coordinator = PlatformPushRegistrationCoordinator(
      source: source,
      onError: errors.add,
    );

    await coordinator.replace(
      deviceId: _deviceOne,
      register: (_) => throw StateError('must not register'),
      unregister: (_) async => true,
    );

    expect(errors, hasLength(1));
    expect(coordinator.hasActiveBinding, isFalse);
    await coordinator.dispose();
    expect(source.disposed, isTrue);
  });

  test('invalid registration receipt fails closed', () async {
    final source = _FakeTokenSource();
    final session = source.addSession();
    final errors = <Object>[];
    final removed = <PlatformPushSubscriptionKey>[];
    final coordinator = PlatformPushRegistrationCoordinator(
      source: source,
      onError: errors.add,
    );

    unawaited(
      coordinator.replace(
        deviceId: _deviceOne,
        register: (_) async => PlatformPushSubscriptionReceipt(
          deviceId: _deviceTwo,
          provider: 'fcm',
          registeredAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        unregister: (key) async {
          removed.add(key);
          return true;
        },
      ),
    );
    await session.waitUntilListened();
    session.emit(const PlatformPushToken(provider: 'fcm', token: 'token-1'));
    await _waitFor(() => errors.isNotEmpty);
    await coordinator.clear();

    expect(errors.single, isA<FormatException>());
    expect(removed, hasLength(1));
    expect(removed.single.deviceId, _deviceOne);
    await coordinator.dispose();
  });
}

PlatformPushSubscriptionReceipt _receiptFor(
  PlatformPushSubscriptionRequest request,
) => PlatformPushSubscriptionReceipt(
  deviceId: request.deviceId,
  provider: request.provider,
  registeredAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

const _deviceOne = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _deviceTwo = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE';

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition was not met before the test deadline.');
}

final class _FakeTokenSource implements PlatformPushTokenSource {
  final _sessions = <_FakeTokenSession>[];
  Object? openFailure;
  Completer<void>? nextOpenGate;
  Completer<void>? _openStarted;
  bool disposed = false;

  _FakeTokenSession addSession() {
    final session = _FakeTokenSession();
    _sessions.add(session);
    return session;
  }

  @override
  Future<PlatformPushTokenSession?> open() async {
    final gate = nextOpenGate;
    nextOpenGate = null;
    if (gate != null) {
      _openStarted = Completer<void>()..complete();
      await gate.future;
    }
    final failure = openFailure;
    if (failure != null) throw failure;
    if (_sessions.isEmpty) return null;
    return _sessions.removeAt(0);
  }

  Future<void> waitUntilOpenStarted() async {
    while (_openStarted == null) {
      await Future<void>.delayed(Duration.zero);
    }
    await _openStarted!.future;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    for (final session in _sessions) {
      await session.close();
    }
    _sessions.clear();
  }
}

final class _FakeTokenSession implements PlatformPushTokenSession {
  final _controller = StreamController<PlatformPushToken>();
  final _listened = Completer<void>();
  bool hasListener = false;
  bool closed = false;

  _FakeTokenSession() {
    _controller.onListen = () {
      hasListener = true;
      _listened.complete();
    };
  }

  @override
  Stream<PlatformPushToken> get tokens => _controller.stream;

  Future<void> waitUntilListened() => _listened.future;

  void emit(PlatformPushToken token) {
    if (!closed) _controller.add(token);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    final closedFuture = _controller.close();
    if (hasListener) await closedFuture;
  }
}

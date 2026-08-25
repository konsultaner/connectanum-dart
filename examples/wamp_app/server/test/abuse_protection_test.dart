import 'dart:async';

import 'package:test/test.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  test(
    'per-account budgets are isolated and refill deterministically',
    () async {
      final clock = _FakeClock();
      final guard = _guard(
        clock,
        controlGlobal: _policy(requests: 10),
        controlPerAccount: _policy(requests: 1),
      );

      await guard.runForAccount(
        'alice',
        WampAppOperationClass.control,
        () async {},
      );
      await expectLater(
        guard.runForAccount(
          'alice',
          WampAppOperationClass.control,
          () async {},
        ),
        throwsA(
          isA<WampAppRateLimitExceeded>().having(
            (error) => error.retryAfter,
            'retryAfter',
            const Duration(seconds: 10),
          ),
        ),
      );
      await guard.runForAccount(
        'bob',
        WampAppOperationClass.control,
        () async {},
      );

      clock.elapse(const Duration(seconds: 10));
      await guard.runForAccount(
        'alice',
        WampAppOperationClass.control,
        () async {},
      );
    },
  );

  test('global budget spans accounts', () async {
    final guard = _guard(
      _FakeClock(),
      controlGlobal: _policy(requests: 2),
      controlPerAccount: _policy(requests: 2),
    );

    await guard.runForAccount(
      'alice',
      WampAppOperationClass.control,
      () async {},
    );
    await guard.runForAccount(
      'bob',
      WampAppOperationClass.control,
      () async {},
    );
    await expectLater(
      guard.runForAccount(
        'charlie',
        WampAppOperationClass.control,
        () async {},
      ),
      throwsA(isA<WampAppRateLimitExceeded>()),
    );
  });

  test('global and per-account concurrency limits fail closed', () async {
    final guard = _guard(
      _FakeClock(),
      controlGlobal: _policy(requests: 10, concurrent: 2),
      controlPerAccount: _policy(requests: 10, concurrent: 1),
    );
    final aliceRelease = Completer<void>();
    final bobRelease = Completer<void>();
    final alice = guard.runForAccount(
      'alice',
      WampAppOperationClass.control,
      () => aliceRelease.future,
    );

    await expectLater(
      guard.runForAccount('alice', WampAppOperationClass.control, () async {}),
      throwsA(isA<WampAppRateLimitExceeded>()),
    );
    final bob = guard.runForAccount(
      'bob',
      WampAppOperationClass.control,
      () => bobRelease.future,
    );
    await expectLater(
      guard.runForAccount(
        'charlie',
        WampAppOperationClass.control,
        () async {},
      ),
      throwsA(isA<WampAppRateLimitExceeded>()),
    );

    aliceRelease.complete();
    bobRelease.complete();
    await Future.wait([alice, bob]);
  });

  test(
    'failed actions release concurrency but consume their request',
    () async {
      final guard = _guard(
        _FakeClock(),
        controlGlobal: _policy(requests: 2, concurrent: 1),
        controlPerAccount: _policy(requests: 2, concurrent: 1),
      );

      await expectLater(
        guard.runForAccount<void>(
          'alice',
          WampAppOperationClass.control,
          () => throw StateError('expected test failure'),
        ),
        throwsStateError,
      );
      await guard.runForAccount(
        'alice',
        WampAppOperationClass.control,
        () async {},
      );
      await expectLater(
        guard.runForAccount(
          'alice',
          WampAppOperationClass.control,
          () async {},
        ),
        throwsA(isA<WampAppRateLimitExceeded>()),
      );
    },
  );

  test('tracked-account capacity evicts idle entries only', () async {
    final guard = _guard(
      _FakeClock(),
      controlGlobal: _policy(requests: 10, concurrent: 10),
      controlPerAccount: _policy(requests: 10),
      maxTrackedAccounts: 1,
    );
    final release = Completer<void>();
    final alice = guard.runForAccount(
      'alice',
      WampAppOperationClass.control,
      () => release.future,
    );

    await expectLater(
      guard.runForAccount('bob', WampAppOperationClass.control, () async {}),
      throwsA(isA<WampAppRateLimitExceeded>()),
    );
    release.complete();
    await alice;
    await guard.runForAccount(
      'bob',
      WampAppOperationClass.control,
      () async {},
    );
    expect(guard.trackedAccountCount, 1);
  });

  test('registration, control, and transfer budgets are independent', () async {
    final guard = _guard(
      _FakeClock(),
      registration: _policy(requests: 1),
      controlGlobal: _policy(requests: 1),
      controlPerAccount: _policy(requests: 1),
      transferGlobal: _policy(requests: 1),
      transferPerAccount: _policy(requests: 1),
    );

    await guard.runRegistration(() async {});
    await guard.runForAccount(
      'alice',
      WampAppOperationClass.control,
      () async {},
    );
    await guard.runForAccount(
      'alice',
      WampAppOperationClass.transfer,
      () async {},
    );
    await expectLater(
      guard.runRegistration(() async {}),
      throwsA(isA<WampAppRateLimitExceeded>()),
    );
    await expectLater(
      guard.runForAccount('alice', WampAppOperationClass.control, () async {}),
      throwsA(isA<WampAppRateLimitExceeded>()),
    );
    await expectLater(
      guard.runForAccount('alice', WampAppOperationClass.transfer, () async {}),
      throwsA(isA<WampAppRateLimitExceeded>()),
    );
  });

  test('registration concurrency is globally bounded', () async {
    final guard = _guard(
      _FakeClock(),
      registration: _policy(requests: 10, concurrent: 1),
    );
    final release = Completer<void>();
    final first = guard.runRegistration(() => release.future);

    await expectLater(
      guard.runRegistration(() async {}),
      throwsA(isA<WampAppRateLimitExceeded>()),
    );
    release.complete();
    await first;
    await guard.runRegistration(() async {});
  });

  test('rate-limit errors redact policy state', () {
    const error = WampAppRateLimitExceeded(Duration(milliseconds: 1));

    expect(error.retryAfterMilliseconds, 1);
    expect(error.toString(), isNot(contains('1')));
  });
}

WampAppAbuseGuard _guard(
  _FakeClock clock, {
  WampAppRateLimitPolicy? registration,
  WampAppRateLimitPolicy? controlGlobal,
  WampAppRateLimitPolicy? controlPerAccount,
  WampAppRateLimitPolicy? transferGlobal,
  WampAppRateLimitPolicy? transferPerAccount,
  int maxTrackedAccounts = 16,
}) {
  return WampAppAbuseGuard(
    WampAppAbuseProtectionConfig(
      registration: registration ?? _policy(requests: 10),
      controlGlobal: controlGlobal ?? _policy(requests: 10),
      controlPerAccount: controlPerAccount ?? _policy(requests: 10),
      transferGlobal: transferGlobal ?? _policy(requests: 10),
      transferPerAccount: transferPerAccount ?? _policy(requests: 10),
      maxTrackedAccounts: maxTrackedAccounts,
    ),
    monotonicMicroseconds: clock.call,
  );
}

WampAppRateLimitPolicy _policy({required int requests, int concurrent = 4}) {
  return WampAppRateLimitPolicy(
    maxRequests: requests,
    window: const Duration(seconds: 10),
    maxConcurrent: concurrent,
  );
}

final class _FakeClock {
  int _microseconds = 0;

  int call() => _microseconds;

  void elapse(Duration duration) {
    _microseconds += duration.inMicroseconds;
  }
}

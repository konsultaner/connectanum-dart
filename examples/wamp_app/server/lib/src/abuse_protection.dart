import 'dart:math' as math;

enum WampAppOperationClass { control, transfer }

final class WampAppRateLimitPolicy {
  const WampAppRateLimitPolicy({
    required this.maxRequests,
    required this.window,
    required this.maxConcurrent,
  });

  final int maxRequests;
  final Duration window;
  final int maxConcurrent;

  void validate(String name) {
    if (maxRequests <= 0 || maxRequests > 1000000000) {
      throw FormatException(
        '$name.max_requests must be between 1 and 1000000000.',
      );
    }
    if (window < const Duration(seconds: 1) ||
        window > const Duration(days: 1)) {
      throw FormatException(
        '$name.window must be between 1 and 86400 seconds.',
      );
    }
    if (maxConcurrent <= 0 || maxConcurrent > 1000000) {
      throw FormatException(
        '$name.max_concurrent must be between 1 and 1000000.',
      );
    }
  }
}

final class WampAppAbuseProtectionConfig {
  const WampAppAbuseProtectionConfig({
    this.registration = defaultRegistration,
    this.controlGlobal = defaultControlGlobal,
    this.controlPerAccount = defaultControlPerAccount,
    this.transferGlobal = defaultTransferGlobal,
    this.transferPerAccount = defaultTransferPerAccount,
    this.maxTrackedAccounts = 4096,
  });

  static const defaultRegistration = WampAppRateLimitPolicy(
    maxRequests: 20,
    window: Duration(minutes: 1),
    maxConcurrent: 2,
  );
  static const defaultControlGlobal = WampAppRateLimitPolicy(
    maxRequests: 30000,
    window: Duration(minutes: 1),
    maxConcurrent: 256,
  );
  static const defaultControlPerAccount = WampAppRateLimitPolicy(
    maxRequests: 2400,
    window: Duration(minutes: 1),
    maxConcurrent: 16,
  );
  static const defaultTransferGlobal = WampAppRateLimitPolicy(
    maxRequests: 120000,
    window: Duration(minutes: 1),
    maxConcurrent: 512,
  );
  static const defaultTransferPerAccount = WampAppRateLimitPolicy(
    maxRequests: 12000,
    window: Duration(minutes: 1),
    maxConcurrent: 32,
  );

  final WampAppRateLimitPolicy registration;
  final WampAppRateLimitPolicy controlGlobal;
  final WampAppRateLimitPolicy controlPerAccount;
  final WampAppRateLimitPolicy transferGlobal;
  final WampAppRateLimitPolicy transferPerAccount;
  final int maxTrackedAccounts;

  void validate() {
    registration.validate('abuse_protection.registration');
    controlGlobal.validate('abuse_protection.control.global');
    controlPerAccount.validate('abuse_protection.control.per_account');
    transferGlobal.validate('abuse_protection.transfer.global');
    transferPerAccount.validate('abuse_protection.transfer.per_account');
    if (maxTrackedAccounts <= 0 || maxTrackedAccounts > 1000000) {
      throw const FormatException(
        'abuse_protection.max_tracked_accounts must be between 1 and 1000000.',
      );
    }
  }
}

final class WampAppRateLimitExceeded implements Exception {
  const WampAppRateLimitExceeded(this.retryAfter);

  final Duration retryAfter;

  int get retryAfterMilliseconds => math.max(1, retryAfter.inMilliseconds);

  @override
  String toString() => 'WampAppRateLimitExceeded([redacted])';
}

final class WampAppAbuseGuard {
  factory WampAppAbuseGuard(
    WampAppAbuseProtectionConfig config, {
    int Function()? monotonicMicroseconds,
  }) {
    config.validate();
    return WampAppAbuseGuard._(
      config,
      monotonicMicroseconds ?? _stopwatchClock(),
    );
  }

  WampAppAbuseGuard._(
    WampAppAbuseProtectionConfig config,
    int Function() monotonicMicroseconds,
  ) : _registration = _CompositeRateLimiter(
        globalPolicy: config.registration,
        maxTrackedKeys: 0,
        monotonicMicroseconds: monotonicMicroseconds,
      ),
      _control = _CompositeRateLimiter(
        globalPolicy: config.controlGlobal,
        perKeyPolicy: config.controlPerAccount,
        maxTrackedKeys: config.maxTrackedAccounts,
        monotonicMicroseconds: monotonicMicroseconds,
      ),
      _transfer = _CompositeRateLimiter(
        globalPolicy: config.transferGlobal,
        perKeyPolicy: config.transferPerAccount,
        maxTrackedKeys: config.maxTrackedAccounts,
        monotonicMicroseconds: monotonicMicroseconds,
      );

  final _CompositeRateLimiter _registration;
  final _CompositeRateLimiter _control;
  final _CompositeRateLimiter _transfer;

  Future<T> runRegistration<T>(Future<T> Function() action) {
    return _registration.run(null, action);
  }

  Future<T> runForAccount<T>(
    String account,
    WampAppOperationClass operationClass,
    Future<T> Function() action,
  ) {
    if (account.isEmpty) {
      throw ArgumentError.value(account, 'account', 'must not be empty');
    }
    final limiter = switch (operationClass) {
      WampAppOperationClass.control => _control,
      WampAppOperationClass.transfer => _transfer,
    };
    return limiter.run(account, action);
  }

  int get trackedAccountCount =>
      _control.trackedKeyCount + _transfer.trackedKeyCount;

  static int Function() _stopwatchClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsedMicroseconds;
  }
}

final class _CompositeRateLimiter {
  _CompositeRateLimiter({
    required WampAppRateLimitPolicy globalPolicy,
    WampAppRateLimitPolicy? perKeyPolicy,
    required this.maxTrackedKeys,
    required this.monotonicMicroseconds,
  }) : _globalPolicy = globalPolicy,
       _perKeyPolicy = perKeyPolicy,
       _global = _RateLimitBucket(
         tokens: globalPolicy.maxRequests.toDouble(),
         lastRefillMicroseconds: monotonicMicroseconds(),
       );

  static const _concurrencyRetry = Duration(milliseconds: 100);

  final WampAppRateLimitPolicy _globalPolicy;
  final WampAppRateLimitPolicy? _perKeyPolicy;
  final int maxTrackedKeys;
  final int Function() monotonicMicroseconds;
  final _RateLimitBucket _global;
  final Map<String, _RateLimitBucket> _perKey = {};

  int get trackedKeyCount => _perKey.length;

  Future<T> run<T>(String? key, Future<T> Function() action) async {
    final now = monotonicMicroseconds();
    _refill(_global, _globalPolicy, now);
    if (_global.inFlight >= _globalPolicy.maxConcurrent) {
      throw const WampAppRateLimitExceeded(_concurrencyRetry);
    }
    final globalRetry = _tokenRetryAfter(_global, _globalPolicy);
    if (globalRetry != null) {
      throw WampAppRateLimitExceeded(globalRetry);
    }

    final perKeyPolicy = _perKeyPolicy;
    final perKeyBucket = perKeyPolicy == null
        ? null
        : _bucketFor(key!, perKeyPolicy, now);
    if (perKeyBucket != null) {
      _refill(perKeyBucket, perKeyPolicy!, now);
      if (perKeyBucket.inFlight >= perKeyPolicy.maxConcurrent) {
        throw const WampAppRateLimitExceeded(_concurrencyRetry);
      }
      final perKeyRetry = _tokenRetryAfter(perKeyBucket, perKeyPolicy);
      if (perKeyRetry != null) {
        throw WampAppRateLimitExceeded(perKeyRetry);
      }
    }

    _global
      ..tokens -= 1
      ..inFlight += 1
      ..lastSeenMicroseconds = now;
    if (perKeyBucket != null) {
      perKeyBucket
        ..tokens -= 1
        ..inFlight += 1
        ..lastSeenMicroseconds = now;
    }
    try {
      return await action();
    } finally {
      _global.inFlight -= 1;
      if (perKeyBucket != null) {
        perKeyBucket.inFlight -= 1;
      }
    }
  }

  _RateLimitBucket _bucketFor(
    String key,
    WampAppRateLimitPolicy policy,
    int now,
  ) {
    final existing = _perKey[key];
    if (existing != null) return existing;
    if (_perKey.length >= maxTrackedKeys) {
      String? oldestKey;
      var oldestSeen = now;
      for (final entry in _perKey.entries) {
        final bucket = entry.value;
        if (bucket.inFlight == 0 && bucket.lastSeenMicroseconds <= oldestSeen) {
          oldestKey = entry.key;
          oldestSeen = bucket.lastSeenMicroseconds;
        }
      }
      if (oldestKey == null) {
        throw WampAppRateLimitExceeded(policy.window);
      }
      _perKey.remove(oldestKey);
    }
    return _perKey[key] = _RateLimitBucket(
      tokens: policy.maxRequests.toDouble(),
      lastRefillMicroseconds: now,
      lastSeenMicroseconds: now,
    );
  }

  static void _refill(
    _RateLimitBucket bucket,
    WampAppRateLimitPolicy policy,
    int now,
  ) {
    final elapsed = now - bucket.lastRefillMicroseconds;
    if (elapsed <= 0) return;
    final refill = elapsed * policy.maxRequests / policy.window.inMicroseconds;
    bucket.tokens = math.min(
      policy.maxRequests.toDouble(),
      bucket.tokens + refill,
    );
    bucket.lastRefillMicroseconds = now;
  }

  static Duration? _tokenRetryAfter(
    _RateLimitBucket bucket,
    WampAppRateLimitPolicy policy,
  ) {
    if (bucket.tokens >= 1) return null;
    final missing = 1 - bucket.tokens;
    final microseconds = math.max(
      1,
      (missing * policy.window.inMicroseconds / policy.maxRequests).ceil(),
    );
    return Duration(microseconds: microseconds);
  }
}

final class _RateLimitBucket {
  _RateLimitBucket({
    required this.tokens,
    required this.lastRefillMicroseconds,
    this.lastSeenMicroseconds = 0,
  });

  double tokens;
  int lastRefillMicroseconds;
  int lastSeenMicroseconds;
  int inFlight = 0;
}

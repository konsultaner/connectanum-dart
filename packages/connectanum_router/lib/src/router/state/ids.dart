/// Generates WAMP-compliant identifiers in the range 1..2^53-1 (safe ints).
class WampIdGenerator {
  WampIdGenerator({
    this.min = 1,
    this.max = 0x1FFFFFFFFFFFFF, // 2^53-1
  }) : _current = min - 1 {
    if (min <= 0 || max <= min) {
      throw ArgumentError('Invalid id range [$min, $max]');
    }
  }

  final int min;
  final int max;
  int _current;

  int next() {
    if (_current >= max) {
      _current = min;
    } else {
      _current += 1;
      if (_current > max) {
        _current = min;
      }
    }
    return _current;
  }
}

/// Registry holding generators for the various WAMP id domains.
class WampIdAllocatorRegistry {
  WampIdAllocatorRegistry({
    WampIdGenerator? sessionIds,
    WampIdGenerator? subscriptionIds,
    WampIdGenerator? registrationIds,
    WampIdGenerator? invocationIds,
    WampIdGenerator? publicationIds,
    WampIdGenerator? requestIds,
  })  : session = sessionIds ?? WampIdGenerator(),
        subscription = subscriptionIds ?? WampIdGenerator(),
        registration = registrationIds ?? WampIdGenerator(),
        invocation = invocationIds ?? WampIdGenerator(),
        publication = publicationIds ?? WampIdGenerator(),
        request = requestIds ?? WampIdGenerator();

  final WampIdGenerator session;
  final WampIdGenerator subscription;
  final WampIdGenerator registration;
  final WampIdGenerator invocation;
  final WampIdGenerator publication;
  final WampIdGenerator request;
}

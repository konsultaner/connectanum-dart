import 'dart:async';

import 'package:connectanum_core/connectanum_core.dart' as wamp;

import '../protocol/session.dart';

/// A session-scoped, race-safe view of the standard WAMP Meta API state.
///
/// Lifecycle subscriptions are established before the initial snapshots are
/// read. Events received during hydration are replayed in receive order, so a
/// create or delete racing a Meta API call cannot leave the cache stale.
final class WampMetaStateCache {
  WampMetaStateCache._(this._session, this._maxConcurrentQueries);

  static const _eventTopics = <String>{
    'wamp.session.on_join',
    'wamp.session.on_leave',
    'wamp.registration.on_create',
    'wamp.registration.on_register',
    'wamp.registration.on_unregister',
    'wamp.registration.on_delete',
    'wamp.subscription.on_create',
    'wamp.subscription.on_subscribe',
    'wamp.subscription.on_unsubscribe',
    'wamp.subscription.on_delete',
  };

  final Session _session;
  final int _maxConcurrentQueries;
  final List<wamp.Subscribed> _eventSubscriptions = <wamp.Subscribed>[];
  final List<_BufferedMetaEvent> _bufferedEvents = <_BufferedMetaEvent>[];
  final Map<int, WampSessionMeta> _sessions = <int, WampSessionMeta>{};
  final Map<int, WampRegistrationMeta> _registrations =
      <int, WampRegistrationMeta>{};
  final Map<int, WampSubscriptionMeta> _subscriptions =
      <int, WampSubscriptionMeta>{};
  final StreamController<WampMetaStateSnapshot> _changes =
      StreamController<WampMetaStateSnapshot>.broadcast(sync: true);

  WampMetaStateSnapshot _snapshot = WampMetaStateSnapshot.empty();
  bool _hydrating = true;
  bool _closed = false;

  /// Starts a cache for an established [session].
  ///
  /// [maxConcurrentQueries] bounds the number of concurrent `get` and member
  /// list calls used to hydrate large realms.
  static Future<WampMetaStateCache> start(
    Session session, {
    int maxConcurrentQueries = 16,
  }) async {
    if (maxConcurrentQueries < 1) {
      throw ArgumentError.value(
        maxConcurrentQueries,
        'maxConcurrentQueries',
        'must be at least 1',
      );
    }
    if (!session.isConnected()) {
      throw StateError('The WAMP session must be connected');
    }

    final cache = WampMetaStateCache._(session, maxConcurrentQueries);
    cache._watchDisconnect();
    try {
      await cache._initialize();
      return cache;
    } catch (error, stackTrace) {
      await cache._dispose(releaseSubscriptions: true);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// The latest immutable state snapshot.
  WampMetaStateSnapshot get snapshot => _snapshot;

  /// Emits a new immutable snapshot after each valid lifecycle update.
  Stream<WampMetaStateSnapshot> get changes => _changes.stream;

  bool get isClosed => _closed;

  Future<void> _initialize() async {
    for (final topic in _eventTopics) {
      final subscribed = await _session.subscribeHandler(
        topic,
        (event) => _handleEvent(topic, event),
      );
      _eventSubscriptions.add(subscribed);
    }

    final state = await _readInitialState();
    if (_closed) {
      throw StateError('The WAMP session disconnected during Meta hydration');
    }
    _sessions.addAll(state.sessions);
    _registrations.addAll(state.registrations);
    _subscriptions.addAll(state.subscriptions);
    for (final event in _bufferedEvents) {
      _applyEvent(event);
    }
    _bufferedEvents.clear();
    _hydrating = false;
    _publishSnapshot();
  }

  void _watchDisconnect() {
    unawaited(
      _session.onDisconnect.then<void>(
        (_) => _dispose(releaseSubscriptions: false),
        onError: (_, _) => _dispose(releaseSubscriptions: false),
      ),
    );
  }

  Future<_MutableMetaState> _readInitialState() async {
    final sessionIds = _intListFromResult(
      await _session.callSingle('wamp.session.list'),
      'wamp.session.list',
    );
    final registrationIds = _groupedIdsFromResult(
      await _session.callSingle('wamp.registration.list'),
      'wamp.registration.list',
    );
    final subscriptionIds = _groupedIdsFromResult(
      await _session.callSingle('wamp.subscription.list'),
      'wamp.subscription.list',
    );

    final sessions = await _loadConcurrently<WampSessionMeta>(
      sessionIds,
      _loadSession,
    );
    final registrations = await _loadConcurrently<WampRegistrationMeta>(
      registrationIds,
      _loadRegistration,
    );
    final subscriptions = await _loadConcurrently<WampSubscriptionMeta>(
      subscriptionIds,
      _loadSubscription,
    );
    return _MutableMetaState(
      sessions: {for (final value in sessions) value.id: value},
      registrations: {for (final value in registrations) value.id: value},
      subscriptions: {for (final value in subscriptions) value.id: value},
    );
  }

  Future<List<T>> _loadConcurrently<T>(
    List<int> ids,
    Future<T?> Function(int id) load,
  ) async {
    if (ids.isEmpty) {
      return <T>[];
    }
    final results = List<T?>.filled(ids.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < ids.length) {
        final index = nextIndex++;
        results[index] = await load(ids[index]);
      }
    }

    final workerCount = ids.length < _maxConcurrentQueries
        ? ids.length
        : _maxConcurrentQueries;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    return <T>[
      for (final value in results) ?value,
    ];
  }

  Future<WampSessionMeta?> _loadSession(int id) async {
    try {
      final result = await _session.callSingle(
        'wamp.session.get',
        arguments: [id],
      );
      return WampSessionMeta.fromDetails(
        id,
        _mapFromResult(result, 'wamp.session.get'),
      );
    } on wamp.Error catch (error) {
      if (error.error == wamp.Error.noSuchSession) {
        return null;
      }
      rethrow;
    }
  }

  Future<WampRegistrationMeta?> _loadRegistration(int id) async {
    try {
      final values = await Future.wait<wamp.Result>([
        _session.callSingle('wamp.registration.get', arguments: [id]),
        _session.callSingle(
          'wamp.registration.list_callees',
          arguments: [id],
        ),
      ]);
      return WampRegistrationMeta.fromDetails(
        id,
        _mapFromResult(values[0], 'wamp.registration.get'),
        callees: _intListFromResult(
          values[1],
          'wamp.registration.list_callees',
        ),
      );
    } on wamp.Error catch (error) {
      if (error.error == wamp.Error.noSuchRegistration) {
        return null;
      }
      rethrow;
    }
  }

  Future<WampSubscriptionMeta?> _loadSubscription(int id) async {
    try {
      final values = await Future.wait<wamp.Result>([
        _session.callSingle('wamp.subscription.get', arguments: [id]),
        _session.callSingle(
          'wamp.subscription.list_subscribers',
          arguments: [id],
        ),
      ]);
      return WampSubscriptionMeta.fromDetails(
        id,
        _mapFromResult(values[0], 'wamp.subscription.get'),
        subscribers: _intListFromResult(
          values[1],
          'wamp.subscription.list_subscribers',
        ),
      );
    } on wamp.Error catch (error) {
      if (error.error == wamp.Error.noSuchSubscription) {
        return null;
      }
      rethrow;
    }
  }

  void _handleEvent(String topic, wamp.Event event) {
    if (_closed) {
      return;
    }
    final buffered = _BufferedMetaEvent(
      topic,
      List<dynamic>.of(event.arguments ?? const <dynamic>[]),
    );
    if (_hydrating) {
      _bufferedEvents.add(buffered);
      return;
    }
    if (_applyEvent(buffered)) {
      _publishSnapshot();
    }
  }

  bool _applyEvent(_BufferedMetaEvent event) {
    final arguments = event.arguments;
    switch (event.topic) {
      case 'wamp.session.on_join':
        final details = _stringMap(arguments.firstOrNull);
        final id = _asInt(details?['session'] ?? details?['id']);
        if (details == null || id == null) {
          return false;
        }
        _sessions[id] = WampSessionMeta.fromDetails(id, details);
        return true;
      case 'wamp.session.on_leave':
        final id = _asInt(arguments.firstOrNull);
        if (id == null) {
          return false;
        }
        _sessions.remove(id);
        _removeSessionMemberships(id);
        return true;
      case 'wamp.registration.on_create':
        final details = _stringMap(_argumentAt(arguments, 1));
        final id = _asInt(details?['id']);
        if (details == null || id == null) {
          return false;
        }
        _registrations[id] = WampRegistrationMeta.fromDetails(id, details);
        return true;
      case 'wamp.registration.on_register':
        return _updateRegistrationMember(arguments, add: true);
      case 'wamp.registration.on_unregister':
        return _updateRegistrationMember(arguments, add: false);
      case 'wamp.registration.on_delete':
        final id = _asInt(_argumentAt(arguments, 1));
        return id != null && _registrations.remove(id) != null;
      case 'wamp.subscription.on_create':
        final details = _stringMap(_argumentAt(arguments, 1));
        final id = _asInt(details?['id']);
        if (details == null || id == null) {
          return false;
        }
        _subscriptions[id] = WampSubscriptionMeta.fromDetails(id, details);
        return true;
      case 'wamp.subscription.on_subscribe':
        return _updateSubscriptionMember(arguments, add: true);
      case 'wamp.subscription.on_unsubscribe':
        return _updateSubscriptionMember(arguments, add: false);
      case 'wamp.subscription.on_delete':
        final id = _asInt(_argumentAt(arguments, 1));
        return id != null && _subscriptions.remove(id) != null;
    }
    return false;
  }

  bool _updateRegistrationMember(List<dynamic> arguments, {required bool add}) {
    final sessionId = _asInt(arguments.firstOrNull);
    final registrationId = _asInt(_argumentAt(arguments, 1));
    final registration = _registrations[registrationId];
    if (sessionId == null || registrationId == null || registration == null) {
      return false;
    }
    final callees = registration.callees.toSet();
    final changed = add ? callees.add(sessionId) : callees.remove(sessionId);
    if (changed) {
      _registrations[registrationId] = registration.copyWith(callees: callees);
    }
    return changed;
  }

  bool _updateSubscriptionMember(List<dynamic> arguments, {required bool add}) {
    final sessionId = _asInt(arguments.firstOrNull);
    final subscriptionId = _asInt(_argumentAt(arguments, 1));
    final subscription = _subscriptions[subscriptionId];
    if (sessionId == null || subscriptionId == null || subscription == null) {
      return false;
    }
    final subscribers = subscription.subscribers.toSet();
    final changed = add
        ? subscribers.add(sessionId)
        : subscribers.remove(sessionId);
    if (changed) {
      _subscriptions[subscriptionId] = subscription.copyWith(
        subscribers: subscribers,
      );
    }
    return changed;
  }

  void _removeSessionMemberships(int sessionId) {
    for (final entry in _registrations.entries.toList(growable: false)) {
      if (entry.value.callees.contains(sessionId)) {
        final callees = entry.value.callees.toSet()..remove(sessionId);
        _registrations[entry.key] = entry.value.copyWith(callees: callees);
      }
    }
    for (final entry in _subscriptions.entries.toList(growable: false)) {
      if (entry.value.subscribers.contains(sessionId)) {
        final subscribers = entry.value.subscribers.toSet()..remove(sessionId);
        _subscriptions[entry.key] = entry.value.copyWith(
          subscribers: subscribers,
        );
      }
    }
  }

  void _publishSnapshot() {
    _snapshot = WampMetaStateSnapshot._(
      sessions: _sessions,
      registrations: _registrations,
      subscriptions: _subscriptions,
    );
    if (!_closed) {
      _changes.add(_snapshot);
    }
  }

  /// Releases the lifecycle subscriptions and closes the change stream.
  Future<void> close() => _dispose(releaseSubscriptions: true);

  Future<void> _dispose({required bool releaseSubscriptions}) async {
    if (_closed) {
      return;
    }
    _closed = true;
    _hydrating = false;
    _bufferedEvents.clear();
    if (releaseSubscriptions && _session.isConnected()) {
      for (final subscribed in _eventSubscriptions.reversed) {
        try {
          await _session.releaseSubscription(subscribed);
        } catch (_) {
          // A concurrent session shutdown already releases router ownership.
        }
      }
    }
    _eventSubscriptions.clear();
    await _changes.close();
  }
}

/// An immutable snapshot of visible WAMP Meta API state.
final class WampMetaStateSnapshot {
  WampMetaStateSnapshot._({
    required Map<int, WampSessionMeta> sessions,
    required Map<int, WampRegistrationMeta> registrations,
    required Map<int, WampSubscriptionMeta> subscriptions,
  }) : sessions = Map<int, WampSessionMeta>.unmodifiable(sessions),
       registrations = Map<int, WampRegistrationMeta>.unmodifiable(
         registrations,
       ),
       subscriptions = Map<int, WampSubscriptionMeta>.unmodifiable(
         subscriptions,
       );

  factory WampMetaStateSnapshot.empty() => WampMetaStateSnapshot._(
    sessions: const <int, WampSessionMeta>{},
    registrations: const <int, WampRegistrationMeta>{},
    subscriptions: const <int, WampSubscriptionMeta>{},
  );

  final Map<int, WampSessionMeta> sessions;
  final Map<int, WampRegistrationMeta> registrations;
  final Map<int, WampSubscriptionMeta> subscriptions;
}

/// Standard `wamp.session.get` details retained by the cache.
final class WampSessionMeta {
  WampSessionMeta.fromDetails(this.id, Map<String, dynamic> details)
    : details = _immutableDetails(details);

  final int id;
  final Map<String, Object?> details;

  String? get authId => details['authid'] as String?;
  String? get authRole => details['authrole'] as String?;
  String? get authMethod => details['authmethod'] as String?;
  String? get authProvider => details['authprovider'] as String?;
}

/// Standard registration details plus the current callee session IDs.
final class WampRegistrationMeta {
  WampRegistrationMeta.fromDetails(
    this.id,
    Map<String, dynamic> details, {
    Iterable<int> callees = const <int>[],
  }) : details = _immutableDetails(details),
       callees = Set<int>.unmodifiable(callees);

  WampRegistrationMeta._(
    this.id,
    this.details,
    Iterable<int> callees,
  ) : callees = Set<int>.unmodifiable(callees);

  final int id;
  final Map<String, Object?> details;
  final Set<int> callees;

  String? get procedure => details['uri'] as String?;
  String? get match => details['match'] as String?;
  String? get invoke => details['invoke'] as String?;

  WampRegistrationMeta copyWith({required Iterable<int> callees}) =>
      WampRegistrationMeta._(id, details, callees);
}

/// Standard subscription details plus the current subscriber session IDs.
final class WampSubscriptionMeta {
  WampSubscriptionMeta.fromDetails(
    this.id,
    Map<String, dynamic> details, {
    Iterable<int> subscribers = const <int>[],
  }) : details = _immutableDetails(details),
       subscribers = Set<int>.unmodifiable(subscribers);

  WampSubscriptionMeta._(
    this.id,
    this.details,
    Iterable<int> subscribers,
  ) : subscribers = Set<int>.unmodifiable(subscribers);

  final int id;
  final Map<String, Object?> details;
  final Set<int> subscribers;

  String? get topic => details['uri'] as String?;
  String? get match => details['match'] as String?;

  WampSubscriptionMeta copyWith({required Iterable<int> subscribers}) =>
      WampSubscriptionMeta._(id, details, subscribers);
}

final class _MutableMetaState {
  const _MutableMetaState({
    required this.sessions,
    required this.registrations,
    required this.subscriptions,
  });

  final Map<int, WampSessionMeta> sessions;
  final Map<int, WampRegistrationMeta> registrations;
  final Map<int, WampSubscriptionMeta> subscriptions;
}

final class _BufferedMetaEvent {
  const _BufferedMetaEvent(this.topic, this.arguments);

  final String topic;
  final List<dynamic> arguments;
}

Map<String, Object?> _immutableDetails(Map<String, dynamic> details) =>
    Map<String, Object?>.unmodifiable(
      details.map((key, value) => MapEntry(key, _freezeValue(value))),
    );

Object? _freezeValue(Object? value) {
  if (value is Map) {
    return Map<Object?, Object?>.unmodifiable(
      value.map((key, child) => MapEntry(key, _freezeValue(child))),
    );
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeValue));
  }
  if (value is Set) {
    return Set<Object?>.unmodifiable(value.map(_freezeValue));
  }
  return value;
}

List<int> _groupedIdsFromResult(wamp.Result result, String procedure) {
  final grouped = _mapFromResult(result, procedure);
  final ids = <int>[];
  for (final policy in const ['exact', 'prefix', 'wildcard']) {
    final value = grouped[policy];
    if (value is! List) {
      throw FormatException('$procedure returned an invalid $policy list');
    }
    ids.addAll(value.map((value) => _requireInt(value, procedure)));
  }
  return ids;
}

List<int> _intListFromResult(wamp.Result result, String procedure) {
  final value = _singleResultValue(result, procedure);
  if (value is! List) {
    throw FormatException('$procedure did not return a list');
  }
  return value.map((value) => _requireInt(value, procedure)).toList();
}

Map<String, dynamic> _mapFromResult(wamp.Result result, String procedure) {
  final value = _singleResultValue(result, procedure);
  final mapped = _stringMap(value);
  if (mapped == null) {
    throw FormatException('$procedure did not return a string-keyed map');
  }
  return mapped;
}

Object? _singleResultValue(wamp.Result result, String procedure) {
  final arguments = result.arguments;
  if (arguments != null && arguments.isNotEmpty) {
    return arguments.first;
  }
  final keywords = result.argumentsKeywords;
  if (keywords != null && keywords.isNotEmpty) {
    return keywords;
  }
  throw FormatException('$procedure returned no result value');
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      return null;
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

int _requireInt(Object? value, String procedure) {
  final parsed = _asInt(value);
  if (parsed == null) {
    throw FormatException('$procedure returned a non-integer ID');
  }
  return parsed;
}

int? _asInt(Object? value) => value is int ? value : null;

Object? _argumentAt(List<dynamic> arguments, int index) =>
    index < arguments.length ? arguments[index] : null;

extension on List<dynamic> {
  Object? get firstOrNull => isEmpty ? null : first;
}

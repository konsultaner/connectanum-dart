import 'dart:collection';

import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:test/test.dart';

void main() {
  test('HTTP3 is opt-in while transport alert throttling defaults to on', () {
    const http3 = Http3Settings();
    expect(http3.enabled, isFalse);
    expect(http3.port, isNull);
    expect(const TransportAlertSettings().throttleOnAlert, isTrue);
  });

  test('realm creation and identity disclosure require explicit opt-in', () {
    const realm = RealmSettings(
      name: 'public',
      auth: RealmAuthSettings(methods: []),
      roles: [],
      limits: RealmLimitSettings(),
    );
    expect(realm.autoCreate, isFalse);
    expect(realm.authorizationProvider, isNull);
    const automatic = RealmSettings(
      name: 'public',
      auth: RealmAuthSettings(methods: []),
      roles: [],
      limits: RealmLimitSettings(),
      autoCreate: true,
    );
    expect(automatic.autoCreate, isTrue);
    const hidden = DiscloseSettings();
    expect(
      [hidden.caller, hidden.publisher, hidden.callee],
      [false, false, false],
    );
    for (final (settings, expected) in [
      (const DiscloseSettings(caller: true), [true, false, false]),
      (const DiscloseSettings(publisher: true), [false, true, false]),
      (const DiscloseSettings(callee: true), [false, false, true]),
    ]) {
      expect([settings.caller, settings.publisher, settings.callee], expected);
    }
  });

  final positiveLimits = <String, Object Function(int)>{
    'failed authentication records': (n) =>
        RealmLimitSettings(maxFailedAuthRecords: n),
    'HTTP authentication grants': (n) =>
        RealmLimitSettings(maxHttpAuthGrants: n),
    'requests per window': (n) => HttpRouteRateLimitSettings(maxRequests: n),
    'rate limit window': (n) => HttpRouteRateLimitSettings(windowMs: n),
    'rate limit buckets': (n) => HttpRouteRateLimitSettings(maxBuckets: n),
  };
  for (final entry in positiveLimits.entries) {
    test('${entry.key} accepts one but rejects zero and negative capacity', () {
      expect(() => entry.value(1), returnsNormally);
      expect(() => entry.value(0), throwsA(isA<AssertionError>()));
      expect(() => entry.value(-1), throwsA(isA<AssertionError>()));
    });
  }
  final nonnegativeLimits = <String, Object Function(int)>{
    'worker minimum': (n) => WorkerPoolSettings(minWorkers: n),
    'backpressure depth': (n) =>
        BackpressureThrottleSettings(depthThreshold: n),
    'backpressure events': (n) =>
        BackpressureThrottleSettings(newEventsThreshold: n),
    'GOAWAY alerts': (n) => TransportAlertSettings(goAwayDeltaThreshold: n),
    'idle alerts': (n) => TransportAlertSettings(idleTimeoutDeltaThreshold: n),
    'body alerts': (n) => TransportAlertSettings(bodyTimeoutDeltaThreshold: n),
    'protocol alerts': (n) =>
        TransportAlertSettings(protocolErrorDeltaThreshold: n),
    'internal alerts': (n) =>
        TransportAlertSettings(internalErrorDeltaThreshold: n),
  };
  for (final entry in nonnegativeLimits.entries) {
    test(
      '${entry.key} accepts zero and one but rejects a negative threshold',
      () {
        expect(() => entry.value(0), returnsNormally);
        expect(() => entry.value(1), returnsNormally);
        expect(() => entry.value(-1), throwsA(isA<AssertionError>()));
      },
    );
  }

  _valueContract(
    'session authentication',
    (c) => SessionProfileAuthSettings(
      methods: _field(c, 'methods', ['ticket', 'scram']),
      authId: _field<String?>(c, 'authId', 'alice'),
      authRole: _field<String?>(c, 'authRole', 'member'),
      httpProvider: _field<String?>(c, 'httpProvider', 'http-auth'),
    ),
    {
      'methods': ['scram', 'ticket'],
      'authId': null,
      'authRole': 'admin',
      'httpProvider': null,
    },
  );
  _valueContract(
    'session profile',
    (c) => SessionProfileSettings(
      name: _field(c, 'name', 'public'),
      realm: _field<String?>(c, 'realm', 'realm1'),
      auth: _field(
        c,
        'auth',
        const SessionProfileAuthSettings(authId: 'alice'),
      ),
      roles: _field(c, 'roles', _nestedOptions()),
    ),
    {
      'name': 'private',
      'realm': null,
      'auth': const SessionProfileAuthSettings(authId: 'bob'),
      'roles': _nestedOptions('changed'),
    },
  );
  _valueContract(
    'internal realm',
    (c) => InternalRealmSettings(
      name: _field(c, 'name', 'internal'),
      authId: _field<String?>(c, 'authId', 'service'),
      authRole: _field<String?>(c, 'authRole', 'trusted'),
      sessionProfile: _field<String?>(c, 'sessionProfile', 'internal-profile'),
      roles: _field(c, 'roles', _nestedOptions()),
      services: _field<Set<String>?>(c, 'services', {'metrics', 'auth'}),
    ),
    {
      'name': 'other',
      'authId': null,
      'authRole': 'limited',
      'sessionProfile': null,
      'roles': _nestedOptions('changed'),
      'services': <String>{'metrics'},
    },
  );
  _valueContract(
    'rawsocket listener',
    (c) => RawSocketListenerSettings(
      maxFrameExponent: _field<int?>(c, 'exponent', 24),
      options: _field(c, 'options', _nestedOptions()),
    ),
    {'exponent': 30, 'options': _nestedOptions('changed')},
  );
  _valueContract(
    'websocket listener',
    (c) => WebSocketListenerSettings(
      path: _field<String?>(c, 'path', '/ws'),
      subprotocols: _field(c, 'subprotocols', ['wamp.2.json', 'wamp.2.cbor']),
      serializerFallback: _field<String?>(c, 'fallback', 'json'),
      options: _field(c, 'options', _nestedOptions()),
    ),
    {
      'path': null,
      'subprotocols': ['wamp.2.cbor', 'wamp.2.json'],
      'fallback': 'cbor',
      'options': _nestedOptions('changed'),
    },
  );
  _valueContract(
    'http3',
    (c) => Http3Settings(
      enabled: _field(c, 'enabled', true),
      port: _field<int?>(c, 'port', 8443),
    ),
    {'enabled': false, 'port': null},
  );
  _valueContract(
    'http listener',
    (c) => HttpListenerSettings(
      alpn: _field(c, 'alpn', ['h2', 'http/1.1']),
      http3: _field<Http3Settings?>(
        c,
        'http3',
        const Http3Settings(enabled: true),
      ),
      sessionProfile: _field<String?>(c, 'profile', 'http-auth'),
      routes: _field(c, 'routes', [_route('/one'), _route('/two')]),
      options: _field(c, 'options', _nestedOptions()),
    ),
    {
      'alpn': ['http/1.1', 'h2'],
      'http3': null,
      'profile': null,
      'routes': [_route('/two'), _route('/one')],
      'options': _nestedOptions('changed'),
    },
  );
  _valueContract(
    'listener',
    (c) => ListenerSettings(
      endpoint: _field(c, 'endpoint', '127.0.0.1:8080'),
      type: _field<String?>(c, 'type', 'websocket'),
      authmethods: _field(c, 'authmethods', ['ticket', 'scram']),
      sessionProfile: _field<String?>(c, 'profile', 'secure'),
      path: _field<String?>(c, 'path', '/ws'),
      tls: _field<Map<String, Object?>?>(c, 'tls', {'certificate': 'cert.pem'}),
      options: _field(c, 'options', _nestedOptions()),
      protocols: _field(c, 'protocols', [
        ListenerProtocol.websocket,
        ListenerProtocol.rawsocket,
      ]),
      rawsocket: _field<RawSocketListenerSettings?>(
        c,
        'rawsocket',
        const RawSocketListenerSettings(maxFrameExponent: 24),
      ),
      websocket: _field<WebSocketListenerSettings?>(
        c,
        'websocket',
        const WebSocketListenerSettings(path: '/ws'),
      ),
      http: _field<HttpListenerSettings?>(
        c,
        'http',
        const HttpListenerSettings(alpn: ['h2']),
      ),
    ),
    {
      'endpoint': '127.0.0.1:9090',
      'type': null,
      'authmethods': ['scram', 'ticket'],
      'profile': null,
      'path': '/other',
      'tls': {'certificate': 'other.pem'},
      'options': _nestedOptions('changed'),
      'protocols': [ListenerProtocol.rawsocket, ListenerProtocol.websocket],
      'rawsocket': null,
      'websocket': null,
      'http': null,
    },
  );
  _valueContract(
    'http match',
    (c) => HttpRouteMatch(
      path: _field<String?>(c, 'path', '/api'),
      prefix: _field<String?>(c, 'prefix', '/'),
      host: _field<String?>(c, 'host', 'example.test'),
      methods: _field(c, 'methods', ['GET', 'HEAD']),
      protocols: _field(c, 'protocols', ['http/1.1', 'h2']),
      headers: _field(c, 'headers', {'x-tenant': 'one'}),
      extra: _field(c, 'extra', _nestedOptions()),
    ),
    {
      'path': null,
      'prefix': '/other',
      'host': null,
      'methods': ['HEAD', 'GET'],
      'protocols': ['h2', 'http/1.1'],
      'headers': {'x-tenant': 'two'},
      'extra': _nestedOptions('changed'),
    },
  );
  _valueContract(
    'http rate limit',
    (c) => HttpRouteRateLimitSettings(
      maxRequests: _field(c, 'requests', 10),
      windowMs: _field(c, 'window', 1000),
      key: _field(c, 'key', 'authid'),
      maxBuckets: _field(c, 'buckets', 64),
    ),
    {'requests': 11, 'window': 2000, 'key': 'global', 'buckets': 65},
  );
  _valueContract(
    'http action',
    (c) => HttpRouteAction(
      type: _field(c, 'type', HttpRouteActionType.rpc),
      procedure: _field<String?>(c, 'procedure', 'app.call'),
      realm: _field<String?>(c, 'realm', 'realm1'),
      sessionProfile: _field<String?>(c, 'profile', 'secure'),
      namespace: _field<String?>(c, 'namespace', 'app'),
      appendMethodSuffix: _field<bool?>(c, 'suffix', true),
      topic: _field<String?>(c, 'topic', 'app.event'),
      serializer: _field<String?>(c, 'serializer', 'json'),
      contentType: _field<String?>(c, 'contentType', 'application/json'),
      directory: _field<String?>(c, 'directory', 'public'),
      cacheControl: _field<String?>(c, 'cacheControl', 'no-store'),
      delegate: _field<String?>(c, 'delegate', 'handler'),
      rateLimit: _field<HttpRouteRateLimitSettings?>(
        c,
        'rateLimit',
        const HttpRouteRateLimitSettings(),
      ),
      options: _field(c, 'options', _nestedOptions()),
    ),
    {
      'type': HttpRouteActionType.internalCall,
      'procedure': null,
      'realm': 'other',
      'profile': null,
      'namespace': 'other',
      'suffix': false,
      'topic': null,
      'serializer': 'cbor',
      'contentType': null,
      'directory': 'private',
      'cacheControl': null,
      'delegate': 'other',
      'rateLimit': null,
      'options': _nestedOptions('changed'),
    },
  );
  _valueContract(
    'http route',
    (c) => HttpRouteSettings(
      match: _field(c, 'match', const HttpRouteMatch(path: '/api')),
      action: _field(
        c,
        'action',
        const HttpRouteAction(
          type: HttpRouteActionType.rpc,
          procedure: 'app.get',
        ),
      ),
      methodActions: _field(c, 'methods', {
        'POST': HttpRouteAction(
          type: HttpRouteActionType.publish,
          topic: 'app.event',
        ),
      }),
    ),
    {
      'match': const HttpRouteMatch(path: '/other'),
      'action': const HttpRouteAction(type: HttpRouteActionType.handler),
      'methods': <String, HttpRouteAction>{},
    },
  );
  _valueContract(
    'open metrics',
    (c) => OpenMetricsSettings(
      enabled: _field(c, 'enabled', true),
      listen: _field<String?>(c, 'listen', '127.0.0.1:9090'),
      path: _field(c, 'path', '/metrics'),
      authToken: _field<String?>(c, 'token', 'test-token'),
      realm: _field(c, 'realm', 'metrics'),
      collectionTimeout: _field(c, 'timeout', const Duration(seconds: 2)),
    ),
    {
      'enabled': false,
      'listen': null,
      'path': '/other',
      'token': null,
      'realm': 'other',
      'timeout': const Duration(seconds: 3),
    },
  );
  _valueContract(
    'backpressure',
    (c) => BackpressureThrottleSettings(
      depthThreshold: _field(c, 'depth', 16),
      newEventsThreshold: _field(c, 'events', 1),
      cooldown: _field(c, 'cooldown', const Duration(milliseconds: 250)),
    ),
    {'depth': 0, 'events': 0, 'cooldown': Duration.zero},
  );
  _valueContract(
    'transport alerts',
    (c) => TransportAlertSettings(
      goAwayDeltaThreshold: _field(c, 'goAway', 1),
      idleTimeoutDeltaThreshold: _field(c, 'idle', 2),
      bodyTimeoutDeltaThreshold: _field(c, 'body', 3),
      protocolErrorDeltaThreshold: _field(c, 'protocol', 4),
      internalErrorDeltaThreshold: _field(c, 'internal', 5),
      cooldown: _field(c, 'cooldown', const Duration(milliseconds: 500)),
      throttleOnAlert: _field(c, 'throttle', true),
    ),
    {
      'goAway': 0,
      'idle': 0,
      'body': 0,
      'protocol': 0,
      'internal': 0,
      'cooldown': Duration.zero,
      'throttle': false,
    },
  );
  _valueContract(
    'metrics',
    (c) => MetricsSettings(
      openMetrics: _field<OpenMetricsSettings?>(
        c,
        'openMetrics',
        const OpenMetricsSettings(enabled: true),
      ),
      backpressure: _field(
        c,
        'backpressure',
        const BackpressureThrottleSettings(),
      ),
      transportAlerts: _field(c, 'alerts', const TransportAlertSettings()),
    ),
    {
      'openMetrics': null,
      'backpressure': const BackpressureThrottleSettings(depthThreshold: 0),
      'alerts': const TransportAlertSettings(throttleOnAlert: false),
    },
  );
  _valueContract(
    'worker pool',
    (c) => WorkerPoolSettings(
      minWorkers: _field(c, 'workers', 1),
    ),
    {'workers': 0},
  );

  test(
    'internal realm snapshots top-level collections and ignores set order',
    () {
      final roles = _nestedOptions();
      final services = {'metrics', 'auth'};
      final first = InternalRealmSettings(
        name: 'internal',
        roles: roles,
        services: services,
      );
      roles['new'] = true;
      services.clear();
      final second = InternalRealmSettings(
        name: 'internal',
        roles: _nestedOptions(),
        services: {'auth', 'metrics'},
      );
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(() => first.roles['new'] = true, throwsUnsupportedError);
      expect(() => first.services.add('new'), throwsUnsupportedError);
      expect(InternalRealmSettings(name: 'empty').services, isEmpty);
    },
  );

  test('copyWith preserves unspecified values and supports zero and false', () {
    const pool = WorkerPoolSettings(minWorkers: 3);
    expect(pool.copyWith(), pool);
    expect(pool.copyWith(minWorkers: 0).minWorkers, 0);
    const pressure = BackpressureThrottleSettings(
      depthThreshold: 7,
      newEventsThreshold: 9,
      cooldown: Duration(seconds: 3),
    );
    expect(pressure.copyWith(), pressure);
    expect(
      pressure.copyWith(depthThreshold: 0),
      const BackpressureThrottleSettings(
        depthThreshold: 0,
        newEventsThreshold: 9,
        cooldown: Duration(seconds: 3),
      ),
    );
    expect(
      pressure.copyWith(newEventsThreshold: 0),
      const BackpressureThrottleSettings(
        depthThreshold: 7,
        newEventsThreshold: 0,
        cooldown: Duration(seconds: 3),
      ),
    );
    expect(
      pressure.copyWith(cooldown: Duration.zero),
      const BackpressureThrottleSettings(
        depthThreshold: 7,
        newEventsThreshold: 9,
        cooldown: Duration.zero,
      ),
    );
    const alerts = TransportAlertSettings(
      goAwayDeltaThreshold: 2,
      idleTimeoutDeltaThreshold: 3,
      bodyTimeoutDeltaThreshold: 4,
      protocolErrorDeltaThreshold: 5,
      internalErrorDeltaThreshold: 6,
      cooldown: Duration(seconds: 7),
    );
    expect(alerts.copyWith(), alerts);
    final changed = alerts.copyWith(
      goAwayDeltaThreshold: 0,
      idleTimeoutDeltaThreshold: 0,
      bodyTimeoutDeltaThreshold: 0,
      protocolErrorDeltaThreshold: 0,
      internalErrorDeltaThreshold: 0,
      cooldown: Duration.zero,
      throttleOnAlert: false,
    );
    expect(changed.goAwayDeltaThreshold, 0);
    expect(changed.idleTimeoutDeltaThreshold, 0);
    expect(changed.bodyTimeoutDeltaThreshold, 0);
    expect(changed.protocolErrorDeltaThreshold, 0);
    expect(changed.internalErrorDeltaThreshold, 0);
    expect(changed.cooldown, Duration.zero);
    expect(changed.throttleOnAlert, isFalse);
    expect(alerts.throttleOnAlert, isTrue);
    final internal = InternalRealmSettings(
      name: 'one',
      authId: 'service',
      authRole: 'trusted',
      sessionProfile: 'profile',
      roles: _nestedOptions(),
      services: {'auth'},
    );
    expect(internal.copyWith(), internal);
    final replacement = internal.copyWith(
      name: 'two',
      authId: 'other',
      authRole: 'limited',
      sessionProfile: 'other-profile',
      roles: {},
      services: {},
    );
    expect(replacement.name, 'two');
    expect(replacement.authId, 'other');
    expect(replacement.authRole, 'limited');
    expect(replacement.sessionProfile, 'other-profile');
    expect(replacement.roles, isEmpty);
    expect(replacement.services, isEmpty);
    expect(internal.services, {'auth'});
  });

  test(
    'router copies and equality retain every top-level configuration field',
    () {
      final original = RouterSettings(
        realms: const [
          RealmSettings(
            name: 'realm1',
            auth: RealmAuthSettings(methods: ['ticket']),
            roles: [],
            limits: RealmLimitSettings(),
          ),
        ],
        listeners: const [ListenerSettings(endpoint: '127.0.0.1:8080')],
        sessionProfiles: const [SessionProfileSettings(name: 'public')],
        internalRealms: [
          InternalRealmSettings(name: 'internal', services: {'auth'}),
        ],
        metrics: const MetricsSettings(
          openMetrics: OpenMetricsSettings(enabled: true),
        ),
        authenticators: const {
          'ticket': AuthenticatorDefinition(type: 'ticket'),
        },
        authorizationProviders: const {
          'policy': AuthorizationProviderDefinition(type: 'rpc'),
        },
        httpAuthProviders: const {
          'bearer': HttpAuthProviderDefinition(type: 'token'),
        },
        workerPool: const WorkerPoolSettings(minWorkers: 2),
      );
      Map<String, Object?> fields(RouterSettings s) => {
        'realms': s.realms,
        'listeners': s.listeners,
        'sessionProfiles': s.sessionProfiles,
        'internalRealms': s.internalRealms,
        'metrics': s.metrics,
        'authenticators': s.authenticators,
        'authorizationProviders': s.authorizationProviders,
        'httpAuthProviders': s.httpAuthProviders,
        'workerPool': s.workerPool,
      };
      const equality = RouterSettingsEquality();
      final copy = original.copyWith();
      expect(identical(copy, original), isFalse);
      expect(fields(copy), fields(original));
      expect(equality.equals(original, copy), isTrue);
      expect(equality.hash(original), equality.hash(copy));
      expect(equality.isValidKey(original), isTrue);
      expect(equality.isValidKey(null), isFalse);
      expect(equality.isValidKey('settings'), isFalse);
      final values =
          HashMap<RouterSettings, String>(
              equals: equality.equals,
              hashCode: equality.hash,
              isValidKey: equality.isValidKey,
            )
            ..[original] = 'original'
            ..[copy] = 'replacement';
      expect(values.length, 1);
      expect(values[original], 'replacement');
      expect(values[Object()], isNull);
      final cases = <String, (RouterSettings, Object?)>{
        'realms': (original.copyWith(realms: []), <RealmSettings>[]),
        'listeners': (original.copyWith(listeners: []), <ListenerSettings>[]),
        'sessionProfiles': (
          original.copyWith(sessionProfiles: []),
          <SessionProfileSettings>[],
        ),
        'internalRealms': (
          original.copyWith(internalRealms: []),
          <InternalRealmSettings>[],
        ),
        'metrics': (
          original.copyWith(metrics: const MetricsSettings()),
          const MetricsSettings(),
        ),
        'authenticators': (
          original.copyWith(authenticators: {}),
          <String, AuthenticatorDefinition>{},
        ),
        'authorizationProviders': (
          original.copyWith(authorizationProviders: {}),
          <String, AuthorizationProviderDefinition>{},
        ),
        'httpAuthProviders': (
          original.copyWith(httpAuthProviders: {}),
          <String, HttpAuthProviderDefinition>{},
        ),
        'workerPool': (
          original.copyWith(
            workerPool: const WorkerPoolSettings(minWorkers: 0),
          ),
          const WorkerPoolSettings(minWorkers: 0),
        ),
      };
      for (final entry in cases.entries) {
        final changed = entry.value.$1;
        expect(fields(changed), {
          ...fields(original),
          entry.key: entry.value.$2,
        }, reason: entry.key);
        expect(equality.equals(original, changed), isFalse, reason: entry.key);
        expect(equality.equals(changed, original), isFalse, reason: entry.key);
        values[changed] = entry.key;
        expect(values[changed.copyWith()], entry.key);
        expect(values[original], 'replacement');
        values.remove(changed);
      }
      expect(fields(original), fields(copy));
    },
  );

  test(
    'listener primary protocol is nullable and preserves preference order',
    () {
      expect(
        const ListenerSettings(endpoint: 'localhost:0').primaryProtocol,
        isNull,
      );
      expect(
        const ListenerSettings(
          endpoint: 'localhost:0',
          protocols: [ListenerProtocol.http3, ListenerProtocol.http],
        ).primaryProtocol,
        ListenerProtocol.http3,
      );
    },
  );
}

T _field<T>(Map<String, Object?> changes, String name, T initial) =>
    changes.containsKey(name) ? changes[name] as T : initial;

Map<String, Object?> _nestedOptions([String value = 'value']) => {
  'nested': {
    'items': [value, 'second'],
  },
};

HttpRouteSettings _route(String path) => HttpRouteSettings(
  match: HttpRouteMatch(path: path),
  action: const HttpRouteAction(
    type: HttpRouteActionType.rpc,
    procedure: 'app.call',
  ),
);

void _valueContract<T extends Object>(
  String name,
  T Function(Map<String, Object?>) build,
  Map<String, Object?> changes,
) {
  group(name, () {
    test('equal independent values work as interchangeable map keys', () {
      final first = build({});
      final equal = build({});
      expect(identical(first, equal), isFalse);
      expect(first == first, isTrue);
      expect(first, equal);
      expect(equal, first);
      expect(first == Object(), isFalse);
      expect(first.hashCode, equal.hashCode);
      final values = {first: 'before'};
      values[equal] = 'after';
      expect(values.length, 1);
      expect(values[first], 'after');
    });
    for (final entry in changes.entries) {
      test(
        'distinguishes ${entry.key} without losing the original map entry',
        () {
          final first = build({});
          final changed = build({entry.key: entry.value});
          expect(first, isNot(changed));
          expect(changed, isNot(first));
          final values = {first: 'original', changed: 'changed'};
          expect(values.length, 2);
          expect(values[build({})], 'original');
          expect(values[build({entry.key: entry.value})], 'changed');
        },
      );
    }
  });
}

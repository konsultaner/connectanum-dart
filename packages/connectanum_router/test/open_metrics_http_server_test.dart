@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library open_metrics_http_server_test;

import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart' show CallOptions;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

class _FakeRuntime implements NativeRuntime {
  final Map<int, int> _ports = {};
  int _nextId = 1;

  @override
  NativeHttpResponseStream openHttpResponseStream({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) {
    throw UnsupportedError('HTTP response streaming not supported');
  }

  @override
  NativeHttpResponseStreamDescriptor openHttpResponseStreamDescriptor({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) {
    throw UnsupportedError('HTTP response streaming not supported');
  }

  @override
  NativeRouterMetrics? pollRouterMetrics() => null;

  @override
  void sendHttpResponse({
    required int handshakeHandle,
    int? connectionId,
    required NativeHttpResponse response,
  }) {
    throw UnsupportedError('HTTP responses not supported');
  }

  @override
  void applyRouterConfig(Uint8List config) {}

  @override
  int reloadTls() => 0;

  @override
  int connectionMaxRawSocketExponent(int connectionId) => 16;

  @override
  NativeConnectionProtocol connectionProtocol(int connectionId) =>
      NativeConnectionProtocol.rawsocket;

  @override
  void closeConnection(int connectionId) {}

  @override
  String? connectionWebSocketProtocol(int connectionId) => null;

  @override
  int getHttp3Port(int listenerId) => 0;

  @override
  void closeListener(int listenerId) {}

  @override
  int getLocalPort(int listenerId) => _ports[listenerId] ?? listenerId;

  @override
  int listen(String host, int port, {int backlog = 128}) {
    final id = _nextId++;
    _ports[id] = port == 0 ? 5000 + id : port;
    return id;
  }

  @override
  int pollConnection(int listenerId) => 0;

  @override
  NativeHttpConnectionEvent? pollHttpConnectionEvent() => null;

  @override
  NativeIncomingMessage? pollMessage(int connectionId) => null;

  @override
  NativeHttpHandshake? pollHttp3Request(int connectionId) => null;

  @override
  NativeHttp3Stream? pollHttp3Stream(int connectionId) => null;

  @override
  void releaseHttp2Handshake(int handle) {}

  @override
  void releaseHttp3Handshake(int handle) {}

  @override
  void releaseHttpHandshake(int handle) {}

  @override
  void rejectWebSocket({
    required int connectionId,
    required int handshakeHandle,
    int status = 400,
    String reason = '',
  }) {}

  @override
  void acceptWebSocket({
    required int connectionId,
    required int handshakeHandle,
    required NativeMessageSerializer serializer,
    required String protocol,
  }) {}

  @override
  void sendMessage(int connectionId, Uint8List payload) {}

  @override
  void shutdown() {}

  @override
  void start() {}

  @override
  NativeHttp2Handshake? takeHttp2Handshake(int connectionId) => null;

  @override
  NativeHttp3Connection? takeHttp3Connection(int connectionId) => null;

  @override
  NativeHttp3Handshake? takeHttp3Handshake(int connectionId) => null;

  @override
  NativeHttpHandshake? takeHttpHandshake(int connectionId) => null;

  @override
  NativeWebSocketHandshake? takeWebSocketHandshake(int connectionId) => null;
}

class _NoopHandleRuntime extends _FakeRuntime
    implements NativeRuntimeWithHandles {
  @override
  String? get libraryPathHint => null;

  @override
  NativeRouterMetrics? pollRouterMetrics() => const NativeRouterMetrics(
    totalEvents: 1,
    gracefulEvents: 1,
    goAwayEvents: 0,
    idleTimeoutEvents: 0,
    bodyTimeoutEvents: 0,
    protocolErrorEvents: 0,
    internalErrorEvents: 0,
    backpressureEvents: 0,
    maxBackpressureDepth: 0,
    breakdown: [
      NativeRouterMetricsBreakdown(
        listenerId: 1,
        protocol: NativeConnectionProtocol.http2,
        totalEvents: 1,
        gracefulEvents: 1,
        goAwayEvents: 0,
        idleTimeoutEvents: 0,
        bodyTimeoutEvents: 0,
        protocolErrorEvents: 0,
        internalErrorEvents: 0,
        backpressureEvents: 0,
        maxBackpressureDepth: 0,
      ),
    ],
  );

  @override
  int pollMessageHandle(int connectionId) => 0;

  @override
  int pollWebSocketMessageHandle(int connectionId) => 0;

  @override
  int retainMessageHandle(int handle) => handle;

  @override
  void releaseMessageHandle(int handle) {}

  @override
  void forwardPublishEvent({
    required int handle,
    required int connectionId,
    required int subscriptionId,
    required int publicationId,
    int? publisherSessionId,
    String? topic,
  }) {}

  @override
  void forwardCallInvocation({
    required int handle,
    required int connectionId,
    required int invocationId,
    required int registrationId,
    int? callerSessionId,
    String? callerAuthId,
    String? callerAuthRole,
    String? procedure,
    bool? receiveProgress,
  }) {}

  @override
  void forwardResultFromYield({
    required int handle,
    required int connectionId,
    required int requestId,
    required bool progress,
  }) {}

  @override
  void forwardInvocationError({
    required int handle,
    required int connectionId,
    required int requestType,
    required int requestId,
  }) {}
}

RouterSettings _buildSettings({
  String? authToken,
  Duration collectionTimeout = const Duration(seconds: 5),
  String metricsListen = '127.0.0.1:0',
}) {
  final realmBuilder = RealmSettingsBuilder('realm1')
    ..addAuthMethod('anonymous')
    ..addRoleFromBuilder(
      RoleSettingsBuilder('member')..addPermissionFromBuilder(
        PermissionSettingsBuilder('')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const [
            'subscribe',
            'publish',
            'call',
            'register',
            'unregister',
          ]),
      ),
    );

  final metricsRealmBuilder = RealmSettingsBuilder('connectanum.metrics')
    ..addAuthMethod('anonymous')
    ..addRoleFromBuilder(
      RoleSettingsBuilder('metrics')..addPermissionFromBuilder(
        PermissionSettingsBuilder('')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const [
            'register',
            'unregister',
            'call',
            'subscribe',
            'publish',
          ]),
      ),
    );

  final listenerBuilder = ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
    ..addAuthMethod('anonymous')
    ..setOptions(const {'max_rawsocket_size_exponent': 16});

  final internalMetricsRealm = InternalRealmSettings(
    name: 'connectanum.metrics',
    authId: 'metrics-daemon',
    authRole: 'metrics',
    services: {'metrics'},
  );

  return RouterSettings(
    realms: [realmBuilder.build(), metricsRealmBuilder.build()],
    listeners: [listenerBuilder.build()],
    internalRealms: [internalMetricsRealm],
    metrics: MetricsSettings(
      openMetrics: OpenMetricsSettings(
        enabled: true,
        listen: metricsListen,
        path: '/metrics',
        authToken: authToken,
        realm: 'connectanum.metrics',
        collectionTimeout: collectionTimeout,
      ),
    ),
    authenticators: const {
      'anonymous': AuthenticatorDefinition(type: 'anonymous'),
    },
    workerPool: const WorkerPoolSettings(minWorkers: 1),
  );
}

int _nextSyntheticHttpRequestId = 1;

Future<HttpResponsePayload> _callMetricsHttp(
  RouterSession session,
  String procedure, {
  String method = 'GET',
  String path = '/metrics',
  String? bearerToken,
}) async {
  final requestId = _nextSyntheticHttpRequestId++;
  final snapshot = HttpRequestSnapshot(
    id: requestId,
    method: method,
    target: path,
    path: path,
    protocol: 'http',
    version: 1,
    headers: {
      if (bearerToken != null)
        HttpHeaders.authorizationHeader: 'Bearer $bearerToken',
    },
    realm: 'connectanum.metrics',
    procedure: procedure,
  );
  final requestPayload = snapshot.toInvocationPayload();
  final result = await session
      .call(
        procedure,
        argumentsKeywords: {
          '_http': requestPayload,
          '_connection': const {
            'listenerId': 1,
            'connectionId': 1,
            'endpoint': '127.0.0.1:0',
          },
        },
        options: CallOptions(
          custom: {
            HttpInvocationKeys.requestId: requestId,
            HttpInvocationKeys.request: requestPayload,
          },
        ),
      )
      .first;
  final payload = HttpResponsePayload.fromKeywordArguments(
    result.argumentsKeywords?.cast<String, Object?>(),
  );
  expect(payload, isNotNull);
  return payload!;
}

RouterBinding _startRouter(RouterSettings settings) {
  final runtime = _NoopHandleRuntime();
  final enrichedSettings = settings.withOpenMetricsHttpRoutes();
  final router = Router(
    RouterConfig(
      endpoints: enrichedSettings.listeners
          .map(Endpoint.fromListenerSettings)
          .toList(growable: false),
    ),
    settings: enrichedSettings,
  );
  return router.start(runtime);
}

void main() {
  test('OpenMetrics settings add router-native HTTP routes', () {
    final settings = _buildSettings().withOpenMetricsHttpRoutes();

    final listener = settings.listeners.single;
    expect(
      listener.protocols,
      equals(const [
        ListenerProtocol.rawsocket,
        ListenerProtocol.http,
        ListenerProtocol.http2,
      ]),
    );
    final routes = listener.http?.routes;
    expect(routes, isNotNull);
    expect(
      routes!.map((route) => route.match.path),
      containsAll(const ['/healthz', '/health', '/metrics']),
    );
    final metricsRoute = routes.firstWhere(
      (route) => route.match.path == '/metrics',
    );
    expect(metricsRoute.match.methods, equals(const ['GET', 'HEAD']));
    expect(metricsRoute.action.type, equals(HttpRouteActionType.internalCall));
    expect(metricsRoute.action.realm, equals('connectanum.metrics'));
    expect(
      metricsRoute.action.procedure,
      equals('connectanum.metrics.openmetrics'),
    );
  });

  test('OpenMetrics settings create an HTTP/2-capable metrics listener', () {
    final settings = _buildSettings(
      metricsListen: '127.0.0.1:18080',
    ).withOpenMetricsHttpRoutes();

    final metricsListener = settings.listeners.singleWhere(
      (listener) => listener.endpoint == '127.0.0.1:18080',
    );
    expect(metricsListener.type, 'http');
    expect(
      metricsListener.protocols,
      equals(const [ListenerProtocol.http, ListenerProtocol.http2]),
    );
    expect(
      metricsListener.options['connectanum_open_metrics_listener'],
      isTrue,
    );
    expect(
      metricsListener.http?.routes.map((route) => route.match.path),
      containsAll(const ['/healthz', '/health', '/metrics']),
    );
  });

  test(
    'OpenMetrics internal HTTP routes serve /metrics and /healthz',
    () async {
      final binding = _startRouter(_buildSettings());
      addTearDown(binding.dispose);
      await binding.ensureInternalServicesReady();

      final caller = await binding.createInternalSession(
        realmUri: 'connectanum.metrics',
        authId: 'metrics-test',
        authRole: 'metrics',
      );
      addTearDown(caller.close);

      final health = await _callMetricsHttp(
        caller,
        'connectanum.metrics.healthz',
        path: '/healthz',
      );
      expect(health.status, equals(200));
      expect(health.bodyText, contains('ok'));

      final metrics = await _callMetricsHttp(
        caller,
        'connectanum.metrics.openmetrics',
      );
      expect(metrics.status, equals(200));
      expect(metrics.bodyText, contains('connectanum_router_realms'));
      expect(metrics.bodyText, contains('connectanum_router_process_info'));
      expect(
        metrics.bodyText,
        contains('connectanum_router_process_resident_memory_bytes'),
      );
      expect(metrics.headers['content-type'], contains('text/plain'));

      final head = await _callMetricsHttp(
        caller,
        'connectanum.metrics.openmetrics',
        method: 'HEAD',
      );
      expect(head.status, equals(200));
      expect(head.bodyText, isEmpty);
    },
  );

  test('OpenMetrics internal HTTP route requires auth token', () async {
    final binding = _startRouter(_buildSettings(authToken: 'secret'));
    addTearDown(binding.dispose);
    await binding.ensureInternalServicesReady();

    final caller = await binding.createInternalSession(
      realmUri: 'connectanum.metrics',
      authId: 'metrics-test',
      authRole: 'metrics',
    );
    addTearDown(caller.close);

    final denied = await _callMetricsHttp(
      caller,
      'connectanum.metrics.openmetrics',
    );
    expect(denied.status, equals(401));
    expect(denied.headers.containsKey('www-authenticate'), isTrue);

    final ok = await _callMetricsHttp(
      caller,
      'connectanum.metrics.openmetrics',
      bearerToken: 'secret',
    );
    expect(ok.status, equals(200));
    expect(ok.bodyText, contains('connectanum_router_realms'));
  });

  test(
    'OpenMetrics internal HTTP route returns unavailable when collection times out',
    () async {
      final binding = _startRouter(
        _buildSettings(collectionTimeout: Duration.zero),
      );
      addTearDown(binding.dispose);
      await binding.ensureInternalServicesReady();

      final caller = await binding.createInternalSession(
        realmUri: 'connectanum.metrics',
        authId: 'metrics-test',
        authRole: 'metrics',
      );
      addTearDown(caller.close);

      final response = await _callMetricsHttp(
        caller,
        'connectanum.metrics.openmetrics',
      );
      expect(response.status, equals(503));
      expect(response.bodyText, isEmpty);
    },
  );
}

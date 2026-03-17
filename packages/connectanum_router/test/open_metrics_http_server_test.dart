@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library open_metrics_http_server_test;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
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

RouterSettings _buildSettings({String? authToken}) {
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
        listen: '127.0.0.1:0',
        path: '/metrics',
        authToken: authToken,
        realm: 'connectanum.metrics',
      ),
    ),
    authenticators: const {
      'anonymous': AuthenticatorDefinition(type: 'anonymous'),
    },
    workerPool: const WorkerPoolSettings(minWorkers: 1),
  );
}

Future<(int status, String body, Map<String, String> headers)> _get(
  Uri uri, {
  String? bearerToken,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    if (bearerToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $bearerToken',
      );
    }
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });
    return (response.statusCode, body, headers);
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('OpenMetrics HTTP server serves /metrics and /healthz', () async {
    final runtime = _NoopHandleRuntime();
    final settings = _buildSettings();
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.disabled,
            maxRawSocketSizeExponent: 16,
          ),
        ],
      ),
      settings: settings,
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    final server = await binding.startOpenMetricsHttpServer();
    expect(server, isNotNull);

    final listenHost = server!.address.address;
    final base = Uri.parse('http://$listenHost:${server.port}');

    final health = await _get(base.replace(path: '/healthz'));
    expect(health.$1, equals(200));
    expect(health.$2, contains('ok'));

    final metrics = await _get(base.replace(path: '/metrics'));
    expect(metrics.$1, equals(200));
    expect(metrics.$2, contains('connectanum_router_realms'));
    expect(metrics.$3['content-type'], contains('text/plain'));
  });

  test('OpenMetrics HTTP server requires auth token when configured', () async {
    final runtime = _NoopHandleRuntime();
    final settings = _buildSettings(authToken: 'secret');
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.disabled,
            maxRawSocketSizeExponent: 16,
          ),
        ],
      ),
      settings: settings,
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    final server = await binding.startOpenMetricsHttpServer();
    expect(server, isNotNull);

    final listenHost = server!.address.address;
    final base = Uri.parse('http://$listenHost:${server.port}/metrics');

    final denied = await _get(base);
    expect(denied.$1, equals(401));
    expect(denied.$3.containsKey('www-authenticate'), isTrue);

    final ok = await _get(base, bearerToken: 'secret');
    expect(ok.$1, equals(200));
    expect(ok.$2, contains('connectanum_router_realms'));
  });
}

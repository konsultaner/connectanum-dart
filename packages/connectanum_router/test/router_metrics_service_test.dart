@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library router_metrics_service_test;

import 'dart:typed_data';

import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

class _FakeRuntime implements NativeRuntime {
  final List<String> listenCalls = [];
  Uint8List? appliedConfig;
  final Map<int, int> _ports = {};
  int _nextId = 1;

  @override
  void applyRouterConfig(Uint8List config) {
    appliedConfig = config;
  }

  @override
  int getLocalPort(int listenerId) => _ports[listenerId] ?? listenerId;

  @override
  int getHttp3Port(int listenerId) => 0;

  @override
  int listen(String host, int port, {int backlog = 128}) {
    final id = _nextId++;
    listenCalls.add('$host:$port:$backlog');
    _ports[id] = port == 0 ? 5000 + id : port;
    return id;
  }

  @override
  int pollConnection(int listenerId) => 0;

  @override
  int connectionMaxRawSocketExponent(int connectionId) => 16;

  @override
  NativeConnectionProtocol connectionProtocol(int connectionId) =>
      NativeConnectionProtocol.rawsocket;

  @override
  String? connectionWebSocketProtocol(int connectionId) => null;

  @override
  NativeHttpHandshake? takeHttpHandshake(int connectionId) => null;

  @override
  void releaseHttpHandshake(int handle) {}

  @override
  NativeHttp2Handshake? takeHttp2Handshake(int connectionId) => null;

  @override
  void releaseHttp2Handshake(int handle) {}

  @override
  NativeWebSocketHandshake? takeWebSocketHandshake(int connectionId) => null;

  @override
  void acceptWebSocket({
    required int connectionId,
    required int handshakeHandle,
    required NativeMessageSerializer serializer,
    required String protocol,
  }) {}

  @override
  void rejectWebSocket({
    required int connectionId,
    required int handshakeHandle,
    int status = 400,
    String reason = '',
  }) {}

  @override
  NativeHttp3Handshake? takeHttp3Handshake(int connectionId) => null;

  @override
  void releaseHttp3Handshake(int handle) {}

  @override
  NativeHttp3Connection? takeHttp3Connection(int connectionId) => null;

  @override
  NativeHttp3Stream? pollHttp3Stream(int connectionId) => null;

  @override
  NativeHttpHandshake? pollHttp3Request(int connectionId) => null;

  @override
  void sendHttpResponse({
    required int handshakeHandle,
    int? connectionId,
    required NativeHttpResponse response,
  }) {
    throw UnsupportedError('HTTP responses not supported');
  }

  @override
  NativeHttpResponseStream openHttpResponseStream({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) {
    throw UnsupportedError('HTTP response streaming not supported');
  }

  @override
  void sendMessage(int connectionId, Uint8List payload) {}

  @override
  NativeHttpConnectionEvent? pollHttpConnectionEvent() => null;

  @override
  NativeRouterMetrics? pollRouterMetrics() => null;

  @override
  NativeIncomingMessage? pollMessage(int connectionId) => null;

  @override
  void shutdown() {}

  @override
  void start() {}
}

class _NoopHandleRuntime extends _FakeRuntime
    implements NativeRuntimeWithHandles {
  NativeRouterMetrics? routerMetrics;
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

  @override
  String? get libraryPathHint => null;

  @override
  NativeRouterMetrics? pollRouterMetrics() =>
      routerMetrics ??
      const NativeRouterMetrics(
        totalEvents: 12,
        gracefulEvents: 8,
        goAwayEvents: 1,
        idleTimeoutEvents: 2,
        bodyTimeoutEvents: 1,
        protocolErrorEvents: 0,
        internalErrorEvents: 0,
        backpressureEvents: 3,
        maxBackpressureDepth: 4,
        breakdown: [
          NativeRouterMetricsBreakdown(
            listenerId: 1,
            protocol: NativeConnectionProtocol.http2,
            totalEvents: 12,
            gracefulEvents: 8,
            goAwayEvents: 1,
            idleTimeoutEvents: 2,
            bodyTimeoutEvents: 1,
            protocolErrorEvents: 0,
            internalErrorEvents: 0,
            backpressureEvents: 3,
            maxBackpressureDepth: 4,
          ),
        ],
      );
}

class _SequencedMetricsRuntime extends _NoopHandleRuntime {
  _SequencedMetricsRuntime(this.sequence);

  final List<NativeRouterMetrics> sequence;
  int _cursor = 0;

  @override
  NativeRouterMetrics? pollRouterMetrics() {
    if (sequence.isEmpty) {
      return super.pollRouterMetrics();
    }
    final index = _cursor < sequence.length ? _cursor : sequence.length - 1;
    final current = sequence[index];
    if (_cursor < sequence.length - 1) {
      _cursor += 1;
    }
    return current;
  }
}

void main() {
  test('metrics exporter collects snapshot and OpenMetrics payload', () async {
    final runtime = _NoopHandleRuntime();
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.native,
            maxRawSocketSizeExponent: 16,
          ),
        ],
      ),
      settings: _buildSettings(),
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    await binding.ensureInternalServicesReady();
    final realmSession = await binding.createInternalSession(
      realmUri: 'realm1',
      authId: 'client',
      authRole: 'member',
    );
    addTearDown(realmSession.close);

    await realmSession.subscribe('com.example.topic');
    await realmSession.register('com.example.proc');

    final metricsClient = await binding.createInternalSession(
      realmUri: 'connectanum.metrics',
      authId: 'observer',
      authRole: 'metrics',
    );
    addTearDown(metricsClient.close);

    final snapshotResult = await metricsClient
        .call('connectanum.metrics.snapshot')
        .first;
    final snapshotPayload =
        snapshotResult.arguments?.first as Map<String, Object?>;

    expect(snapshotPayload['router'], isA<Map<String, Object?>>());
    final routerMetrics = snapshotPayload['router'] as Map<String, Object?>;
    expect(routerMetrics['transport'], isNotNull);
    final realms = snapshotPayload['realms'] as List<dynamic>;
    final realmMetrics = realms.cast<Map<String, Object?>>().firstWhere(
      (realm) => realm['realm'] == 'realm1',
    );
    expect(realmMetrics['topics'], greaterThanOrEqualTo(1));
    expect(realmMetrics['registered_procedures'], greaterThanOrEqualTo(1));

    final exporterInfo = snapshotPayload['exporter'] as Map<String, Object?>?;
    expect(exporterInfo, isNotNull);
    expect(exporterInfo!['realm'], 'connectanum.metrics');
    expect(exporterInfo['path'], '/metrics');

    final openMetricsResult = await metricsClient
        .call('connectanum.metrics.openmetrics')
        .first;
    final openMetricsText = openMetricsResult.arguments?.first as String;
    expect(openMetricsText, contains('connectanum_router_realms'));
    expect(openMetricsText, contains('realm="realm1"'));
    expect(openMetricsText, contains('connectanum_router_http_events_total'));
    expect(
      openMetricsText,
      contains('connectanum_router_http_events_by_listener_total'),
    );
    expect(openMetricsText, contains('listener_id="1"'));
  });

  test('boss emits transport alerts and throttles on GOAWAY spikes', () async {
    final metricsBurst = _buildMetricsBreakdown(
      goAwayEvents: 0,
      backpressureEvents: 0,
      maxBackpressureDepth: 0,
    );
    final metricsAfter = _buildMetricsBreakdown(
      goAwayEvents: 2,
      backpressureEvents: 0,
      maxBackpressureDepth: 0,
    );
    final runtime = _SequencedMetricsRuntime([
      metricsBurst,
      metricsAfter,
      metricsAfter,
    ]);
    final events = <Object>[];
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.native,
            maxRawSocketSizeExponent: 16,
          ),
        ],
      ),
      settings: _buildSettings(),
    );

    final binding = router.start(
      runtime,
      workerPollInterval: const Duration(milliseconds: 2),
      onEvent: events.add,
    );
    addTearDown(binding.dispose);

    // Allow a few boss loops to poll the metrics sequence.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final alert = events.whereType<Map<String, Object?>>().firstWhere(
      (event) => event['type'] == 'listener_transport_alert',
      orElse: () => const {},
    );
    expect(alert, isNotEmpty);
    expect(alert['listenerId'], equals(1));
    expect(alert['reason'], equals('go_away'));
    expect(alert['newEvents'], equals(2));
    expect(alert['throttled'], isTrue);
  });
}

NativeRouterMetrics _buildMetricsBreakdown({
  int goAwayEvents = 1,
  int backpressureEvents = 3,
  int maxBackpressureDepth = 4,
}) => NativeRouterMetrics(
  totalEvents: goAwayEvents + backpressureEvents + 10,
  gracefulEvents: 8,
  goAwayEvents: goAwayEvents,
  idleTimeoutEvents: 2,
  bodyTimeoutEvents: 1,
  protocolErrorEvents: 0,
  internalErrorEvents: 0,
  backpressureEvents: backpressureEvents,
  maxBackpressureDepth: maxBackpressureDepth,
  breakdown: [
    NativeRouterMetricsBreakdown(
      listenerId: 1,
      protocol: NativeConnectionProtocol.http2,
      totalEvents: goAwayEvents + backpressureEvents + 10,
      gracefulEvents: 8,
      goAwayEvents: goAwayEvents,
      idleTimeoutEvents: 2,
      bodyTimeoutEvents: 1,
      protocolErrorEvents: 0,
      internalErrorEvents: 0,
      backpressureEvents: backpressureEvents,
      maxBackpressureDepth: maxBackpressureDepth,
    ),
  ],
);

RouterSettings _buildSettings() {
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
    metrics: const MetricsSettings(
      openMetrics: OpenMetricsSettings(
        enabled: true,
        listen: '127.0.0.1:0',
        path: '/metrics',
        realm: 'connectanum.metrics',
      ),
    ),
    authenticators: const {
      'anonymous': AuthenticatorDefinition(type: 'anonymous'),
    },
    workerPool: const WorkerPoolSettings(minWorkers: 1),
  );
}

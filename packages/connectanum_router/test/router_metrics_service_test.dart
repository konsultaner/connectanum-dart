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
  int reloadTls() => 0;

  @override
  int getLocalPort(int listenerId) => _ports[listenerId] ?? listenerId;

  @override
  int getHttp3Port(int listenerId) => 0;

  @override
  void closeListener(int listenerId) {}

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
  void closeConnection(int connectionId) {}

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
  NativeHttpResponseStreamDescriptor openHttpResponseStreamDescriptor({
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
    final events = <Object>[];
    final metricsBurst = _buildMetricsBreakdown(
      goAwayEvents: 0,
      backpressureEvents: 0,
      maxBackpressureDepth: 0,
    );
    final metricsAfter = _buildMetricsBreakdown(
      goAwayEvents: 1,
      backpressureEvents: 0,
      maxBackpressureDepth: 0,
    );
    final runtime = _SequencedMetricsRuntime([
      metricsBurst,
      metricsAfter,
      metricsAfter,
    ]);
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
      settings: _buildSettings(),
    );

    final binding = router.start(runtime, onEvent: events.add);
    addTearDown(binding.dispose);

    // Wait for the boss loop to observe the metrics delta and emit alerts.
    await _waitForTransportAlert(events);

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
    final routerAlerts = routerMetrics['alerts'] as Map<String, Object?>?;
    expect(routerAlerts, isNotNull);
    expect(routerAlerts!['backpressure_alerts'], greaterThanOrEqualTo(0));
    expect(
      routerAlerts['throttled_backpressure_alerts'],
      greaterThanOrEqualTo(0),
    );
    expect(routerMetrics['transport'], isNotNull);
    final processMetrics =
        routerMetrics['process'] as Map<String, Object?>? ?? const {};
    expect(processMetrics['pid'], isA<int>());
    expect(processMetrics['current_rss_bytes'], greaterThan(0));
    expect(processMetrics['max_rss_bytes'], greaterThan(0));
    final workerMetrics =
        routerMetrics['workers'] as List<Object?>? ?? const [];
    expect(workerMetrics, isNotEmpty);
    final workerMetric = workerMetrics.cast<Map<String, Object?>>().first;
    expect(workerMetric['id'], isA<int>());
    expect(workerMetric['isolate_hash'], isA<int>());
    expect(workerMetric['connection_count'], greaterThanOrEqualTo(0));
    expect(workerMetric['busy'], isA<bool>());
    expect(workerMetric['in_flight_dispatches'], greaterThanOrEqualTo(0));
    expect(workerMetric['pending_dispatches'], greaterThanOrEqualTo(0));
    expect(workerMetric['dispatches_total'], greaterThanOrEqualTo(0));
    expect(workerMetric['queued_dispatches_total'], greaterThanOrEqualTo(0));
    expect(workerMetric['completed_dispatches_total'], greaterThanOrEqualTo(0));
    expect(workerMetric['errors_total'], greaterThanOrEqualTo(0));
    expect(workerMetric['total_busy_duration_ms'], greaterThanOrEqualTo(0));
    expect(workerMetric['total_queue_latency_ms'], greaterThanOrEqualTo(0));
    expect(workerMetric['max_pending_dispatches'], greaterThanOrEqualTo(0));
    final transportMetrics =
        routerMetrics['transport'] as Map<String, Object?>? ?? const {};
    expect(transportMetrics['active_throttles'], equals(1));
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
    expect(openMetricsText, contains('connectanum_router_process_info'));
    expect(
      openMetricsText,
      contains('connectanum_router_process_resident_memory_bytes'),
    );
    expect(
      openMetricsText,
      contains('connectanum_router_process_max_resident_memory_bytes'),
    );
    expect(
      openMetricsText,
      contains('connectanum_router_worker_busy_isolates'),
    );
    expect(openMetricsText, contains('connectanum_router_worker_connections'));
    expect(openMetricsText, contains('connectanum_router_worker_busy'));
    expect(
      openMetricsText,
      contains('connectanum_router_worker_pending_dispatches'),
    );
    expect(
      openMetricsText,
      contains('connectanum_router_worker_dispatches_total'),
    );
    expect(
      openMetricsText,
      contains('connectanum_router_worker_queued_dispatches_total'),
    );
    expect(
      openMetricsText,
      contains('connectanum_router_worker_completed_dispatches_total'),
    );
    expect(
      openMetricsText,
      contains('connectanum_router_worker_dispatch_errors_total'),
    );
    expect(
      openMetricsText,
      contains('connectanum_router_worker_busy_duration_ms_total'),
    );
    expect(
      openMetricsText,
      contains('connectanum_router_worker_queue_latency_ms_total'),
    );
    expect(
      openMetricsText,
      contains('connectanum_router_worker_oldest_pending_dispatch_age_ms'),
    );
    expect(
      openMetricsText,
      contains('connectanum_router_worker_max_pending_dispatches'),
    );
    expect(openMetricsText, contains('realm="realm1"'));
    expect(openMetricsText, contains('connectanum_router_http_events_total'));
    expect(
      openMetricsText,
      contains('connectanum_router_http_events_by_listener_total'),
    );
    expect(openMetricsText, contains('listener_id="1"'));
    expect(
      openMetricsText,
      contains('connectanum_router_backpressure_alerts_total'),
    );
    expect(
      openMetricsText,
      contains('connectanum_router_backpressure_alerts_throttled_total'),
    );
    expect(
      openMetricsText,
      contains('connectanum_router_transport_alerts_total{reason="go_away"} 1'),
    );
    expect(
      openMetricsText,
      contains(
        'connectanum_router_transport_alerts_by_listener_total{listener_id="1",protocol="http2",endpoint="127.0.0.1:5001",reason="go_away"} 1',
      ),
    );
    expect(
      openMetricsText,
      contains('connectanum_router_throttled_listeners 1'),
    );
    expect(
      openMetricsText,
      contains(
        'connectanum_router_listener_throttle_active{listener_id="1",protocol="http2",endpoint="127.0.0.1:5001"} 1',
      ),
    );
    expect(
      openMetricsText,
      contains(
        'connectanum_router_listener_throttle_remaining_ms{listener_id="1",protocol="http2",endpoint="127.0.0.1:5001"} ',
      ),
    );

    final transportAlerts = snapshotPayload['alerts'] as Map<String, Object?>?;
    expect(transportAlerts, isNotNull);
    expect(transportAlerts!['goaway'], equals(1));
    expect(transportAlerts['transport'], equals(1));
    expect(transportAlerts['active_throttles'], equals(1));
    final byListener =
        transportAlerts['by_listener'] as List<Object?>? ?? const [];
    final entry = byListener.whereType<Map<String, Object?>>().firstWhere(
      (value) => value['listener_id'] == 1,
      orElse: () => const {},
    );
    expect(entry['goaway'], equals(1));
    expect(entry['transport'], equals(1));
    expect(entry['throttle_active'], isTrue);
    expect(entry['throttle_remaining_ms'], greaterThan(0));
    expect(entry['throttle_until'], isA<String>());
    expect(entry['last_alert_at'], isA<String>());
    expect(entry['last_alert_category'], equals('transport'));
    expect(entry['last_alert_reason'], equals('go_away'));
    expect(entry['last_new_events'], equals(1));
    expect(entry['last_total_events'], equals(1));
    final activeThrottleListeners =
        transportAlerts['active_throttle_listeners'] as List<Object?>? ??
        const [];
    expect(activeThrottleListeners, hasLength(1));
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
            tlsMode: TlsMode.disabled,
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

  test('metrics snapshot redacts OpenMetrics bearer token', () async {
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
      settings: _buildSettings(openMetricsAuthToken: 'secret-token'),
    );

    final binding = router.start(_NoopHandleRuntime());
    addTearDown(binding.dispose);

    await binding.ensureInternalServicesReady();
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
    final exporterInfo = snapshotPayload['exporter'] as Map<String, Object?>?;

    expect(exporterInfo, isNotNull);
    expect(exporterInfo!.containsKey('auth_token'), isFalse);
    expect(exporterInfo['auth_required'], isTrue);
  });

  test(
    'metrics snapshot treats empty OpenMetrics bearer token as disabled',
    () async {
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
        settings: _buildSettings(openMetricsAuthToken: ''),
      );

      final binding = router.start(_NoopHandleRuntime());
      addTearDown(binding.dispose);

      await binding.ensureInternalServicesReady();
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
      final exporterInfo = snapshotPayload['exporter'] as Map<String, Object?>?;

      expect(exporterInfo, isNotNull);
      expect(exporterInfo!.containsKey('auth_token'), isFalse);
      expect(exporterInfo['auth_required'], isFalse);
    },
  );

  test(
    'metrics exporter exposes timeout and error transport alerts across payloads and OpenMetrics',
    () async {
      final events = <Object>[];
      final metricsBefore = _buildMetricsBreakdown(
        goAwayEvents: 0,
        idleTimeoutEvents: 0,
        bodyTimeoutEvents: 0,
        protocolErrorEvents: 0,
        internalErrorEvents: 0,
        backpressureEvents: 0,
        maxBackpressureDepth: 0,
      );
      final metricsAfter = _buildMetricsBreakdown(
        goAwayEvents: 1,
        idleTimeoutEvents: 2,
        bodyTimeoutEvents: 3,
        protocolErrorEvents: 4,
        internalErrorEvents: 5,
        backpressureEvents: 0,
        maxBackpressureDepth: 0,
      );
      final runtime = _SequencedMetricsRuntime([
        metricsBefore,
        metricsAfter,
        metricsAfter,
      ]);
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
        settings: _buildSettings(),
      );

      final binding = router.start(runtime, onEvent: events.add);
      addTearDown(binding.dispose);

      await _waitForTransportAlerts(events, expected: 5);

      await binding.ensureInternalServicesReady();
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
      final routerMetrics =
          snapshotPayload['router'] as Map<String, Object?>? ?? const {};
      final transportMetrics =
          routerMetrics['transport'] as Map<String, Object?>? ?? const {};
      expect(transportMetrics['transport_alerts'], equals(5));
      expect(transportMetrics['goaway_alerts'], equals(1));
      expect(transportMetrics['idle_timeout_alerts'], equals(1));
      expect(transportMetrics['body_timeout_alerts'], equals(1));
      expect(transportMetrics['protocol_error_alerts'], equals(1));
      expect(transportMetrics['internal_error_alerts'], equals(1));

      final openMetricsResult = await metricsClient
          .call('connectanum.metrics.openmetrics')
          .first;
      final openMetricsText = openMetricsResult.arguments?.first as String;
      expect(
        openMetricsText,
        contains('connectanum_router_http_idle_timeouts_total 2'),
      );
      expect(
        openMetricsText,
        contains('connectanum_router_http_body_timeouts_total 3'),
      );
      expect(
        openMetricsText,
        contains('connectanum_router_http_protocol_errors_total 4'),
      );
      expect(
        openMetricsText,
        contains('connectanum_router_http_internal_errors_total 5'),
      );
      expect(
        openMetricsText,
        contains(
          'connectanum_router_transport_alerts_total{reason="go_away"} 1',
        ),
      );
      expect(
        openMetricsText,
        contains(
          'connectanum_router_transport_alerts_total{reason="idle_timeout"} 1',
        ),
      );
      expect(
        openMetricsText,
        contains(
          'connectanum_router_transport_alerts_total{reason="body_timeout"} 1',
        ),
      );
      expect(
        openMetricsText,
        contains(
          'connectanum_router_transport_alerts_total{reason="protocol_error"} 1',
        ),
      );
      expect(
        openMetricsText,
        contains(
          'connectanum_router_transport_alerts_total{reason="internal_error"} 1',
        ),
      );
      expect(
        openMetricsText,
        contains(
          'connectanum_router_transport_alerts_by_listener_total{listener_id="1",protocol="http2",endpoint="127.0.0.1:5001",reason="idle_timeout"} 1',
        ),
      );
      expect(
        openMetricsText,
        contains(
          'connectanum_router_transport_alerts_by_listener_total{listener_id="1",protocol="http2",endpoint="127.0.0.1:5001",reason="body_timeout"} 1',
        ),
      );
      expect(
        openMetricsText,
        contains(
          'connectanum_router_transport_alerts_by_listener_total{listener_id="1",protocol="http2",endpoint="127.0.0.1:5001",reason="protocol_error"} 1',
        ),
      );
      expect(
        openMetricsText,
        contains(
          'connectanum_router_transport_alerts_by_listener_total{listener_id="1",protocol="http2",endpoint="127.0.0.1:5001",reason="internal_error"} 1',
        ),
      );

      final transportAlerts =
          snapshotPayload['alerts'] as Map<String, Object?>?;
      expect(transportAlerts, isNotNull);
      expect(transportAlerts!['transport'], equals(5));
      expect(transportAlerts['goaway'], equals(1));
      expect(transportAlerts['idle_timeout'], equals(1));
      expect(transportAlerts['body_timeout'], equals(1));
      expect(transportAlerts['protocol_error'], equals(1));
      expect(transportAlerts['internal_error'], equals(1));
      expect(transportAlerts['active_throttles'], equals(1));

      final byListener =
          transportAlerts['by_listener'] as List<Object?>? ?? const [];
      final entry = byListener.whereType<Map<String, Object?>>().firstWhere(
        (value) => value['listener_id'] == 1,
        orElse: () => const {},
      );
      expect(entry['transport'], equals(5));
      expect(entry['goaway'], equals(1));
      expect(entry['idle_timeout'], equals(1));
      expect(entry['body_timeout'], equals(1));
      expect(entry['protocol_error'], equals(1));
      expect(entry['internal_error'], equals(1));
      expect(entry['last_alert_reason'], equals('internal_error'));
      expect(entry['last_new_events'], equals(5));
      expect(entry['last_total_events'], equals(5));

      final alertEvents = events
          .whereType<Map<String, Object?>>()
          .where((event) => event['type'] == 'listener_transport_alert')
          .toList(growable: false);
      expect(alertEvents, hasLength(5));
      final reasons = {
        for (final alert in alertEvents) alert['reason']: alert['newEvents'],
      };
      expect(
        reasons,
        equals({
          'go_away': 1,
          'idle_timeout': 2,
          'body_timeout': 3,
          'protocol_error': 4,
          'internal_error': 5,
        }),
      );
    },
  );
}

Future<void> _waitForTransportAlert(List<Object> events) async {
  await _waitForTransportAlerts(events, expected: 1);
}

Future<void> _waitForTransportAlerts(
  List<Object> events, {
  required int expected,
}) async {
  const attempts = 50;
  for (var i = 0; i < attempts; i += 1) {
    final count = events
        .whereType<Map<String, Object?>>()
        .where((event) => event['type'] == 'listener_transport_alert')
        .length;
    if (count >= expected) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

NativeRouterMetrics _buildMetricsBreakdown({
  int goAwayEvents = 1,
  int idleTimeoutEvents = 2,
  int bodyTimeoutEvents = 1,
  int protocolErrorEvents = 0,
  int internalErrorEvents = 0,
  int backpressureEvents = 3,
  int maxBackpressureDepth = 4,
}) => NativeRouterMetrics(
  totalEvents:
      goAwayEvents +
      idleTimeoutEvents +
      bodyTimeoutEvents +
      protocolErrorEvents +
      internalErrorEvents +
      backpressureEvents +
      8,
  gracefulEvents: 8,
  goAwayEvents: goAwayEvents,
  idleTimeoutEvents: idleTimeoutEvents,
  bodyTimeoutEvents: bodyTimeoutEvents,
  protocolErrorEvents: protocolErrorEvents,
  internalErrorEvents: internalErrorEvents,
  backpressureEvents: backpressureEvents,
  maxBackpressureDepth: maxBackpressureDepth,
  breakdown: [
    NativeRouterMetricsBreakdown(
      listenerId: 1,
      protocol: NativeConnectionProtocol.http2,
      totalEvents:
          goAwayEvents +
          idleTimeoutEvents +
          bodyTimeoutEvents +
          protocolErrorEvents +
          internalErrorEvents +
          backpressureEvents +
          8,
      gracefulEvents: 8,
      goAwayEvents: goAwayEvents,
      idleTimeoutEvents: idleTimeoutEvents,
      bodyTimeoutEvents: bodyTimeoutEvents,
      protocolErrorEvents: protocolErrorEvents,
      internalErrorEvents: internalErrorEvents,
      backpressureEvents: backpressureEvents,
      maxBackpressureDepth: maxBackpressureDepth,
    ),
  ],
);

RouterSettings _buildSettings({String? openMetricsAuthToken}) {
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
        realm: 'connectanum.metrics',
        authToken: openMetricsAuthToken,
      ),
      backpressure: BackpressureThrottleSettings(
        cooldown: Duration(seconds: 5),
      ),
      transportAlerts: TransportAlertSettings(cooldown: Duration(seconds: 5)),
    ),
    authenticators: const {
      'anonymous': AuthenticatorDefinition(type: 'anonymous'),
    },
    workerPool: const WorkerPoolSettings(minWorkers: 1),
  );
}

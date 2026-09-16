import 'dart:convert';

import 'package:connectanum_router/src/router/models/router_metrics.dart';
import 'package:test/test.dart';

void main() {
  test(
    'snapshot JSON preserves every counter and omits unavailable metrics',
    () {
      final snapshot = _snapshot();
      expect(snapshot.toJson(), _snapshotJson);
      expect(snapshot.copyWith().toJson(), _snapshotJson);
      expect(snapshot.copyWith(), isNot(same(snapshot)));
      expect(jsonDecode(jsonEncode(snapshot.toJson())), _snapshotJson);
    },
  );

  test(
    'snapshot copy replaces counters, time and nested metrics independently',
    () {
      final snapshot = _snapshot();
      const alerts = RouterAlertMetrics(backpressureAlerts: 7);
      const shutdown = RouterShutdownMetrics(drainInProgress: true);
      const process = RouterProcessMetrics(
        processId: 101,
        currentRssBytes: 4294967297,
        maxRssBytes: 8589934593,
      );
      final changed = snapshot.copyWith(
        timestamp: DateTime.utc(2026, 9, 17, 1, 2, 3),
        realmCount: 21,
        sessionCount: 22,
        subscriptionCount: 23,
        registrationCount: 24,
        pendingInvocationCount: 25,
        totalInvocationsDispatched: 26,
        totalPublicationsRouted: 27,
        retryDeduplicationActiveCount: 28,
        totalRetryDeduplicationThrottleRejects: 29,
        totalRetryDeduplicationDebounceReplacements: 30,
        totalRetryDeduplicationCapacityRejects: 31,
        totalRetryDeduplicationExpirations: 32,
        activeConnections: 33,
        workerCount: 34,
        alerts: alerts,
        shutdown: shutdown,
        process: process,
        transport: _transport,
      );
      expect(changed.toJson(), {
        'timestamp': '2026-09-17T01:02:03.000Z',
        'realm_count': 21,
        'session_count': 22,
        'subscription_count': 23,
        'registration_count': 24,
        'pending_invocation_count': 25,
        'total_invocations_dispatched': 26,
        'total_publications_routed': 27,
        'retry_deduplication_active_count': 28,
        'total_retry_deduplication_throttle_rejects': 29,
        'total_retry_deduplication_debounce_replacements': 30,
        'total_retry_deduplication_capacity_rejects': 31,
        'total_retry_deduplication_expirations': 32,
        'active_connections': 33,
        'worker_count': 34,
        'shutdown': {..._shutdownJson, 'drain_in_progress': true},
        'alerts': {..._alertsJson, 'backpressure_alerts': 7},
        'process': {
          'pid': 101,
          'current_rss_bytes': 4294967297,
          'max_rss_bytes': 8589934593,
        },
        'transport': _transportJson,
      });
      expect(changed.copyWith().toJson(), changed.toJson());
      expect(
        changed.copyWith(process: null, transport: null).process,
        same(process),
      );
      expect(
        changed.copyWith(process: null, transport: null).transport,
        same(_transport),
      );
      expect(changed.copyWith(realmCount: 0).realmCount, 0);
      expect(snapshot.toJson(), _snapshotJson);
    },
  );

  test(
    'shutdown distinguishes absent duration from zero and formats timestamps',
    () {
      expect(const RouterShutdownMetrics().toJson(), _shutdownJson);
      final shutdown = RouterShutdownMetrics(
        drainInProgress: true,
        drainTotal: 12,
        drainTimeouts: 3,
        closedListenersTotal: 4,
        closedPendingConnectionsTotal: 5,
        lastDrainDurationMs: 0,
        drainStartedAtUtc: DateTime.parse('2026-09-16T12:00:00+02:00'),
        drainDeadlineAtUtc: DateTime.utc(2026, 9, 16, 10, 0, 1),
      );
      expect(shutdown.toJson(), {
        'drain_in_progress': true,
        'drain_total': 12,
        'drain_timeouts': 3,
        'closed_listeners_total': 4,
        'closed_pending_connections_total': 5,
        'last_drain_duration_ms': 0,
        'drain_started_at': '2026-09-16T10:00:00.000Z',
        'drain_deadline_at': '2026-09-16T10:00:01.000Z',
      });
    },
  );

  test('backpressure reasons are present only when populated', () {
    expect(const RouterAlertMetrics().toJson(), _alertsJson);
    expect(
      const RouterAlertMetrics(
        backpressureAlerts: 13,
        throttledBackpressureAlerts: 7,
        backpressureAlertReasons: {'depth': 5, 'burst': 8},
      ).toJson(),
      {
        'backpressure_alerts': 13,
        'throttled_backpressure_alerts': 7,
        'backpressure_alert_reasons': {'depth': 5, 'burst': 8},
      },
    );
  });

  test('HTTP telemetry uses stable keys and keeps every counter distinct', () {
    expect(_response.toJson(), _responseJson);
    expect(_request.toJson(), _requestJson);
    expect(jsonDecode(jsonEncode(_response.toJson())), _responseJson);
    expect(jsonDecode(jsonEncode(_request.toJson())), _requestJson);
  });

  test(
    'transport JSON distinguishes absent groups and zero active throttles',
    () {
      expect(_transport.toJson(), _transportJson);
      expect(_transport.copyWith().toJson(), _transportJson);
      expect(_transport.activeThrottles, isEmpty);
      expect(_transport.activeThrottleCount, 0);
    },
  );

  test(
    'transport copy replaces every counter and preserves stream metrics',
    () {
      final original = _transport.copyWith(
        httpResponseStream: _response,
        httpRequestBodyStream: _request,
        alertBreakdown: [_alert(active: true)],
        breakdown: [_breakdown],
      );
      final changed = original.copyWith(
        totalEvents: 21,
        gracefulEvents: 22,
        goAwayEvents: 23,
        idleTimeoutEvents: 24,
        bodyTimeoutEvents: 25,
        protocolErrorEvents: 26,
        internalErrorEvents: 27,
        backpressureEvents: 28,
        maxBackpressureDepth: 29,
        backpressureAlerts: 30,
        transportAlerts: 31,
        goAwayAlerts: 32,
        idleTimeoutAlerts: 33,
        bodyTimeoutAlerts: 34,
        protocolErrorAlerts: 35,
        internalErrorAlerts: 36,
        rawSocketZeroCopyCallsTotal: 37,
        rawSocketZeroCopyBytesTotal: 38,
        bufferedFileSegmentCallsTotal: 39,
        bufferedFileSegmentBytesTotal: 40,
        alertBreakdown: [],
        breakdown: [],
      );
      expect(changed.toJson(), {
        'total_events': 21,
        'graceful_events': 22,
        'goaway_events': 23,
        'idle_timeout_events': 24,
        'body_timeout_events': 25,
        'protocol_error_events': 26,
        'internal_error_events': 27,
        'backpressure_events': 28,
        'max_backpressure_depth': 29,
        'backpressure_alerts': 30,
        'transport_alerts': 31,
        'goaway_alerts': 32,
        'idle_timeout_alerts': 33,
        'body_timeout_alerts': 34,
        'protocol_error_alerts': 35,
        'internal_error_alerts': 36,
        'rawsocket_zero_copy_calls_total': 37,
        'rawsocket_zero_copy_bytes_total': 38,
        'buffered_file_segment_calls_total': 39,
        'buffered_file_segment_bytes_total': 40,
        'active_throttles': 0,
        'http_response_stream': _responseJson,
        'http_request_body_stream': _requestJson,
      });
      expect(changed.copyWith().toJson(), changed.toJson());
      expect(changed.copyWith(totalEvents: 0).totalEvents, 0);
      expect(original.totalEvents, 1);
      expect(original.activeThrottleCount, 1);
      expect(original.breakdown, [_breakdown]);
    },
  );

  test(
    'active throttle selection preserves order and isolates returned list',
    () {
      final inactive = _alert(active: false, id: 1);
      final first = _alert(active: true, id: 2);
      final second = _alert(active: true, id: 3);
      final metrics = _transport.copyWith(
        alertBreakdown: [inactive, first, second],
        breakdown: [_breakdown],
      );
      expect(metrics.activeThrottleCount, 2);
      expect(metrics.activeThrottles, [first, second]);
      final selected = metrics.activeThrottles;
      selected[0] = inactive;
      expect(metrics.activeThrottles, [first, second]);
      final encoded = metrics.toJson();
      expect(
        (encoded['active_throttle_listeners'] as List).map(
          (entry) => entry['listener_id'],
        ),
        [2, 3],
      );
      expect(
        (encoded['alert_breakdown'] as List).map(
          (entry) => entry['listener_id'],
        ),
        [1, 2, 3],
      );
      expect(encoded['by_listener_protocol'], [_breakdownJson]);
      final inactiveOnly = metrics.copyWith(alertBreakdown: [inactive]);
      expect(inactiveOnly.activeThrottleCount, 0);
      expect(
        inactiveOnly.toJson(),
        isNot(contains('active_throttle_listeners')),
      );
      expect(inactiveOnly.toJson()['alert_breakdown'], hasLength(1));
    },
  );

  test(
    'listener alert total excludes backpressure and retains optional zeros',
    () {
      final minimal = _alert(active: false);
      expect(minimal.transportAlerts, 28);
      expect(minimal.toJson(), _alertJson);
      final populated = RouterTransportAlertBreakdown(
        listenerId: 41,
        protocol: 'websocket',
        endpoint: '127.0.0.1:8081',
        backpressureAlerts: 100,
        goAwayAlerts: 2,
        idleTimeoutAlerts: 3,
        bodyTimeoutAlerts: 5,
        protocolErrorAlerts: 7,
        internalErrorAlerts: 11,
        throttleActive: true,
        throttleRemainingMs: 0,
        throttleUntil: DateTime.utc(2026, 9, 16, 10, 1),
        lastAlertAt: DateTime.utc(2026, 9, 16, 10),
        lastAlertCategory: '',
        lastAlertReason: 'burst',
        lastNewEvents: 0,
        lastTotalEvents: 25,
      );
      expect(populated.toJson(), {
        ..._alertJson,
        'throttle_active': true,
        'throttle_remaining_ms': 0,
        'throttle_until': '2026-09-16T10:01:00.000Z',
        'last_alert_at': '2026-09-16T10:00:00.000Z',
        'last_alert_category': '',
        'last_alert_reason': 'burst',
        'last_new_events': 0,
        'last_total_events': 25,
      });
      expect(_breakdown.toJson(), _breakdownJson);
    },
  );

  test('unspecified throttle is inactive even with backpressure alerts', () {
    const alert = RouterTransportAlertBreakdown(
      listenerId: 5,
      protocol: 'rawsocket',
      endpoint: '127.0.0.1:8082',
      backpressureAlerts: 99,
      goAwayAlerts: 0,
      idleTimeoutAlerts: 0,
      bodyTimeoutAlerts: 0,
      protocolErrorAlerts: 0,
      internalErrorAlerts: 0,
    );
    expect(alert.throttleActive, isFalse);
    expect(alert.transportAlerts, 0);
    final metrics = _transport.copyWith(alertBreakdown: [alert]);
    expect(metrics.activeThrottleCount, 0);
    expect(metrics.activeThrottles, isEmpty);
    expect(metrics.toJson(), isNot(contains('active_throttle_listeners')));
    expect(alert.toJson()['backpressure_alerts'], 99);
    expect(alert.toJson()['throttle_active'], isFalse);
  });
}

RouterMetricsSnapshot _snapshot() => RouterMetricsSnapshot(
  timestamp: DateTime.utc(2026, 9, 16),
  realmCount: 1,
  sessionCount: 2,
  subscriptionCount: 3,
  registrationCount: 4,
  pendingInvocationCount: 5,
  totalInvocationsDispatched: 6,
  totalPublicationsRouted: 7,
  retryDeduplicationActiveCount: 8,
  totalRetryDeduplicationThrottleRejects: 9,
  totalRetryDeduplicationDebounceReplacements: 10,
  totalRetryDeduplicationCapacityRejects: 11,
  totalRetryDeduplicationExpirations: 12,
  activeConnections: 13,
  workerCount: 14,
);

const _shutdownJson = <String, Object?>{
  'drain_in_progress': false,
  'drain_total': 0,
  'drain_timeouts': 0,
  'closed_listeners_total': 0,
  'closed_pending_connections_total': 0,
};
const _alertsJson = <String, Object?>{
  'backpressure_alerts': 0,
  'throttled_backpressure_alerts': 0,
};
const _snapshotJson = <String, Object?>{
  'timestamp': '2026-09-16T00:00:00.000Z',
  'realm_count': 1,
  'session_count': 2,
  'subscription_count': 3,
  'registration_count': 4,
  'pending_invocation_count': 5,
  'total_invocations_dispatched': 6,
  'total_publications_routed': 7,
  'retry_deduplication_active_count': 8,
  'total_retry_deduplication_throttle_rejects': 9,
  'total_retry_deduplication_debounce_replacements': 10,
  'total_retry_deduplication_capacity_rejects': 11,
  'total_retry_deduplication_expirations': 12,
  'active_connections': 13,
  'worker_count': 14,
  'shutdown': _shutdownJson,
  'alerts': _alertsJson,
};

const _transport = RouterTransportMetrics(
  totalEvents: 1,
  gracefulEvents: 2,
  goAwayEvents: 3,
  idleTimeoutEvents: 4,
  bodyTimeoutEvents: 5,
  protocolErrorEvents: 6,
  internalErrorEvents: 7,
  backpressureEvents: 8,
  maxBackpressureDepth: 9,
  backpressureAlerts: 10,
  transportAlerts: 11,
  goAwayAlerts: 12,
  idleTimeoutAlerts: 13,
  bodyTimeoutAlerts: 14,
  protocolErrorAlerts: 15,
  internalErrorAlerts: 16,
  rawSocketZeroCopyCallsTotal: 17,
  rawSocketZeroCopyBytesTotal: 18,
  bufferedFileSegmentCallsTotal: 19,
  bufferedFileSegmentBytesTotal: 20,
);
const _transportJson = <String, Object?>{
  'total_events': 1,
  'graceful_events': 2,
  'goaway_events': 3,
  'idle_timeout_events': 4,
  'body_timeout_events': 5,
  'protocol_error_events': 6,
  'internal_error_events': 7,
  'backpressure_events': 8,
  'max_backpressure_depth': 9,
  'backpressure_alerts': 10,
  'transport_alerts': 11,
  'goaway_alerts': 12,
  'idle_timeout_alerts': 13,
  'body_timeout_alerts': 14,
  'protocol_error_alerts': 15,
  'internal_error_alerts': 16,
  'rawsocket_zero_copy_calls_total': 17,
  'rawsocket_zero_copy_bytes_total': 18,
  'buffered_file_segment_calls_total': 19,
  'buffered_file_segment_bytes_total': 20,
  'active_throttles': 0,
};

RouterTransportAlertBreakdown _alert({required bool active, int id = 41}) =>
    RouterTransportAlertBreakdown(
      listenerId: id,
      protocol: 'websocket',
      endpoint: '127.0.0.1:8081',
      backpressureAlerts: 100,
      goAwayAlerts: 2,
      idleTimeoutAlerts: 3,
      bodyTimeoutAlerts: 5,
      protocolErrorAlerts: 7,
      internalErrorAlerts: 11,
      throttleActive: active,
    );
const _alertJson = <String, Object?>{
  'listener_id': 41,
  'protocol': 'websocket',
  'endpoint': '127.0.0.1:8081',
  'backpressure_alerts': 100,
  'goaway_alerts': 2,
  'idle_timeout_alerts': 3,
  'body_timeout_alerts': 5,
  'protocol_error_alerts': 7,
  'internal_error_alerts': 11,
  'transport_alerts': 28,
  'throttle_active': false,
};
const _breakdown = RouterTransportMetricsBreakdown(
  listenerId: 51,
  protocol: 'rawsocket',
  endpoint: '127.0.0.1:8082',
  totalEvents: 1,
  gracefulEvents: 2,
  goAwayEvents: 3,
  idleTimeoutEvents: 4,
  bodyTimeoutEvents: 5,
  protocolErrorEvents: 6,
  internalErrorEvents: 7,
  backpressureEvents: 8,
  maxBackpressureDepth: 9,
);
const _breakdownJson = <String, Object?>{
  'listener_id': 51,
  'protocol': 'rawsocket',
  'endpoint': '127.0.0.1:8082',
  'total_events': 1,
  'graceful_events': 2,
  'goaway_events': 3,
  'idle_timeout_events': 4,
  'body_timeout_events': 5,
  'protocol_error_events': 6,
  'internal_error_events': 7,
  'backpressure_events': 8,
  'max_backpressure_depth': 9,
};

const _response = RouterHttpResponseStreamMetrics(
  streamingResponsesTotal: 1,
  streamOpenToHeadersSendSamplesTotal: 2,
  streamOpenToHeadersSendUsTotal: 3,
  headersSendCallSamplesTotal: 4,
  headersSendCallUsTotal: 5,
  headersToFirstConnectionWriteSamplesTotal: 6,
  headersToFirstConnectionWriteUsTotal: 7,
  headersToFirstConnectionWriteGe1msTotal: 8,
  headersToFirstConnectionWriteGe5msTotal: 9,
  headersToFirstConnectionWriteGe10msTotal: 10,
  firstChunkChannelWaitSamplesTotal: 11,
  firstChunkChannelWaitUsTotal: 12,
  firstChunkChannelWaitGe1msTotal: 13,
  firstChunkChannelWaitGe5msTotal: 14,
  firstChunkChannelWaitGe10msTotal: 15,
  headersToFirstChunkDequeueSamplesTotal: 16,
  headersToFirstChunkDequeueUsTotal: 17,
  headersToFirstChunkDequeueGe1msTotal: 18,
  headersToFirstChunkDequeueGe5msTotal: 19,
  headersToFirstChunkDequeueGe10msTotal: 20,
  firstChunkSendCallSamplesTotal: 21,
  firstChunkSendCallUsTotal: 22,
  firstChunkSendCallGe1msTotal: 23,
  firstChunkSendCallGe5msTotal: 24,
  firstChunkSendCallGe10msTotal: 25,
  headersToFirstChunkSendCallSamplesTotal: 26,
  headersToFirstChunkSendCallUsTotal: 27,
  tailChunkChannelWaitSamplesTotal: 28,
  tailChunkChannelWaitUsTotal: 29,
  tailChunkChannelWaitGe1msTotal: 30,
  tailChunkChannelWaitGe5msTotal: 31,
  tailChunkChannelWaitGe10msTotal: 32,
  tailChunkSendCallSamplesTotal: 33,
  tailChunkSendCallUsTotal: 34,
  tailChunkSendCallGe1msTotal: 35,
  tailChunkSendCallGe5msTotal: 36,
  tailChunkSendCallGe10msTotal: 37,
  firstToLastChunkSendSamplesTotal: 38,
  firstToLastChunkSendUsTotal: 39,
  firstToLastChunkSendGe1msTotal: 40,
  firstToLastChunkSendGe5msTotal: 41,
  firstToLastChunkSendGe10msTotal: 42,
);
const _responseJson = <String, Object?>{
  'streaming_responses_total': 1,
  'stream_open_to_headers_send_samples_total': 2,
  'stream_open_to_headers_send_us_total': 3,
  'headers_send_call_samples_total': 4,
  'headers_send_call_us_total': 5,
  'headers_to_first_connection_write_samples_total': 6,
  'headers_to_first_connection_write_us_total': 7,
  'headers_to_first_connection_write_ge_1ms_total': 8,
  'headers_to_first_connection_write_ge_5ms_total': 9,
  'headers_to_first_connection_write_ge_10ms_total': 10,
  'first_chunk_channel_wait_samples_total': 11,
  'first_chunk_channel_wait_us_total': 12,
  'first_chunk_channel_wait_ge_1ms_total': 13,
  'first_chunk_channel_wait_ge_5ms_total': 14,
  'first_chunk_channel_wait_ge_10ms_total': 15,
  'headers_to_first_chunk_dequeue_samples_total': 16,
  'headers_to_first_chunk_dequeue_us_total': 17,
  'headers_to_first_chunk_dequeue_ge_1ms_total': 18,
  'headers_to_first_chunk_dequeue_ge_5ms_total': 19,
  'headers_to_first_chunk_dequeue_ge_10ms_total': 20,
  'first_chunk_send_call_samples_total': 21,
  'first_chunk_send_call_us_total': 22,
  'first_chunk_send_call_ge_1ms_total': 23,
  'first_chunk_send_call_ge_5ms_total': 24,
  'first_chunk_send_call_ge_10ms_total': 25,
  'headers_to_first_chunk_send_call_samples_total': 26,
  'headers_to_first_chunk_send_call_us_total': 27,
  'tail_chunk_channel_wait_samples_total': 28,
  'tail_chunk_channel_wait_us_total': 29,
  'tail_chunk_channel_wait_ge_1ms_total': 30,
  'tail_chunk_channel_wait_ge_5ms_total': 31,
  'tail_chunk_channel_wait_ge_10ms_total': 32,
  'tail_chunk_send_call_samples_total': 33,
  'tail_chunk_send_call_us_total': 34,
  'tail_chunk_send_call_ge_1ms_total': 35,
  'tail_chunk_send_call_ge_5ms_total': 36,
  'tail_chunk_send_call_ge_10ms_total': 37,
  'first_to_last_chunk_send_samples_total': 38,
  'first_to_last_chunk_send_us_total': 39,
  'first_to_last_chunk_send_ge_1ms_total': 40,
  'first_to_last_chunk_send_ge_5ms_total': 41,
  'first_to_last_chunk_send_ge_10ms_total': 42,
};
const _request = RouterHttpRequestBodyStreamMetrics(
  streamingRequestsTotal: 1,
  dataChunkSamplesTotal: 2,
  dataChunkWaitUsTotal: 3,
  firstChunkWaitSamplesTotal: 4,
  firstChunkWaitUsTotal: 5,
  secondChunkWaitSamplesTotal: 6,
  secondChunkWaitUsTotal: 7,
  remainingTailReadSamplesTotal: 8,
  remainingTailReadUsTotal: 9,
  remainingTailDataWaitSamplesTotal: 10,
  remainingTailDataWaitUsTotal: 11,
  remainingTailDataWaitMaxUsTotal: 12,
  remainingTailDataWaitMaxEventIndexTotal: 13,
  remainingTailDataWaitMaxBytesBeforeTotal: 14,
  remainingTailDataWaitMaxBytesAfterTotal: 15,
  remainingTailDataWaitMaxEofTotal: 16,
  remainingTailDataWaitMaxAvailableCapacityBeforeTotal: 17,
  remainingTailDataWaitMaxUsedCapacityBeforeTotal: 18,
  remainingTailDataWaitMaxAvailableCapacityAfterDataTotal: 19,
  remainingTailDataWaitMaxUsedCapacityAfterDataTotal: 20,
  remainingTailDataWaitMaxAvailableCapacityAfterReleaseTotal: 21,
  remainingTailDataWaitMaxUsedCapacityAfterReleaseTotal: 22,
  totalReadSamplesTotal: 23,
  totalReadUsTotal: 24,
);
const _requestJson = <String, Object?>{
  'streaming_requests_total': 1,
  'data_chunk_samples_total': 2,
  'data_chunk_wait_us_total': 3,
  'first_chunk_wait_samples_total': 4,
  'first_chunk_wait_us_total': 5,
  'second_chunk_wait_samples_total': 6,
  'second_chunk_wait_us_total': 7,
  'remaining_tail_read_samples_total': 8,
  'remaining_tail_read_us_total': 9,
  'remaining_tail_data_wait_samples_total': 10,
  'remaining_tail_data_wait_us_total': 11,
  'remaining_tail_data_wait_max_us_total': 12,
  'remaining_tail_data_wait_max_event_index_total': 13,
  'remaining_tail_data_wait_max_bytes_before_total': 14,
  'remaining_tail_data_wait_max_bytes_after_total': 15,
  'remaining_tail_data_wait_max_eof_total': 16,
  'remaining_tail_data_wait_max_available_capacity_before_total': 17,
  'remaining_tail_data_wait_max_used_capacity_before_total': 18,
  'remaining_tail_data_wait_max_available_capacity_after_data_total': 19,
  'remaining_tail_data_wait_max_used_capacity_after_data_total': 20,
  'remaining_tail_data_wait_max_available_capacity_after_release_total': 21,
  'remaining_tail_data_wait_max_used_capacity_after_release_total': 22,
  'total_read_samples_total': 23,
  'total_read_us_total': 24,
};

import 'package:meta/meta.dart';

/// A snapshot of router-wide metrics captured at a single point in time.
@immutable
class RouterMetricsSnapshot {
  const RouterMetricsSnapshot({
    required this.timestamp,
    required this.realmCount,
    required this.sessionCount,
    required this.subscriptionCount,
    required this.registrationCount,
    required this.pendingInvocationCount,
    required this.totalInvocationsDispatched,
    required this.totalPublicationsRouted,
    required this.activeConnections,
    required this.workerCount,
    this.workerLoad = const <RouterWorkerLoadMetrics>[],
    this.shutdown = const RouterShutdownMetrics(),
    this.alerts = const RouterAlertMetrics(),
    this.process,
    this.transport,
  });

  /// Time when the snapshot was collected.
  final DateTime timestamp;

  /// Number of realms currently tracked by the state store.
  final int realmCount;

  /// Number of active sessions across all realms.
  final int sessionCount;

  /// Number of active subscriptions across all realms.
  final int subscriptionCount;

  /// Number of active procedure registrations across all realms.
  final int registrationCount;

  /// Count of pending invocations awaiting completion.
  final int pendingInvocationCount;

  /// Total invocations dispatched since router start.
  final int totalInvocationsDispatched;

  /// Total publications routed since router start.
  final int totalPublicationsRouted;

  /// Number of TCP connections currently assigned to workers.
  final int activeConnections;

  /// Number of worker isolates currently running.
  final int workerCount;

  /// Per-worker load counters captured by the boss isolate.
  final List<RouterWorkerLoadMetrics> workerLoad;

  /// Graceful shutdown/drain state owned by the binding.
  final RouterShutdownMetrics shutdown;

  /// Aggregated alert counters emitted by the boss loop (backpressure, etc.).
  final RouterAlertMetrics alerts;

  /// Process-level runtime metrics collected by the binding isolate.
  final RouterProcessMetrics? process;

  /// Aggregated transport-level metrics emitted by the native runtime.
  final RouterTransportMetrics? transport;

  RouterMetricsSnapshot copyWith({
    DateTime? timestamp,
    int? realmCount,
    int? sessionCount,
    int? subscriptionCount,
    int? registrationCount,
    int? pendingInvocationCount,
    int? totalInvocationsDispatched,
    int? totalPublicationsRouted,
    int? activeConnections,
    int? workerCount,
    List<RouterWorkerLoadMetrics>? workerLoad,
    RouterShutdownMetrics? shutdown,
    RouterAlertMetrics? alerts,
    RouterProcessMetrics? process,
    RouterTransportMetrics? transport,
  }) {
    return RouterMetricsSnapshot(
      timestamp: timestamp ?? this.timestamp,
      realmCount: realmCount ?? this.realmCount,
      sessionCount: sessionCount ?? this.sessionCount,
      subscriptionCount: subscriptionCount ?? this.subscriptionCount,
      registrationCount: registrationCount ?? this.registrationCount,
      pendingInvocationCount:
          pendingInvocationCount ?? this.pendingInvocationCount,
      totalInvocationsDispatched:
          totalInvocationsDispatched ?? this.totalInvocationsDispatched,
      totalPublicationsRouted:
          totalPublicationsRouted ?? this.totalPublicationsRouted,
      activeConnections: activeConnections ?? this.activeConnections,
      workerCount: workerCount ?? this.workerCount,
      workerLoad: workerLoad ?? this.workerLoad,
      shutdown: shutdown ?? this.shutdown,
      alerts: alerts ?? this.alerts,
      process: process ?? this.process,
      transport: transport ?? this.transport,
    );
  }

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'realm_count': realmCount,
    'session_count': sessionCount,
    'subscription_count': subscriptionCount,
    'registration_count': registrationCount,
    'pending_invocation_count': pendingInvocationCount,
    'total_invocations_dispatched': totalInvocationsDispatched,
    'total_publications_routed': totalPublicationsRouted,
    'active_connections': activeConnections,
    'worker_count': workerCount,
    'workers': workerLoad
        .map((worker) => worker.toJson())
        .toList(growable: false),
    'shutdown': shutdown.toJson(),
    'alerts': alerts.toJson(),
    if (process != null) 'process': process!.toJson(),
    if (transport != null) 'transport': transport!.toJson(),
  };
}

/// Per-worker load counters observed by the router boss.
@immutable
class RouterWorkerLoadMetrics {
  const RouterWorkerLoadMetrics({
    required this.id,
    required this.isolateHash,
    required this.connectionCount,
    required this.busy,
    required this.inFlightDispatches,
    required this.pendingDispatches,
    required this.dispatchesTotal,
    required this.queuedDispatchesTotal,
    required this.completedDispatchesTotal,
    required this.errorsTotal,
    required this.totalBusyDurationMs,
    required this.totalQueueLatencyMs,
    required this.maxPendingDispatches,
    this.currentBusyDurationMs,
    this.lastDispatchDurationMs,
    this.oldestPendingDispatchAgeMs,
    this.lastQueueLatencyMs,
  });

  /// Stable worker identifier allocated by the boss.
  final int id;

  /// VM isolate hash, useful for correlating worker lifecycle events.
  final int isolateHash;

  /// Number of live connections currently assigned to this worker.
  final int connectionCount;

  /// Whether the worker is currently processing a dispatched native message.
  final bool busy;

  /// Current dispatches in flight on this worker.
  final int inFlightDispatches;

  /// Native message handles prefetched by the boss and waiting for dispatch.
  final int pendingDispatches;

  /// Total native message dispatches assigned to this worker.
  final int dispatchesTotal;

  /// Total native message handles prefetched into the worker dispatch queue.
  final int queuedDispatchesTotal;

  /// Dispatches that reported completion or error.
  final int completedDispatchesTotal;

  /// Dispatches that reported a worker error.
  final int errorsTotal;

  /// Total observed worker busy time in milliseconds.
  final int totalBusyDurationMs;

  /// Total observed time native message handles spent queued before dispatch.
  final int totalQueueLatencyMs;

  /// Highest observed boss-side pending dispatch queue depth.
  final int maxPendingDispatches;

  /// Current in-flight dispatch duration in milliseconds, when busy.
  final int? currentBusyDurationMs;

  /// Most recent completed dispatch duration in milliseconds.
  final int? lastDispatchDurationMs;

  /// Age in milliseconds of the oldest currently pending dispatch, when any.
  final int? oldestPendingDispatchAgeMs;

  /// Most recent boss-side queue latency in milliseconds.
  final int? lastQueueLatencyMs;

  Map<String, Object?> toJson() => {
    'id': id,
    'isolate_hash': isolateHash,
    'connection_count': connectionCount,
    'busy': busy,
    'in_flight_dispatches': inFlightDispatches,
    'pending_dispatches': pendingDispatches,
    'dispatches_total': dispatchesTotal,
    'queued_dispatches_total': queuedDispatchesTotal,
    'completed_dispatches_total': completedDispatchesTotal,
    'errors_total': errorsTotal,
    'total_busy_duration_ms': totalBusyDurationMs,
    'total_queue_latency_ms': totalQueueLatencyMs,
    'max_pending_dispatches': maxPendingDispatches,
    if (currentBusyDurationMs != null)
      'current_busy_duration_ms': currentBusyDurationMs,
    if (lastDispatchDurationMs != null)
      'last_dispatch_duration_ms': lastDispatchDurationMs,
    if (oldestPendingDispatchAgeMs != null)
      'oldest_pending_dispatch_age_ms': oldestPendingDispatchAgeMs,
    if (lastQueueLatencyMs != null) 'last_queue_latency_ms': lastQueueLatencyMs,
  };
}

/// Process-level metrics for the router VM process.
@immutable
class RouterProcessMetrics {
  const RouterProcessMetrics({
    required this.processId,
    required this.currentRssBytes,
    required this.maxRssBytes,
  });

  /// Operating-system process identifier.
  final int processId;

  /// Current resident set size in bytes.
  final int currentRssBytes;

  /// Maximum resident set size observed by the process in bytes.
  final int maxRssBytes;

  Map<String, Object?> toJson() => {
    'pid': processId,
    'current_rss_bytes': currentRssBytes,
    'max_rss_bytes': maxRssBytes,
  };
}

/// Shutdown/drain counters emitted by the binding.
@immutable
class RouterShutdownMetrics {
  const RouterShutdownMetrics({
    this.drainInProgress = false,
    this.drainTotal = 0,
    this.drainTimeouts = 0,
    this.closedListenersTotal = 0,
    this.closedPendingConnectionsTotal = 0,
    this.lastDrainDurationMs,
    this.drainStartedAtUtc,
    this.drainDeadlineAtUtc,
  });

  final bool drainInProgress;
  final int drainTotal;
  final int drainTimeouts;
  final int closedListenersTotal;
  final int closedPendingConnectionsTotal;
  final int? lastDrainDurationMs;
  final DateTime? drainStartedAtUtc;
  final DateTime? drainDeadlineAtUtc;

  Map<String, Object?> toJson() => {
    'drain_in_progress': drainInProgress,
    'drain_total': drainTotal,
    'drain_timeouts': drainTimeouts,
    'closed_listeners_total': closedListenersTotal,
    'closed_pending_connections_total': closedPendingConnectionsTotal,
    if (lastDrainDurationMs != null)
      'last_drain_duration_ms': lastDrainDurationMs,
    if (drainStartedAtUtc != null)
      'drain_started_at': drainStartedAtUtc!.toIso8601String(),
    if (drainDeadlineAtUtc != null)
      'drain_deadline_at': drainDeadlineAtUtc!.toIso8601String(),
  };
}

/// Alert counters produced by the boss telemetry loop.
@immutable
class RouterAlertMetrics {
  const RouterAlertMetrics({
    this.backpressureAlerts = 0,
    this.throttledBackpressureAlerts = 0,
    this.backpressureAlertReasons = const <String, int>{},
  });

  /// Total listener backpressure alerts emitted by the boss loop.
  final int backpressureAlerts;

  /// Alerts that triggered throttling (depth threshold exceeded).
  final int throttledBackpressureAlerts;

  /// Alert counts grouped by reason (e.g. depth threshold vs bursty events).
  final Map<String, int> backpressureAlertReasons;

  Map<String, Object?> toJson() => {
    'backpressure_alerts': backpressureAlerts,
    'throttled_backpressure_alerts': throttledBackpressureAlerts,
    if (backpressureAlertReasons.isNotEmpty)
      'backpressure_alert_reasons': backpressureAlertReasons,
  };
}

/// Aggregated telemetry emitted by the native transport.
@immutable
class RouterHttpResponseStreamMetrics {
  const RouterHttpResponseStreamMetrics({
    required this.streamingResponsesTotal,
    required this.streamOpenToHeadersSendSamplesTotal,
    required this.streamOpenToHeadersSendUsTotal,
    required this.headersSendCallSamplesTotal,
    required this.headersSendCallUsTotal,
    required this.headersToFirstConnectionWriteSamplesTotal,
    required this.headersToFirstConnectionWriteUsTotal,
    required this.headersToFirstConnectionWriteGe1msTotal,
    required this.headersToFirstConnectionWriteGe5msTotal,
    required this.headersToFirstConnectionWriteGe10msTotal,
    required this.firstChunkChannelWaitSamplesTotal,
    required this.firstChunkChannelWaitUsTotal,
    required this.firstChunkChannelWaitGe1msTotal,
    required this.firstChunkChannelWaitGe5msTotal,
    required this.firstChunkChannelWaitGe10msTotal,
    required this.headersToFirstChunkDequeueSamplesTotal,
    required this.headersToFirstChunkDequeueUsTotal,
    required this.headersToFirstChunkDequeueGe1msTotal,
    required this.headersToFirstChunkDequeueGe5msTotal,
    required this.headersToFirstChunkDequeueGe10msTotal,
    required this.firstChunkSendCallSamplesTotal,
    required this.firstChunkSendCallUsTotal,
    required this.firstChunkSendCallGe1msTotal,
    required this.firstChunkSendCallGe5msTotal,
    required this.firstChunkSendCallGe10msTotal,
    required this.headersToFirstChunkSendCallSamplesTotal,
    required this.headersToFirstChunkSendCallUsTotal,
    required this.tailChunkChannelWaitSamplesTotal,
    required this.tailChunkChannelWaitUsTotal,
    required this.tailChunkChannelWaitGe1msTotal,
    required this.tailChunkChannelWaitGe5msTotal,
    required this.tailChunkChannelWaitGe10msTotal,
    required this.tailChunkSendCallSamplesTotal,
    required this.tailChunkSendCallUsTotal,
    required this.tailChunkSendCallGe1msTotal,
    required this.tailChunkSendCallGe5msTotal,
    required this.tailChunkSendCallGe10msTotal,
    required this.firstToLastChunkSendSamplesTotal,
    required this.firstToLastChunkSendUsTotal,
    required this.firstToLastChunkSendGe1msTotal,
    required this.firstToLastChunkSendGe5msTotal,
    required this.firstToLastChunkSendGe10msTotal,
  });

  final int streamingResponsesTotal;
  final int streamOpenToHeadersSendSamplesTotal;
  final int streamOpenToHeadersSendUsTotal;
  final int headersSendCallSamplesTotal;
  final int headersSendCallUsTotal;
  final int headersToFirstConnectionWriteSamplesTotal;
  final int headersToFirstConnectionWriteUsTotal;
  final int headersToFirstConnectionWriteGe1msTotal;
  final int headersToFirstConnectionWriteGe5msTotal;
  final int headersToFirstConnectionWriteGe10msTotal;
  final int firstChunkChannelWaitSamplesTotal;
  final int firstChunkChannelWaitUsTotal;
  final int firstChunkChannelWaitGe1msTotal;
  final int firstChunkChannelWaitGe5msTotal;
  final int firstChunkChannelWaitGe10msTotal;
  final int headersToFirstChunkDequeueSamplesTotal;
  final int headersToFirstChunkDequeueUsTotal;
  final int headersToFirstChunkDequeueGe1msTotal;
  final int headersToFirstChunkDequeueGe5msTotal;
  final int headersToFirstChunkDequeueGe10msTotal;
  final int firstChunkSendCallSamplesTotal;
  final int firstChunkSendCallUsTotal;
  final int firstChunkSendCallGe1msTotal;
  final int firstChunkSendCallGe5msTotal;
  final int firstChunkSendCallGe10msTotal;
  final int headersToFirstChunkSendCallSamplesTotal;
  final int headersToFirstChunkSendCallUsTotal;
  final int tailChunkChannelWaitSamplesTotal;
  final int tailChunkChannelWaitUsTotal;
  final int tailChunkChannelWaitGe1msTotal;
  final int tailChunkChannelWaitGe5msTotal;
  final int tailChunkChannelWaitGe10msTotal;
  final int tailChunkSendCallSamplesTotal;
  final int tailChunkSendCallUsTotal;
  final int tailChunkSendCallGe1msTotal;
  final int tailChunkSendCallGe5msTotal;
  final int tailChunkSendCallGe10msTotal;
  final int firstToLastChunkSendSamplesTotal;
  final int firstToLastChunkSendUsTotal;
  final int firstToLastChunkSendGe1msTotal;
  final int firstToLastChunkSendGe5msTotal;
  final int firstToLastChunkSendGe10msTotal;

  Map<String, Object?> toJson() => {
    'streaming_responses_total': streamingResponsesTotal,
    'stream_open_to_headers_send_samples_total':
        streamOpenToHeadersSendSamplesTotal,
    'stream_open_to_headers_send_us_total': streamOpenToHeadersSendUsTotal,
    'headers_send_call_samples_total': headersSendCallSamplesTotal,
    'headers_send_call_us_total': headersSendCallUsTotal,
    'headers_to_first_connection_write_samples_total':
        headersToFirstConnectionWriteSamplesTotal,
    'headers_to_first_connection_write_us_total':
        headersToFirstConnectionWriteUsTotal,
    'headers_to_first_connection_write_ge_1ms_total':
        headersToFirstConnectionWriteGe1msTotal,
    'headers_to_first_connection_write_ge_5ms_total':
        headersToFirstConnectionWriteGe5msTotal,
    'headers_to_first_connection_write_ge_10ms_total':
        headersToFirstConnectionWriteGe10msTotal,
    'first_chunk_channel_wait_samples_total': firstChunkChannelWaitSamplesTotal,
    'first_chunk_channel_wait_us_total': firstChunkChannelWaitUsTotal,
    'first_chunk_channel_wait_ge_1ms_total': firstChunkChannelWaitGe1msTotal,
    'first_chunk_channel_wait_ge_5ms_total': firstChunkChannelWaitGe5msTotal,
    'first_chunk_channel_wait_ge_10ms_total': firstChunkChannelWaitGe10msTotal,
    'headers_to_first_chunk_dequeue_samples_total':
        headersToFirstChunkDequeueSamplesTotal,
    'headers_to_first_chunk_dequeue_us_total':
        headersToFirstChunkDequeueUsTotal,
    'headers_to_first_chunk_dequeue_ge_1ms_total':
        headersToFirstChunkDequeueGe1msTotal,
    'headers_to_first_chunk_dequeue_ge_5ms_total':
        headersToFirstChunkDequeueGe5msTotal,
    'headers_to_first_chunk_dequeue_ge_10ms_total':
        headersToFirstChunkDequeueGe10msTotal,
    'first_chunk_send_call_samples_total': firstChunkSendCallSamplesTotal,
    'first_chunk_send_call_us_total': firstChunkSendCallUsTotal,
    'first_chunk_send_call_ge_1ms_total': firstChunkSendCallGe1msTotal,
    'first_chunk_send_call_ge_5ms_total': firstChunkSendCallGe5msTotal,
    'first_chunk_send_call_ge_10ms_total': firstChunkSendCallGe10msTotal,
    'headers_to_first_chunk_send_call_samples_total':
        headersToFirstChunkSendCallSamplesTotal,
    'headers_to_first_chunk_send_call_us_total':
        headersToFirstChunkSendCallUsTotal,
    'tail_chunk_channel_wait_samples_total': tailChunkChannelWaitSamplesTotal,
    'tail_chunk_channel_wait_us_total': tailChunkChannelWaitUsTotal,
    'tail_chunk_channel_wait_ge_1ms_total': tailChunkChannelWaitGe1msTotal,
    'tail_chunk_channel_wait_ge_5ms_total': tailChunkChannelWaitGe5msTotal,
    'tail_chunk_channel_wait_ge_10ms_total': tailChunkChannelWaitGe10msTotal,
    'tail_chunk_send_call_samples_total': tailChunkSendCallSamplesTotal,
    'tail_chunk_send_call_us_total': tailChunkSendCallUsTotal,
    'tail_chunk_send_call_ge_1ms_total': tailChunkSendCallGe1msTotal,
    'tail_chunk_send_call_ge_5ms_total': tailChunkSendCallGe5msTotal,
    'tail_chunk_send_call_ge_10ms_total': tailChunkSendCallGe10msTotal,
    'first_to_last_chunk_send_samples_total': firstToLastChunkSendSamplesTotal,
    'first_to_last_chunk_send_us_total': firstToLastChunkSendUsTotal,
    'first_to_last_chunk_send_ge_1ms_total': firstToLastChunkSendGe1msTotal,
    'first_to_last_chunk_send_ge_5ms_total': firstToLastChunkSendGe5msTotal,
    'first_to_last_chunk_send_ge_10ms_total': firstToLastChunkSendGe10msTotal,
  };
}

/// Native HTTP request-body reader telemetry.
@immutable
class RouterHttpRequestBodyStreamMetrics {
  const RouterHttpRequestBodyStreamMetrics({
    required this.streamingRequestsTotal,
    required this.dataChunkSamplesTotal,
    required this.dataChunkWaitUsTotal,
    required this.firstChunkWaitSamplesTotal,
    required this.firstChunkWaitUsTotal,
    required this.secondChunkWaitSamplesTotal,
    required this.secondChunkWaitUsTotal,
    required this.remainingTailReadSamplesTotal,
    required this.remainingTailReadUsTotal,
    required this.remainingTailDataWaitSamplesTotal,
    required this.remainingTailDataWaitUsTotal,
    required this.remainingTailDataWaitMaxUsTotal,
    required this.remainingTailDataWaitMaxEventIndexTotal,
    required this.remainingTailDataWaitMaxBytesBeforeTotal,
    required this.remainingTailDataWaitMaxBytesAfterTotal,
    required this.remainingTailDataWaitMaxEofTotal,
    required this.remainingTailDataWaitMaxAvailableCapacityBeforeTotal,
    required this.remainingTailDataWaitMaxUsedCapacityBeforeTotal,
    required this.remainingTailDataWaitMaxAvailableCapacityAfterDataTotal,
    required this.remainingTailDataWaitMaxUsedCapacityAfterDataTotal,
    required this.remainingTailDataWaitMaxAvailableCapacityAfterReleaseTotal,
    required this.remainingTailDataWaitMaxUsedCapacityAfterReleaseTotal,
    required this.totalReadSamplesTotal,
    required this.totalReadUsTotal,
  });

  final int streamingRequestsTotal;
  final int dataChunkSamplesTotal;
  final int dataChunkWaitUsTotal;
  final int firstChunkWaitSamplesTotal;
  final int firstChunkWaitUsTotal;
  final int secondChunkWaitSamplesTotal;
  final int secondChunkWaitUsTotal;
  final int remainingTailReadSamplesTotal;
  final int remainingTailReadUsTotal;
  final int remainingTailDataWaitSamplesTotal;
  final int remainingTailDataWaitUsTotal;
  final int remainingTailDataWaitMaxUsTotal;
  final int remainingTailDataWaitMaxEventIndexTotal;
  final int remainingTailDataWaitMaxBytesBeforeTotal;
  final int remainingTailDataWaitMaxBytesAfterTotal;
  final int remainingTailDataWaitMaxEofTotal;
  final int remainingTailDataWaitMaxAvailableCapacityBeforeTotal;
  final int remainingTailDataWaitMaxUsedCapacityBeforeTotal;
  final int remainingTailDataWaitMaxAvailableCapacityAfterDataTotal;
  final int remainingTailDataWaitMaxUsedCapacityAfterDataTotal;
  final int remainingTailDataWaitMaxAvailableCapacityAfterReleaseTotal;
  final int remainingTailDataWaitMaxUsedCapacityAfterReleaseTotal;
  final int totalReadSamplesTotal;
  final int totalReadUsTotal;

  Map<String, Object?> toJson() => {
    'streaming_requests_total': streamingRequestsTotal,
    'data_chunk_samples_total': dataChunkSamplesTotal,
    'data_chunk_wait_us_total': dataChunkWaitUsTotal,
    'first_chunk_wait_samples_total': firstChunkWaitSamplesTotal,
    'first_chunk_wait_us_total': firstChunkWaitUsTotal,
    'second_chunk_wait_samples_total': secondChunkWaitSamplesTotal,
    'second_chunk_wait_us_total': secondChunkWaitUsTotal,
    'remaining_tail_read_samples_total': remainingTailReadSamplesTotal,
    'remaining_tail_read_us_total': remainingTailReadUsTotal,
    'remaining_tail_data_wait_samples_total': remainingTailDataWaitSamplesTotal,
    'remaining_tail_data_wait_us_total': remainingTailDataWaitUsTotal,
    'remaining_tail_data_wait_max_us_total': remainingTailDataWaitMaxUsTotal,
    'remaining_tail_data_wait_max_event_index_total':
        remainingTailDataWaitMaxEventIndexTotal,
    'remaining_tail_data_wait_max_bytes_before_total':
        remainingTailDataWaitMaxBytesBeforeTotal,
    'remaining_tail_data_wait_max_bytes_after_total':
        remainingTailDataWaitMaxBytesAfterTotal,
    'remaining_tail_data_wait_max_eof_total': remainingTailDataWaitMaxEofTotal,
    'remaining_tail_data_wait_max_available_capacity_before_total':
        remainingTailDataWaitMaxAvailableCapacityBeforeTotal,
    'remaining_tail_data_wait_max_used_capacity_before_total':
        remainingTailDataWaitMaxUsedCapacityBeforeTotal,
    'remaining_tail_data_wait_max_available_capacity_after_data_total':
        remainingTailDataWaitMaxAvailableCapacityAfterDataTotal,
    'remaining_tail_data_wait_max_used_capacity_after_data_total':
        remainingTailDataWaitMaxUsedCapacityAfterDataTotal,
    'remaining_tail_data_wait_max_available_capacity_after_release_total':
        remainingTailDataWaitMaxAvailableCapacityAfterReleaseTotal,
    'remaining_tail_data_wait_max_used_capacity_after_release_total':
        remainingTailDataWaitMaxUsedCapacityAfterReleaseTotal,
    'total_read_samples_total': totalReadSamplesTotal,
    'total_read_us_total': totalReadUsTotal,
  };
}

/// Aggregated telemetry emitted by the native transport.
@immutable
class RouterTransportMetrics {
  const RouterTransportMetrics({
    required this.totalEvents,
    required this.gracefulEvents,
    required this.goAwayEvents,
    required this.idleTimeoutEvents,
    required this.bodyTimeoutEvents,
    required this.protocolErrorEvents,
    required this.internalErrorEvents,
    required this.backpressureEvents,
    required this.maxBackpressureDepth,
    this.backpressureAlerts = 0,
    this.transportAlerts = 0,
    this.goAwayAlerts = 0,
    this.idleTimeoutAlerts = 0,
    this.bodyTimeoutAlerts = 0,
    this.protocolErrorAlerts = 0,
    this.internalErrorAlerts = 0,
    this.httpResponseStream,
    this.httpRequestBodyStream,
    this.alertBreakdown = const <RouterTransportAlertBreakdown>[],
    this.breakdown = const <RouterTransportMetricsBreakdown>[],
  });

  final int totalEvents;
  final int gracefulEvents;
  final int goAwayEvents;
  final int idleTimeoutEvents;
  final int bodyTimeoutEvents;
  final int protocolErrorEvents;
  final int internalErrorEvents;
  final int backpressureEvents;
  final int maxBackpressureDepth;
  final int backpressureAlerts;
  final int transportAlerts;
  final int goAwayAlerts;
  final int idleTimeoutAlerts;
  final int bodyTimeoutAlerts;
  final int protocolErrorAlerts;
  final int internalErrorAlerts;
  final RouterHttpResponseStreamMetrics? httpResponseStream;
  final RouterHttpRequestBodyStreamMetrics? httpRequestBodyStream;
  final List<RouterTransportAlertBreakdown> alertBreakdown;
  final List<RouterTransportMetricsBreakdown> breakdown;

  int get activeThrottleCount =>
      alertBreakdown.where((entry) => entry.throttleActive).length;

  List<RouterTransportAlertBreakdown> get activeThrottles => alertBreakdown
      .where((entry) => entry.throttleActive)
      .toList(growable: false);

  RouterTransportMetrics copyWith({
    int? totalEvents,
    int? gracefulEvents,
    int? goAwayEvents,
    int? idleTimeoutEvents,
    int? bodyTimeoutEvents,
    int? protocolErrorEvents,
    int? internalErrorEvents,
    int? backpressureEvents,
    int? maxBackpressureDepth,
    int? backpressureAlerts,
    int? transportAlerts,
    int? goAwayAlerts,
    int? idleTimeoutAlerts,
    int? bodyTimeoutAlerts,
    int? protocolErrorAlerts,
    int? internalErrorAlerts,
    RouterHttpResponseStreamMetrics? httpResponseStream,
    RouterHttpRequestBodyStreamMetrics? httpRequestBodyStream,
    List<RouterTransportAlertBreakdown>? alertBreakdown,
    List<RouterTransportMetricsBreakdown>? breakdown,
  }) {
    return RouterTransportMetrics(
      totalEvents: totalEvents ?? this.totalEvents,
      gracefulEvents: gracefulEvents ?? this.gracefulEvents,
      goAwayEvents: goAwayEvents ?? this.goAwayEvents,
      idleTimeoutEvents: idleTimeoutEvents ?? this.idleTimeoutEvents,
      bodyTimeoutEvents: bodyTimeoutEvents ?? this.bodyTimeoutEvents,
      protocolErrorEvents: protocolErrorEvents ?? this.protocolErrorEvents,
      internalErrorEvents: internalErrorEvents ?? this.internalErrorEvents,
      backpressureEvents: backpressureEvents ?? this.backpressureEvents,
      maxBackpressureDepth: maxBackpressureDepth ?? this.maxBackpressureDepth,
      backpressureAlerts: backpressureAlerts ?? this.backpressureAlerts,
      transportAlerts: transportAlerts ?? this.transportAlerts,
      goAwayAlerts: goAwayAlerts ?? this.goAwayAlerts,
      idleTimeoutAlerts: idleTimeoutAlerts ?? this.idleTimeoutAlerts,
      bodyTimeoutAlerts: bodyTimeoutAlerts ?? this.bodyTimeoutAlerts,
      protocolErrorAlerts: protocolErrorAlerts ?? this.protocolErrorAlerts,
      internalErrorAlerts: internalErrorAlerts ?? this.internalErrorAlerts,
      httpResponseStream: httpResponseStream ?? this.httpResponseStream,
      httpRequestBodyStream:
          httpRequestBodyStream ?? this.httpRequestBodyStream,
      alertBreakdown: alertBreakdown ?? this.alertBreakdown,
      breakdown: breakdown ?? this.breakdown,
    );
  }

  Map<String, Object?> toJson() => {
    'total_events': totalEvents,
    'graceful_events': gracefulEvents,
    'goaway_events': goAwayEvents,
    'idle_timeout_events': idleTimeoutEvents,
    'body_timeout_events': bodyTimeoutEvents,
    'protocol_error_events': protocolErrorEvents,
    'internal_error_events': internalErrorEvents,
    'backpressure_events': backpressureEvents,
    'max_backpressure_depth': maxBackpressureDepth,
    'backpressure_alerts': backpressureAlerts,
    'transport_alerts': transportAlerts,
    'goaway_alerts': goAwayAlerts,
    'idle_timeout_alerts': idleTimeoutAlerts,
    'body_timeout_alerts': bodyTimeoutAlerts,
    'protocol_error_alerts': protocolErrorAlerts,
    'internal_error_alerts': internalErrorAlerts,
    'active_throttles': activeThrottleCount,
    if (httpResponseStream != null)
      'http_response_stream': httpResponseStream!.toJson(),
    if (httpRequestBodyStream != null)
      'http_request_body_stream': httpRequestBodyStream!.toJson(),
    if (activeThrottles.isNotEmpty)
      'active_throttle_listeners': activeThrottles
          .map((entry) => entry.toJson())
          .toList(growable: false),
    if (alertBreakdown.isNotEmpty)
      'alert_breakdown': alertBreakdown
          .map((entry) => entry.toJson())
          .toList(growable: false),
    if (breakdown.isNotEmpty)
      'by_listener_protocol': breakdown.map((entry) => entry.toJson()).toList(),
  };
}

/// Per-listener/per-protocol aggregation of alert counts.
@immutable
class RouterTransportAlertBreakdown {
  const RouterTransportAlertBreakdown({
    required this.listenerId,
    required this.protocol,
    required this.endpoint,
    required this.backpressureAlerts,
    required this.goAwayAlerts,
    required this.idleTimeoutAlerts,
    required this.bodyTimeoutAlerts,
    required this.protocolErrorAlerts,
    required this.internalErrorAlerts,
    this.throttleActive = false,
    this.throttleRemainingMs,
    this.throttleUntil,
    this.lastAlertAt,
    this.lastAlertCategory,
    this.lastAlertReason,
    this.lastNewEvents,
    this.lastTotalEvents,
  });

  final int listenerId;
  final String protocol;
  final String endpoint;
  final int backpressureAlerts;
  final int goAwayAlerts;
  final int idleTimeoutAlerts;
  final int bodyTimeoutAlerts;
  final int protocolErrorAlerts;
  final int internalErrorAlerts;
  final bool throttleActive;
  final int? throttleRemainingMs;
  final DateTime? throttleUntil;
  final DateTime? lastAlertAt;
  final String? lastAlertCategory;
  final String? lastAlertReason;
  final int? lastNewEvents;
  final int? lastTotalEvents;

  int get transportAlerts =>
      goAwayAlerts +
      idleTimeoutAlerts +
      bodyTimeoutAlerts +
      protocolErrorAlerts +
      internalErrorAlerts;

  Map<String, Object?> toJson() => {
    'listener_id': listenerId,
    'protocol': protocol,
    'endpoint': endpoint,
    'backpressure_alerts': backpressureAlerts,
    'goaway_alerts': goAwayAlerts,
    'idle_timeout_alerts': idleTimeoutAlerts,
    'body_timeout_alerts': bodyTimeoutAlerts,
    'protocol_error_alerts': protocolErrorAlerts,
    'internal_error_alerts': internalErrorAlerts,
    'transport_alerts': transportAlerts,
    'throttle_active': throttleActive,
    if (throttleRemainingMs != null)
      'throttle_remaining_ms': throttleRemainingMs,
    if (throttleUntil != null)
      'throttle_until': throttleUntil!.toIso8601String(),
    if (lastAlertAt != null) 'last_alert_at': lastAlertAt!.toIso8601String(),
    if (lastAlertCategory != null) 'last_alert_category': lastAlertCategory,
    if (lastAlertReason != null) 'last_alert_reason': lastAlertReason,
    if (lastNewEvents != null) 'last_new_events': lastNewEvents,
    if (lastTotalEvents != null) 'last_total_events': lastTotalEvents,
  };
}

/// Per-listener/per-protocol breakdown of transport metrics.
@immutable
class RouterTransportMetricsBreakdown {
  const RouterTransportMetricsBreakdown({
    required this.listenerId,
    required this.protocol,
    required this.endpoint,
    required this.totalEvents,
    required this.gracefulEvents,
    required this.goAwayEvents,
    required this.idleTimeoutEvents,
    required this.bodyTimeoutEvents,
    required this.protocolErrorEvents,
    required this.internalErrorEvents,
    required this.backpressureEvents,
    required this.maxBackpressureDepth,
  });

  final int listenerId;
  final String protocol;
  final String endpoint;
  final int totalEvents;
  final int gracefulEvents;
  final int goAwayEvents;
  final int idleTimeoutEvents;
  final int bodyTimeoutEvents;
  final int protocolErrorEvents;
  final int internalErrorEvents;
  final int backpressureEvents;
  final int maxBackpressureDepth;

  Map<String, Object?> toJson() => {
    'listener_id': listenerId,
    'protocol': protocol,
    'endpoint': endpoint,
    'total_events': totalEvents,
    'graceful_events': gracefulEvents,
    'goaway_events': goAwayEvents,
    'idle_timeout_events': idleTimeoutEvents,
    'body_timeout_events': bodyTimeoutEvents,
    'protocol_error_events': protocolErrorEvents,
    'internal_error_events': internalErrorEvents,
    'backpressure_events': backpressureEvents,
    'max_backpressure_depth': maxBackpressureDepth,
  };
}

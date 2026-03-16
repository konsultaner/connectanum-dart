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
    this.shutdown = const RouterShutdownMetrics(),
    this.alerts = const RouterAlertMetrics(),
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

  /// Graceful shutdown/drain state owned by the binding.
  final RouterShutdownMetrics shutdown;

  /// Aggregated alert counters emitted by the boss loop (backpressure, etc.).
  final RouterAlertMetrics alerts;

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
    RouterShutdownMetrics? shutdown,
    RouterAlertMetrics? alerts,
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
      shutdown: shutdown ?? this.shutdown,
      alerts: alerts ?? this.alerts,
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
    'shutdown': shutdown.toJson(),
    'alerts': alerts.toJson(),
    if (transport != null) 'transport': transport!.toJson(),
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

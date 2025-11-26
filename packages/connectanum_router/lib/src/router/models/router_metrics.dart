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

  /// Aggregated transport-level metrics emitted by the native runtime.
  final RouterTransportMetrics? transport;

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
    if (transport != null) 'transport': transport!.toJson(),
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
  final List<RouterTransportMetricsBreakdown> breakdown;

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
    if (breakdown.isNotEmpty)
      'by_listener_protocol': breakdown.map((entry) => entry.toJson()).toList(),
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

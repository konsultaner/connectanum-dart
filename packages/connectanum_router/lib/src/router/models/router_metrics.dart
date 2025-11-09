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
  };
}

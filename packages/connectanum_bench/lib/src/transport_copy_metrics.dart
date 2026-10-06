import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_router/connectanum_router.dart';

/// Adds router-process transport counters to one WAMP client's copy metrics.
///
/// A numeric transport total is emitted only when the client already reports
/// complete coverage and the router has every counter needed for the active
/// cleartext transport. Known counters remain available as a lower bound when
/// some path is unmeasured.
Map<String, Object?> mergeRouterTransportCopyMetrics(
  Map<String, Object?> clientMetrics, {
  required WampScenario scenario,
  required NativeRouterTransportCopyMetrics? before,
  required NativeRouterTransportCopyMetrics? after,
}) {
  final metrics = Map<String, Object?>.from(clientMetrics);
  Map<String, Object?> notMeasured(String reason) => {
    'status': 'not_measured',
    'reason': reason,
  };

  final needsWebSocket = scenario.transport == WampTransport.websocket;
  final needsTls = scenario.secureTransport;
  final routerDelta = before != null && after != null
      ? after.deltaFrom(before)
      : null;
  final routerWebSocketMeasured =
      !needsWebSocket || routerDelta?.websocketCoalesceCopyBytesTotal != null;
  final clientTransport = _copyByteCount(metrics['transport_copy_bytes']);
  final coverageValue = metrics['coverage'];
  final clientCoverage = coverageValue is Map
      ? Map<String, Object?>.from(coverageValue)
      : <String, Object?>{};
  final clientBoundaryValue = clientCoverage['unknown_boundaries'];
  final clientUnknownBoundaries = clientBoundaryValue is List
      ? clientBoundaryValue.whereType<String>().toList()
      : <String>[];
  final clientCoverageComplete =
      clientCoverage['transport_copy_bytes'] ==
          'complete_client_connectanum_path' &&
      clientBoundaryValue is List &&
      clientBoundaryValue.every((value) => value is String);
  final completePath =
      clientCoverageComplete &&
      clientUnknownBoundaries.isEmpty &&
      clientTransport != null &&
      routerDelta != null &&
      routerWebSocketMeasured &&
      !needsTls;

  final unknownBoundaries = clientUnknownBoundaries;
  void addUnknownBoundary(String value) {
    if (!unknownBoundaries.contains(value)) unknownBoundaries.add(value);
  }

  if (!clientCoverageComplete) {
    addUnknownBoundary('client transport copy coverage is incomplete');
  }
  if (clientTransport == null) {
    addUnknownBoundary(
      'client transport copy counter is invalid or unavailable',
    );
  }
  if (routerDelta == null) {
    addUnknownBoundary('router transport copy snapshots are unavailable');
  } else if (!routerWebSocketMeasured) {
    addUnknownBoundary(
      'router WebSocket coalescing copy counter is unavailable',
    );
  }
  if (needsTls) {
    addUnknownBoundary('TLS memory-copy behavior is not measured');
  }

  final clientKnownOwnBytes = _copyByteCount(
    metrics['known_own_transport_copy_bytes'],
  );
  final routerKnownOwnBytes = routerDelta == null
      ? 0
      : routerDelta.dartToNativeCopiedBytesTotal +
            (needsWebSocket
                ? (routerDelta.websocketCoalesceCopyBytesTotal ?? 0)
                : 0);
  metrics['known_own_transport_copy_bytes'] =
      (clientKnownOwnBytes ?? 0) + routerKnownOwnBytes;

  final breakdownValue = metrics['known_own_copy_breakdown'];
  final breakdown = breakdownValue is Map
      ? Map<String, Object?>.from(breakdownValue)
      : <String, Object?>{};
  final clientBreakdownValue = breakdown['client'];
  final clientBreakdown = clientBreakdownValue is Map
      ? Map<String, Object?>.from(clientBreakdownValue)
      : <String, Object?>{};
  final routerBreakdown = <String, Object?>{};
  routerBreakdown['dart_to_native_copy_bytes'] = routerDelta == null
      ? notMeasured('router transport copy snapshots are unavailable')
      : routerDelta.dartToNativeCopiedBytesTotal;
  routerBreakdown['websocket_coalesce_copy_bytes'] = !needsWebSocket
      ? 0
      : routerDelta?.websocketCoalesceCopyBytesTotal ??
            notMeasured(
              'router WebSocket coalescing copy counter is unavailable',
            );
  breakdown
    ..['client'] = clientBreakdown
    ..['router'] = routerBreakdown;
  metrics['known_own_copy_breakdown'] = breakdown;

  metrics['transport_copy_bytes'] = completePath
      ? clientTransport +
            routerDelta.dartToNativeCopiedBytesTotal +
            (needsWebSocket ? routerDelta.websocketCoalesceCopyBytesTotal! : 0)
      : notMeasured(
          needsTls
              ? 'TLS copy behavior is not instrumented'
              : !clientCoverageComplete || clientTransport == null
              ? 'client transport copy coverage is incomplete'
              : routerDelta == null
              ? 'router transport copy snapshots are unavailable'
              : 'an active router transport copy counter is unavailable',
        );

  clientCoverage['transport_copy_bytes'] = completePath
      ? 'complete_connectanum_owned_path'
      : 'partial';
  clientCoverage['unknown_boundaries'] = unknownBoundaries;
  metrics['coverage'] = clientCoverage;

  if (needsTls) {
    metrics['tls_copy_bytes'] = notMeasured(
      'TLS accepted-plaintext bytes do not measure memory copies',
    );
    final clientTls = _copyByteCount(metrics['tls_plaintext_accepted_bytes']);
    final routerTls = routerDelta?.tlsPlaintextAcceptedBytesTotal;
    metrics['tls_plaintext_accepted_bytes'] =
        clientTls != null && routerTls != null
        ? clientTls + routerTls
        : notMeasured(
            'TLS plaintext acceptance is missing on a client or router side',
          );
  }
  return metrics;
}

// A fractional, non-finite or imprecise JSON number cannot measure byte counts.
int? _copyByteCount(Object? value) {
  if (value is int) return value >= 0 ? value : null;
  if (value is double &&
      value.isFinite &&
      value >= 0 &&
      value <= 9007199254740991 &&
      value == value.truncateToDouble()) {
    return value.toInt();
  }
  return null;
}

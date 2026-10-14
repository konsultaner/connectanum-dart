import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_router/connectanum_router.dart';

/// Versioned boundary contract approved for the standard Dart SDK campaign.
const connectanumCopyMeasurementScope = 'connectanum_buffer_boundaries_v1';

const _nativeClientCopyFields = [
  'dart_to_native_copy_bytes',
  'ffi_borrowed_send_input_copy_bytes',
  'io_buffer_front_copy_bytes',
  'io_buffered_read_copy_bytes',
];
const _dartClientCopyFields = [
  'rawsocket_frame_payload_copy_bytes',
  'rawsocket_frame_header_copy_bytes',
  'rawsocket_input_copy_bytes',
  'rawsocket_fragment_coalesce_copy_bytes',
  'rawsocket_pre_handshake_queue_copy_bytes',
  'websocket_fragment_coalesce_copy_bytes',
];

Map<String, Object?> dependencyCopyMetric(String dependency, String reason) => {
  'status': 'not_measured',
  'scope': 'dependency_internals',
  'dependency': dependency,
  'reason': reason,
};

/// Certifies only the documented Connectanum client buffer-copy boundaries.
/// Unknown dependencies remain separate from missing owned counters.
Map<String, Object?> clientTransportCopyMetricsFor(
  WampScenario scenario,
  Map<String, Object?> counters,
) {
  final native =
      scenario.clientImplementation == WampClientImplementation.native;
  final websocket = scenario.transport == WampTransport.websocket;
  final requiredFields = native
      ? [
          ..._nativeClientCopyFields,
          if (websocket) 'websocket_mask_copy_bytes',
          if (websocket) 'websocket_coalesce_copy_bytes',
        ]
      : _dartClientCopyFields;
  final missing = <String>[];
  var measuredBytes = 0;
  for (final field in requiredFields) {
    final value = _copyByteCount(counters[field]);
    if (value == null) {
      missing.add('client $field is invalid or unavailable');
    } else {
      measuredBytes += value;
    }
  }
  Map<String, Object?> notApplicable(String reason) => {
    'status': 'not_applicable',
    'reason': reason,
  };
  return {
    'measurement_scope': connectanumCopyMeasurementScope,
    'transport_copy_bytes': missing.isEmpty
        ? measuredBytes
        : {'status': 'not_measured', 'reason': missing.join('; ')},
    'known_own_transport_copy_bytes': measuredBytes,
    'known_own_copy_breakdown': {'client': Map<String, Object?>.from(counters)},
    'coverage': {
      'transport_copy_bytes': missing.isEmpty
          ? 'complete_client_connectanum_path'
          : 'partial',
      'unknown_boundaries': missing,
      'unmeasured_dependency_boundaries': [
        if (!native) 'dart_sdk_socket_io',
        if (!native && websocket) 'dart_sdk_websocket_masking',
        if (scenario.secureTransport)
          native ? 'rustls_tokio_rustls' : 'dart_sdk_tls',
      ],
    },
    'websocket_mask_copy_bytes': !websocket
        ? notApplicable('RawSocket does not mask WebSocket frames')
        : native
        ? _copyByteCount(counters['websocket_mask_copy_bytes']) ??
              {
                'status': 'not_measured',
                'reason': 'native mask counter missing',
              }
        : dependencyCopyMetric(
            'dart_sdk_websocket_masking',
            'Dart SDK WebSocket masking is outside Connectanum instrumentation',
          ),
    'tls_copy_bytes': !scenario.secureTransport
        ? notApplicable('workload uses cleartext transport')
        : dependencyCopyMetric(
            native ? 'rustls_tokio_rustls' : 'dart_sdk_tls',
            'TLS dependency internals are not a total Connectanum buffer-copy metric',
          ),
  };
}

/// Payload copies after a frozen native FlatBuffers owner is submitted.
/// The worker invokes this only for its native-owned typed payload workloads.
Object ownedFlatBuffersPayloadCopyBytes(List<WampSample> samples) {
  if (samples.isNotEmpty &&
      samples.every((sample) {
        final length = sample.nativePptPayloadBytes;
        return sample.nativePptFrameSubmissions == 1 &&
            length != null &&
            length >= 0 &&
            sample.nativePptPayloadReusedBytes == length;
      })) {
    return 0;
  }
  return <String, Object?>{
    'status': 'not_measured',
    'reason':
        'every owner must have one measured native PPT frame submission '
        'retaining its complete encoded payload',
  };
}

/// Adds router-process transport counters to one WAMP client's copy metrics.
///
/// A numeric transport total is emitted only when the client already reports
/// complete coverage and the router has every counter needed for the active
/// transport. Known counters remain available as a lower bound when
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
  final breakdownValue = metrics['known_own_copy_breakdown'];
  final breakdown = breakdownValue is Map
      ? Map<String, Object?>.from(breakdownValue)
      : <String, Object?>{};
  final clientBreakdownValue = breakdown['client'];
  final clientBreakdown = clientBreakdownValue is Map
      ? Map<String, Object?>.from(clientBreakdownValue)
      : <String, Object?>{};
  final measuredClient = clientTransportCopyMetricsFor(
    scenario,
    clientBreakdown,
  );
  final clientCoverageComplete =
      metrics['measurement_scope'] == connectanumCopyMeasurementScope &&
      clientCoverage['transport_copy_bytes'] ==
          'complete_client_connectanum_path' &&
      clientBoundaryValue is List &&
      clientBoundaryValue.every((value) => value is String) &&
      _copyByteCount(measuredClient['transport_copy_bytes']) != null &&
      measuredClient['transport_copy_bytes'] == clientTransport;
  final clientInputMeasured =
      scenario.clientImplementation != WampClientImplementation.native ||
      (_copyByteCount(clientBreakdown['io_buffer_front_copy_bytes']) != null &&
          _copyByteCount(clientBreakdown['io_buffered_read_copy_bytes']) !=
              null);
  final routerFrontCopies = _copyByteCount(
    routerDelta?.ioBufferFrontCopyBytesTotal,
  );
  final routerReplayCopies = _copyByteCount(
    routerDelta?.ioBufferedReadCopyBytesTotal,
  );
  final routerFfiCopies = _copyByteCount(
    routerDelta?.ffiBorrowedSendCopyBytesTotal,
  );
  final routerInputMeasured =
      routerFrontCopies != null && routerReplayCopies != null;
  final completePath =
      clientCoverageComplete &&
      clientInputMeasured &&
      clientUnknownBoundaries.isEmpty &&
      clientTransport != null &&
      routerDelta != null &&
      routerWebSocketMeasured &&
      routerInputMeasured &&
      routerFfiCopies != null;

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
  if (!clientInputMeasured) {
    addUnknownBoundary('client prefetched input copy counters are unavailable');
  }
  if (routerDelta == null) {
    addUnknownBoundary('router transport copy snapshots are unavailable');
  } else if (!routerWebSocketMeasured) {
    addUnknownBoundary(
      'router WebSocket coalescing copy counter is unavailable',
    );
  }
  if (routerDelta != null && !routerInputMeasured) {
    addUnknownBoundary('router prefetched input copy counters are unavailable');
  }
  if (routerDelta != null && routerFfiCopies == null) {
    addUnknownBoundary('router borrowed FFI send copy counter is unavailable');
  }

  final clientKnownOwnBytes = _copyByteCount(
    metrics['known_own_transport_copy_bytes'],
  );
  final routerKnownOwnBytes = routerDelta == null
      ? 0
      : routerDelta.dartToNativeCopiedBytesTotal +
            (needsWebSocket
                ? (routerDelta.websocketCoalesceCopyBytesTotal ?? 0)
                : 0) +
            (routerFrontCopies ?? 0) +
            (routerReplayCopies ?? 0) +
            (routerFfiCopies ?? 0);
  metrics['known_own_transport_copy_bytes'] =
      (clientKnownOwnBytes ?? 0) + routerKnownOwnBytes;

  final routerBreakdown = <String, Object?>{};
  routerBreakdown['io_buffer_front_copy_bytes'] =
      routerFrontCopies ??
      notMeasured(
        'router prefetched input staging copy counter is unavailable',
      );
  routerBreakdown['io_buffered_read_copy_bytes'] =
      routerReplayCopies ??
      notMeasured('router prefetched input replay copy counter is unavailable');
  // Named source counters remain partial and never certify total TLS copies.
  routerBreakdown['rustls_outbound_chunk_copy_bytes'] =
      _copyByteCount(routerDelta?.rustlsOutboundChunkCopyBytesTotal) ??
      notMeasured('router partial Rustls source counter is unavailable');
  routerBreakdown['rustls_queue_read_copy_bytes'] =
      _copyByteCount(routerDelta?.rustlsQueueReadCopyBytesTotal) ??
      notMeasured('router partial Rustls source counter is unavailable');
  routerBreakdown['rustls_deframer_append_copy_bytes'] =
      _copyByteCount(routerDelta?.rustlsDeframerAppendCopyBytesTotal) ??
      notMeasured('router partial Rustls source counter is unavailable');
  routerBreakdown['rustls_deframer_move_copy_bytes'] =
      _copyByteCount(routerDelta?.rustlsDeframerMoveCopyBytesTotal) ??
      notMeasured('router partial Rustls source counter is unavailable');
  routerBreakdown['rustls_record_buffer_copy_bytes'] =
      _copyByteCount(routerDelta?.rustlsRecordBufferCopyBytesTotal) ??
      notMeasured('router partial Rustls source counter is unavailable');
  routerBreakdown['rustls_record_append_copy_bytes'] =
      _copyByteCount(routerDelta?.rustlsRecordAppendCopyBytesTotal) ??
      notMeasured('router partial Rustls source counter is unavailable');
  routerBreakdown['tokio_rustls_plaintext_extract_copy_bytes'] =
      _copyByteCount(routerDelta?.tokioRustlsPlaintextExtractCopyBytesTotal) ??
      notMeasured('router partial Tokio-Rustls source counter is unavailable');
  routerBreakdown['dart_to_native_copy_bytes'] = routerDelta == null
      ? notMeasured('router transport copy snapshots are unavailable')
      : routerDelta.dartToNativeCopiedBytesTotal;
  routerBreakdown['ffi_borrowed_send_input_copy_bytes'] =
      routerFfiCopies ??
      notMeasured('router borrowed FFI send copy counter is unavailable');
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
            (needsWebSocket
                ? routerDelta.websocketCoalesceCopyBytesTotal!
                : 0) +
            routerFrontCopies +
            routerReplayCopies +
            routerFfiCopies
      : notMeasured(
          !clientCoverageComplete || clientTransport == null
              ? 'client transport copy coverage is incomplete'
              : !clientInputMeasured
              ? 'client prefetched input copy counters are unavailable'
              : routerDelta == null
              ? 'router transport copy snapshots are unavailable'
              : !routerInputMeasured
              ? 'router prefetched input copy counters are unavailable'
              : 'an active router transport copy counter is unavailable',
        );

  clientCoverage['transport_copy_bytes'] = completePath
      ? 'complete_connectanum_owned_path'
      : 'partial';
  clientCoverage['unknown_boundaries'] = unknownBoundaries;
  final dependencies = clientCoverage['unmeasured_dependency_boundaries'];
  clientCoverage['unmeasured_dependency_boundaries'] = [
    if (dependencies is List) ...dependencies,
    if (needsTls &&
        (dependencies is! List ||
            !dependencies.contains('rustls_tokio_rustls')))
      'rustls_tokio_rustls',
  ];
  metrics['coverage'] = clientCoverage;

  if (needsTls) {
    metrics['tls_copy_bytes'] = dependencyCopyMetric(
      scenario.clientImplementation == WampClientImplementation.native
          ? 'rustls_tokio_rustls'
          : 'dart_sdk_tls_and_rustls_tokio_rustls',
      'TLS dependency internals are not measured by plaintext acceptance',
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

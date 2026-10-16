import 'dart:convert';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_bench/src/transport_copy_metrics.dart';
import 'package:connectanum_bench/src/codec_copy_metrics.dart';
import 'package:connectanum_bench/src/owned_copy_metrics.dart';
import 'package:connectanum_bench/src/raw_frame_copy_metrics.dart';
import 'package:connectanum_bench/src/native_crypto_copy_metrics.dart';

WampScenario ownedCopyScenario({
  bool native = true,
  bool secure = false,
  bool ws = false,
  bool encrypted = true,
  bool mixed = true,
  bool fileTransfer = false,
}) => WampScenario(
  transport: ws ? WampTransport.websocket : WampTransport.rawsocket,
  secureTransport: secure,
  serializer: WampSerializer.flatbuffers,
  clientImplementation: native
      ? WampClientImplementation.native
      : WampClientImplementation.dart,
  peerSerializer: mixed ? WampSerializer.cbor : null,
  pptScheme: encrypted ? 'wamp' : 'x_connectanum_bench_typed',
  mode: fileTransfer ? WampMode.fileTransfer : WampMode.rpc,
  uri: 'bench.rpc.echo',
  iterations: 1,
  concurrency: 1,
  payloadBytes: 1024,
);
Map<String, Object?> dartCopyComponent(int clones) => {
  'status': 'measured',
  for (final field in ownedCopyObservationFields) field: 0,
  'clone_copy_bytes': clones,
  'ppt_serializer_copy_bytes': 7,
  'known_copy_bytes': clones + 7,
};
Map<String, Object?> codecCopyComponent(int vector) => {
  'status': 'measured',
  'coverage_version': 1,
  for (final field in codecCopyMetricFields) field: 0,
  'vector_copy_bytes': vector,
  'known_copy_bytes': vector,
};
Map<String, Object?> rawCopyComponent(int coalescing) => {
  'status': 'measured',
  for (final field in rawFrameCopyMetricFields) field: 0,
  'coalescing_copy_bytes': coalescing,
  'single_segment_contiguous_requests': 999,
  'known_copy_bytes': coalescing,
};
Map<String, Object?> _rawFixture(WampScenario scenario) {
  final native =
      scenario.clientImplementation == WampClientImplementation.native;
  final ws = scenario.transport == WampTransport.websocket;
  final active = native && scenario.pptScheme == 'wamp';
  final clientFields = native
      ? [
          'dart_to_native_copy_bytes',
          'ffi_borrowed_send_input_copy_bytes',
          'io_buffer_front_copy_bytes',
          'io_buffered_read_copy_bytes',
          if (ws) ...[
            'websocket_mask_copy_bytes',
            'websocket_coalesce_copy_bytes',
          ],
        ]
      : [
          'rawsocket_frame_payload_copy_bytes',
          'rawsocket_frame_header_copy_bytes',
          'rawsocket_input_copy_bytes',
          'rawsocket_fragment_coalesce_copy_bytes',
          'rawsocket_pre_handshake_queue_copy_bytes',
          'websocket_fragment_coalesce_copy_bytes',
        ];
  final routerFields = [
    'dart_to_native_copy_bytes',
    'ffi_borrowed_send_input_copy_bytes',
    'io_buffer_front_copy_bytes',
    'io_buffered_read_copy_bytes',
    if (ws) 'websocket_coalesce_copy_bytes',
  ];
  return {
    'measurement_scope': connectanumCopyMeasurementScope,
    'transport_copy_bytes': clientFields.length + routerFields.length,
    'coverage': {
      'transport_copy_bytes': 'complete_connectanum_owned_path',
      'unknown_boundaries': <String>[],
      'unmeasured_dependency_boundaries': [
        if (!native) 'dart_sdk_socket_io',
        if (!native && ws) 'dart_sdk_websocket_masking',
        if (scenario.secureTransport) 'rustls_tokio_rustls',
        if (scenario.secureTransport && !native) 'dart_sdk_tls',
      ],
    },
    'websocket_mask_copy_bytes': !ws
        ? {'status': 'not_applicable', 'reason': 'RawSocket fixture'}
        : native
        ? 1
        : dependencyCopyMetric(
            'dart_sdk_websocket_masking',
            'Synthetic SDK masking boundary',
          ),
    'tls_copy_bytes': !scenario.secureTransport
        ? {'status': 'not_applicable', 'reason': 'Cleartext fixture'}
        : dependencyCopyMetric(
            native
                ? 'rustls_tokio_rustls'
                : 'dart_sdk_tls_and_rustls_tokio_rustls',
            'Synthetic TLS dependency boundary',
          ),
    'known_own_copy_breakdown': {
      'client': {for (final field in clientFields) field: 1},
      'router': {for (final field in routerFields) field: 1},
    },
    'dart_owned_buffer_copy_breakdown': {
      'client': dartCopyComponent(11),
      'router': {
        'status': 'measured',
        'boss_generation': 3,
        'main_isolate': dartCopyComponent(13),
        'workers': {'9': dartCopyComponent(17), '2': dartCopyComponent(19)},
        'known_copy_bytes': 70,
      },
    },
    'native_codec_copy_breakdown': {
      'client': codecCopyComponent(native ? 23 : 0),
      'router': codecCopyComponent(29),
    },
    'raw_frame_copy_breakdown': {
      'client': rawCopyComponent(native ? 31 : 0),
      'router': rawCopyComponent(37),
    },
    'native_crypto_copy_breakdown': {
      'status': 'measured',
      'active': active,
      for (final field in nativeCryptoCopyFields)
        field: active
            ? 1
            : nativeCryptoCopyFields.indexOf(field) < 3
            ? 0
            : null,
      'known_copy_bytes': active ? 7 : 0,
    },
    'e2ee_copy_bytes': {
      'status': scenario.pptScheme == 'wamp'
          ? 'not_measured'
          : 'not_applicable',
    },
    'e2ee_copy_breakdown': {
      'coverage': 'known_staging_only',
      'diagnostic_copy_bytes': 900000000,
    },
    'transcode_copy_bytes': {
      'status': scenario.peerSerializer == null
          ? 'not_applicable'
          : 'not_measured',
    },
    'builder_input_copy_bytes': 7,
  };
}

Map<String, Object?> ownedCopyFixture(WampScenario scenario) =>
    Map<String, Object?>.from(
      jsonDecode(jsonEncode(_rawFixture(scenario))) as Map,
    );

Map copyMetricMapAt(Map root, List<String> path) {
  Map value = root;
  for (final key in path) {
    value = value[key] as Map;
  }
  return value;
}

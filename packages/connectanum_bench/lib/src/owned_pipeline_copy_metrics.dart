import 'encoded_wamp_volume.dart';
// Benchmark-only observations of the core's byte-buffer boundaries.
// ignore: implementation_imports
import 'package:connectanum_core/src/serializer/owned_copy_metrics.dart';
import 'codec_copy_metrics.dart';
import 'raw_frame_copy_metrics.dart';
import 'transport_copy_metrics.dart';
import 'wamp_workload_runner.dart';
import 'native_crypto_copy_metrics.dart';

Map<String, Object?>? _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) return null;
  return Map<String, Object?>.from(value);
}

int _count(Object? value, String label) {
  if (value is! int || value < 0) {
    throw StateError('$label is not a byte count');
  }
  return value;
}

int _component(
  Object? value,
  List<String> fields,
  String label, {
  List<String> nonByteFields = const [],
  List<String> zeroFields = const [],
}) {
  final map = _map(value);
  if (map == null || map['status'] != 'measured') {
    throw StateError('$label was not measured');
  }
  var sum = 0;
  for (final field in fields) {
    sum += _count(map[field], '$label.$field');
  }
  for (final field in nonByteFields) {
    _count(map[field], '$label.$field');
  }
  for (final field in zeroFields) {
    if (_count(map[field], '$label.$field') != 0) {
      throw StateError('$label has a failed or unmeasured operation');
    }
  }
  if (_count(map['known_copy_bytes'], '$label.known_copy_bytes') != sum) {
    throw StateError('$label subtotal disagrees with its fields');
  }
  return sum;
}

int _codecComponent(Object? value, String label) {
  final map = _map(value);
  final coverage = map?['coverage_version'];
  if (coverage is! int || coverage != 1) {
    throw StateError('$label copy coverage v1 is unavailable');
  }
  return _component(map, codecCopyMetricFields, label);
}

int _dartComponent(Object? value, String label) => _component(
  value,
  OwnedCopyMetrics.fields,
  label,
  zeroFields: const ['failed_copy_operations', 'unmeasured_copy_operations'],
);

int _routerDart(Object? value) {
  final router = _map(value);
  final workers = _map(router?['workers']);
  final generation = router?['boss_generation'];
  if (router?['status'] != 'measured' ||
      generation is! int ||
      generation < 1 ||
      workers == null ||
      workers.isEmpty ||
      workers.keys.any((id) => id.isEmpty)) {
    throw StateError('router Dart ownership observations are incomplete');
  }
  var sum = _dartComponent(router!['main_isolate'], 'router.main_isolate');
  for (final entry in workers.entries) {
    sum += _dartComponent(entry.value, 'router.worker.${entry.key}');
  }
  if (_count(router['known_copy_bytes'], 'router subtotal') != sum) {
    throw StateError('router subtotal disagrees with its isolates');
  }
  return sum;
}

int _raw(Object? value, String label) => _component(
  value,
  rawFrameCopyMetricFields.take(2).toList(),
  label,
  nonByteFields: rawFrameCopyMetricFields.skip(2).toList(),
);

int _crypto(Object? value, {required bool active}) {
  final map = _map(value);
  if (map == null || map['status'] != 'measured' || map['active'] != active) {
    throw StateError('native crypto provider observations are incomplete');
  }
  if (active) {
    return _component(map, nativeCryptoCopyFields, 'client.native_crypto');
  }
  for (final field in nativeCryptoCopyFields) {
    if ((nativeCryptoCopyFields.indexOf(field) < 3 || map[field] != null) &&
        _count(map[field], 'inactive native crypto.$field') != 0) {
      throw StateError('inactive native provider performed copies');
    }
  }
  if (_count(map['known_copy_bytes'], 'inactive native crypto subtotal') != 0) {
    throw StateError('inactive native provider has a nonzero subtotal');
  }
  return 0;
}

/// Sums disjoint owned byte-buffer boundaries. PPT, portable crypto and builder
/// diagnostics are subsets of the Dart-owned fields and are never added again.
/// A mixed window reports actual router work, without baseline subtraction.
Map<String, Object?> mergeOwnedPipelineCopyMetrics(
  Map<String, Object?> input, {
  required WampScenario scenario,
}) {
  final result = Map<String, Object?>.from(input);
  final encrypted = scenario.pptScheme == 'wamp';
  final mixed =
      scenario.peerSerializer != null &&
      scenario.peerSerializer != scenario.serializer;
  final native =
      scenario.clientImplementation == WampClientImplementation.native;
  final dependencyInput = _map(
    input['coverage'],
  )?['unmeasured_dependency_boundaries'];
  final dependencies = <String>{
    'dart_sdk_runtime_internals',
    'rust_std_tokio_bytes_internals',
    'serializer_dependency_internals',
    if (scenario.mode == WampMode.fileTransfer) 'file_io_dependency_internals',
    if (encrypted) 'crypto_dependency_internals',
    if (dependencyInput is List) ...dependencyInput.whereType<String>(),
  }.toList()..sort();
  final parts = <String, int>{};
  final errors = <String>[];
  void observe(String name, int Function() read) {
    try {
      parts[name] = read();
    } on StateError catch (error) {
      errors.add(error.message);
    }
  }

  final dart = _map(input['dart_owned_buffer_copy_breakdown']);
  final codec = _map(input['native_codec_copy_breakdown']);
  final raw = _map(input['raw_frame_copy_breakdown']);
  result['encoded_wamp_volume'] = mergeEncodedWampVolumes({
    'client_dart': _map(dart?['client'])?['encoded_wamp_volume'],
    'router_dart': _map(dart?['router'])?['encoded_wamp_volume'],
    'client_native': _map(codec?['client'])?['encoded_wamp_volume'],
    'router_native': _map(codec?['router'])?['encoded_wamp_volume'],
  });
  observe('client_dart', () => _dartComponent(dart?['client'], 'client.dart'));
  observe('router_dart', () => _routerDart(dart?['router']));
  observe(
    'router_native_codec',
    () => _codecComponent(codec?['router'], 'router.native_codec'),
  );
  observe(
    'router_native_raw_frame',
    () => _raw(raw?['router'], 'router.native_raw_frame'),
  );
  // Supporting native work (for example file hashing) can run with a Dart
  // transport. Observe those process counters independently of transport choice.
  observe(
    'client_native_codec',
    () => _codecComponent(codec?['client'], 'client.native_codec'),
  );
  observe(
    'client_native_raw_frame',
    () => _raw(raw?['client'], 'client.native_raw_frame'),
  );
  observe('native_crypto', () {
    if (encrypted && native) {
      final client = _map(dart?['client']);
      if (_count(
            client?['portable_crypto_copy_bytes'],
            'native-provider portable crypto',
          ) !=
          0) {
        throw StateError('portable crypto ran in a native-provider window');
      }
    }
    return _crypto(
      input['native_crypto_copy_breakdown'],
      active: encrypted && native,
    );
  });
  observe('transport', () {
    final coverage = _map(input['coverage']);
    if (input['measurement_scope'] != connectanumCopyMeasurementScope ||
        coverage?['transport_copy_bytes'] !=
            'complete_connectanum_owned_path' ||
        coverage?['unknown_boundaries'] is! List ||
        (coverage!['unknown_boundaries'] as List).isNotEmpty) {
      throw StateError('transport copy coverage is incomplete');
    }
    final boundaries = _map(input['known_own_copy_breakdown']);
    final nativeFields = [
      'dart_to_native_copy_bytes',
      'ffi_borrowed_send_input_copy_bytes',
      'io_buffer_front_copy_bytes',
      'io_buffered_read_copy_bytes',
    ];
    final clientFields = native
        ? [
            ...nativeFields,
            if (scenario.transport == WampTransport.websocket) ...[
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
      ...nativeFields,
      if (scenario.transport == WampTransport.websocket)
        'websocket_coalesce_copy_bytes',
    ];
    var sum = 0;
    for (final entry in {
      'client': clientFields,
      'router': routerFields,
    }.entries) {
      final counters = _map(boundaries?[entry.key]);
      for (final field in entry.value) {
        sum += _count(counters?[field], 'transport.${entry.key}.$field');
      }
    }
    if (_count(input['transport_copy_bytes'], 'transport total') != sum) {
      throw StateError('transport total disagrees with its fields');
    }
    final expected = {
      if (!native) 'dart_sdk_socket_io',
      if (!native && scenario.transport == WampTransport.websocket)
        'dart_sdk_websocket_masking',
      if (scenario.secureTransport) 'rustls_tokio_rustls',
      if (scenario.secureTransport && !native) 'dart_sdk_tls',
    };
    if (dependencyInput is! List ||
        dependencyInput.any((value) => value is! String) ||
        dependencyInput.toSet().length != dependencyInput.length ||
        dependencyInput.length != expected.length ||
        !dependencyInput.toSet().containsAll(expected)) {
      throw StateError(
        'transport dependency labels disagree with the active path',
      );
    }
    return sum;
  });
  Map<String, Object?> breakdown(
    Map<String, int> components,
    List<String> unknown,
  ) => {
    'coverage': unknown.isEmpty ? 'complete_connectanum_owned_path' : 'partial',
    'measurement_scope': connectanumCopyMeasurementScope,
    'components': components,
    'unknown_boundaries': unknown,
    'unmeasured_dependency_boundaries': dependencies,
  };
  Object total(List<String> unknown, Map<String, int> components) =>
      unknown.isEmpty
      ? components.values.fold<int>(0, (sum, value) => sum + value)
      : {'status': 'not_measured', 'reason': unknown.join('; ')};
  if (encrypted) {
    result['e2ee_copy_bytes'] = total(errors, parts);
    result['e2ee_copy_breakdown'] = {
      ...breakdown(parts, errors),
      'provider_staging_diagnostics': input['e2ee_copy_breakdown'],
      if (errors.isEmpty)
        'non_transport_owned_copy_bytes':
            (total(errors, parts) as int) - parts['transport']!,
    };
  }
  if (mixed) {
    final transcode = {
      for (final name in [
        'router_dart',
        'router_native_codec',
        'router_native_raw_frame',
      ])
        if (parts[name] != null) name: parts[name]!,
    };
    final unknown = [
      for (final name in [
        'router_dart',
        'router_native_codec',
        'router_native_raw_frame',
      ])
        if (!parts.containsKey(name)) '$name is not measured',
    ];
    result['transcode_copy_bytes'] = total(unknown, transcode);
    result['transcode_copy_breakdown'] = {
      ...breakdown(transcode, unknown),
      'boundary': 'router_serializer_and_dispatch_buffers',
    };
  }
  return result;
}

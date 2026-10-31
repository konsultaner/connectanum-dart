// Observe the core's declared byte-buffer operations at benchmark boundaries.
// ignore: implementation_imports
import 'package:connectanum_core/src/serializer/owned_copy_metrics.dart';

import 'encoded_wamp_volume.dart';

const ownedCopyObservationFields = [
  ...OwnedCopyMetrics.fields,
  'failed_copy_operations',
  'unmeasured_copy_operations',
];

/// Cumulative observations must cover every required field and a complete
/// window. Failure/unknown-operation counts are not copied byte counts.
Map<String, Object?> ownedBufferCopyMetricsDelta(
  Map<String, Object?>? before,
  Map<String, Object?>? after,
) {
  Map<String, Object?> unavailable(String reason) => {
    'status': 'not_measured',
    'reason': reason,
  };
  if (before == null || after == null) {
    return unavailable('owned buffer observation was not enabled');
  }
  final delta = <String, int>{};
  for (final field in ownedCopyObservationFields) {
    final start = before[field];
    final end = after[field];
    if (start is! int || end is! int || start < 0 || end < start) {
      return unavailable(
        'owned buffer counter $field is missing, invalid or rewound',
      );
    }
    delta[field] = end - start;
  }
  if (delta['failed_copy_operations'] != 0 ||
      delta['unmeasured_copy_operations'] != 0) {
    return {
      ...unavailable(
        'a buffer operation failed or used an unobserved allocator',
      ),
      'observed_deltas': delta,
    };
  }
  return {
    'status': 'measured',
    'encoded_wamp_volume': encodedWampVolumeDelta(before, after),
    ...delta,
    'known_copy_bytes': OwnedCopyMetrics.fields.fold<int>(
      0,
      (sum, field) => sum + delta[field]!,
    ),
  };
}

/// The boss and state store share the main isolate. Worker identities and the
/// boss generation must stay stable; a timeout cannot certify a complete window.
Map<String, Object?> routerOwnedBufferCopyMetricsDelta(
  Map<String, Object?>? before,
  Map<String, Object?>? after, {
  required bool quiescent,
}) {
  Map<String, Object?> unavailable(String reason) => {
    'status': 'not_measured',
    'reason': reason,
  };
  if (!quiescent) {
    return unavailable('router did not settle after the workload');
  }
  if (before?['status'] != 'measured' || after?['status'] != 'measured') {
    return unavailable('a router snapshot is unavailable');
  }
  final generation = before!['boss_generation'];
  if (generation is! int ||
      generation < 1 ||
      generation != after!['boss_generation']) {
    return unavailable('router boss generation changed or is invalid');
  }
  final earlier = _stringMap(before['workers']);
  final later = _stringMap(after['workers']);
  if (earlier == null ||
      later == null ||
      earlier.isEmpty ||
      earlier.length != later.length ||
      earlier.keys.any((key) => !later.containsKey(key))) {
    return unavailable('router worker generations changed or are missing');
  }
  final main = ownedBufferCopyMetricsDelta(
    _stringMap(before['main_isolate']),
    _stringMap(after['main_isolate']),
  );
  final workers = {
    for (final id in earlier.keys)
      id: ownedBufferCopyMetricsDelta(
        _stringMap(earlier[id]),
        _stringMap(later[id]),
      ),
  };
  final components = [main, ...workers.values];
  if (components.any((value) => value['status'] != 'measured')) {
    return {
      ...unavailable('a router isolate has incomplete copy observations'),
      'main_isolate': main,
      'workers': workers,
    };
  }
  return {
    'status': 'measured',
    'boss_generation': generation,
    'encoded_wamp_volume': mergeEncodedWampVolumes({
      'main_isolate': main['encoded_wamp_volume'],
      for (final entry in workers.entries)
        entry.key: entry.value['encoded_wamp_volume'],
    }),
    'main_isolate': main,
    'workers': workers,
    'known_copy_bytes': components.fold<int>(
      0,
      (sum, value) => sum + (value['known_copy_bytes'] as int),
    ),
  };
}

Map<String, Object?>? _stringMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) return null;
  return Map<String, Object?>.from(value);
}

import 'dart_heap_allocation_volume.dart';
import 'dart_vm_metrics.dart';

Map<String, Object?> metricsObject(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Metrics observer expected an object');
  }
  return Map<String, Object?>.from(value);
}

int? _optionalCount(Object? value) {
  if (value == null) return null;
  if (value is! int || value < 0 || value > 9007199254740991) {
    throw const FormatException('Invalid metrics observer counter');
  }
  return value;
}

int _count(Object? value) {
  final result = _optionalCount(value);
  if (result == null) throw const FormatException('Missing observer counter');
  return result;
}

List<String> _identities(Object? value) {
  if (value is! List || value.any((id) => id is! String || id.isEmpty)) {
    throw const FormatException('Invalid metrics observer isolate identities');
  }
  final ids = value.cast<String>();
  if (ids.toSet().length != ids.length) {
    throw const FormatException(
      'Duplicate metrics observer isolate identities',
    );
  }
  return ids;
}

Map<String, Object?> encodeMetricsWindow(DartVmMetricsWindow window) => {
  'cpu_user_ticks': window.cpuUserTicks,
  'cpu_system_ticks': window.cpuSystemTicks,
  'isolate_ids': window.isolateIds,
  'profiled_isolate_ids': window.profiledIsolateIds,
  'gc_snapshots': window.gcSnapshots?.map(
    (group, value) => MapEntry(group, {
      'young_collections': value.newCollections,
      'old_collections': value.oldCollections,
      'young_pause_us': value.newPauseMicros,
      'old_pause_us': value.oldPauseMicros,
      'heap_used_bytes': value.heapUsedBytes,
    }),
  ),
  'allocation_snapshot': switch (window.allocationSnapshot) {
    final snapshot? => {
      'before_us': snapshot.beforeMicros,
      'after_us': snapshot.afterMicros,
    },
    null => null,
  },
};

DartVmMetricsWindow decodeMetricsWindow(Object? value) {
  final map = metricsObject(value);
  final rawGc = map['gc_snapshots'];
  final gc = rawGc == null
      ? null
      : metricsObject(rawGc).map((group, value) {
          if (group.isEmpty) {
            throw const FormatException('Empty heap group identity');
          }
          final raw = metricsObject(value);
          return MapEntry(
            group,
            DartVmGcHeapSnapshot(
              newCollections: _count(raw['young_collections']),
              oldCollections: _count(raw['old_collections']),
              newPauseMicros: _count(raw['young_pause_us']),
              oldPauseMicros: _count(raw['old_pause_us']),
              heapUsedBytes: _optionalCount(raw['heap_used_bytes']),
            ),
          );
        });
  DartHeapUsageSnapshot? allocation;
  if (map['allocation_snapshot'] case final raw?) {
    final times = metricsObject(raw);
    if (gc == null || gc.values.any((entry) => entry.heapUsedBytes == null)) {
      throw const FormatException(
        'Allocation snapshot has no heap observations',
      );
    }
    allocation = DartHeapUsageSnapshot(
      beforeMicros: _count(times['before_us']),
      afterMicros: _count(times['after_us']),
      groups: gc.map(
        (group, entry) => MapEntry(group, (
          usedBytes: entry.heapUsedBytes!,
          youngCollections: entry.newCollections,
          oldCollections: entry.oldCollections,
        )),
      ),
    );
  }
  return DartVmMetricsWindow(
    cpuUserTicks: _optionalCount(map['cpu_user_ticks']),
    cpuSystemTicks: _optionalCount(map['cpu_system_ticks']),
    isolateIds: _identities(map['isolate_ids']),
    profiledIsolateIds: map['profiled_isolate_ids'] == null
        ? null
        : _identities(map['profiled_isolate_ids']),
    gcSnapshots: gc,
    allocationSnapshot: allocation,
  );
}

Map<String, Object?> encodeMetricsResult(DartVmMetricsResult result) => {
  'allocated_bytes': result.allocatedBytes,
  'allocation_measurement': result.allocationMeasurement,
  'gc_count': result.gcCount,
  'gc_pause_us': result.gcPauseMicros,
  'cpu_user_us': result.cpuUserMicros,
  'cpu_system_us': result.cpuSystemMicros,
  'current_rss_bytes': result.currentRssBytes,
  'peak_rss_bytes': result.peakRssBytes,
};

DartVmMetricsResult decodeMetricsResult(Object? value) {
  final map = metricsObject(value);
  return DartVmMetricsResult(
    allocatedBytes: _optionalCount(map['allocated_bytes']),
    allocationMeasurement: map['allocation_measurement'] == null
        ? null
        : metricsObject(map['allocation_measurement']),
    gcCount: _optionalCount(map['gc_count']),
    gcPauseMicros: _optionalCount(map['gc_pause_us']),
    cpuUserMicros: _optionalCount(map['cpu_user_us']),
    cpuSystemMicros: _optionalCount(map['cpu_system_us']),
    currentRssBytes: _optionalCount(map['current_rss_bytes']),
    peakRssBytes: _optionalCount(map['peak_rss_bytes']),
  );
}

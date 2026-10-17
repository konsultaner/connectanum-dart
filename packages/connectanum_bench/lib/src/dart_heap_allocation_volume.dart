/// Heap occupancy and native collection counters for one application group.
typedef DartHeapUsage = ({
  int usedBytes,
  int youngCollections,
  int oldCollections,
});

class DartHeapUsageSnapshot {
  const DartHeapUsageSnapshot({
    required this.beforeMicros,
    required this.afterMicros,
    required this.groups,
  });

  final int beforeMicros;
  final int afterMicros;
  final Map<String, DartHeapUsage> groups;
}

const dartHeapAllocationMethod = 'dart_heap_gc_volume_v1';
const dartHeapAllocationScope = 'dart_managed_heap_allocation_pressure';
const _maximumObservation = 9007199254740991;

int _count(Object? value, String label) {
  if (value is! int || value < 0 || value > _maximumObservation) {
    throw StateError('$label is not a bounded nonnegative integer');
  }
  return value;
}

int _kilobytes(Object? value, String label) {
  final parsed = value is String && RegExp(r'^\d+$').hasMatch(value)
      ? int.tryParse(value)
      : value;
  final count = _count(parsed, label);
  if (count > _maximumObservation ~/ 1024) {
    throw StateError('$label exceeds the byte observation limit');
  }
  return count * 1024;
}

int _sum(int left, int right) {
  final result = left + right;
  if (result.abs() > _maximumObservation) {
    throw StateError('allocation observations exceed the integer limit');
  }
  return result;
}

/// Occupancy change plus reclaimed bytes preserves allocations after collection.
/// Timeline KB rounding contributes at most 2 KiB uncertainty per collection.
/// Native collection counters independently detect lost/duplicated trace events.
/// GC inside a snapshot's RPC bracket cannot be attributed safely.
Map<String, Object?> dartHeapAllocationVolume(
  DartHeapUsageSnapshot? before,
  DartHeapUsageSnapshot? after,
  List<Map<String, dynamic>> events,
) {
  final expected = <String, (int, int)>{};
  final observed = <String, (int, int)>{};
  final observations = <Map<String, Object?>>[];
  try {
    if (before == null || after == null) {
      throw StateError('application heap observations are unavailable');
    }
    _count(before.beforeMicros, 'start snapshot timestamp');
    _count(after.afterMicros, 'end snapshot timestamp');
    if (before.afterMicros < before.beforeMicros ||
        after.beforeMicros <= before.afterMicros ||
        after.afterMicros < after.beforeMicros ||
        before.groups.isEmpty ||
        before.groups.length != after.groups.length ||
        before.groups.keys.any(
          (group) => group.isEmpty || !after.groups.containsKey(group),
        )) {
      throw StateError('heap identities or snapshot brackets changed');
    }
    var heapBefore = 0;
    var heapAfter = 0;
    for (final entry in before.groups.entries) {
      final start = entry.value;
      final end = after.groups[entry.key]!;
      heapBefore = _sum(heapBefore, _count(start.usedBytes, 'initial heap'));
      heapAfter = _sum(heapAfter, _count(end.usedBytes, 'final heap'));
      final young =
          _count(end.youngCollections, 'final young collections') -
          _count(start.youngCollections, 'initial young collections');
      final old =
          _count(end.oldCollections, 'final old collections') -
          _count(start.oldCollections, 'initial old collections');
      if (young < 0 || old < 0) throw StateError('collection counters rewound');
      expected[entry.key] = (young, old);
    }
    observed.addAll({for (final group in expected.keys) group: (0, 0)});
    final unique = <String, List<int>>{};
    var reclaimed = 0;
    var youngEvents = 0;
    var oldEvents = 0;
    for (final event in events) {
      if (event['cat'] != 'GC') continue;
      final args = event['args'];
      if (args is! Map) continue;
      final group = args['isolateGroupId'];
      if (!expected.containsKey(group)) continue;
      final name = event['name'];
      final young = name == 'CollectNewGeneration';
      final old =
          name == 'CollectOldGeneration' || name == 'StartConcurrentMarking';
      if (!young && !old) {
        if (args.containsKey('Before.New.Used (kB)')) {
          throw StateError('unsupported GC collection kind: $name');
        }
        continue;
      }
      final phase = event['ph'];
      if (phase != 'E' && phase != 'X') continue;
      final timestamp = _sum(
        _count(event['ts'], 'GC timestamp'),
        phase == 'X' ? _count(event['dur'], 'GC duration') : 0,
      );
      if ((timestamp >= before.beforeMicros &&
              timestamp <= before.afterMicros) ||
          (timestamp >= after.beforeMicros && timestamp <= after.afterMicros)) {
        throw StateError('GC overlaps a heap snapshot bracket');
      }
      if (timestamp < before.afterMicros || timestamp > after.beforeMicros) {
        continue;
      }
      final values = [
        for (final generation in ['New', 'Old']) ...[
          _kilobytes(args['Before.$generation.Used (kB)'], 'GC initial heap'),
          _kilobytes(args['After.$generation.Used (kB)'], 'GC final heap'),
        ],
      ];
      final key =
          '$group:${_count(event['tid'], 'GC thread')}:$timestamp:$name';
      final prior = unique[key];
      if (prior != null) {
        if (List.generate(4, (i) => prior[i] != values[i]).any((v) => v)) {
          throw StateError('conflicting duplicate GC observations');
        }
        continue;
      }
      unique[key] = values;
      observations.add({
        'isolate_group_id': group,
        'thread_id': _count(event['tid'], 'GC thread'),
        'timestamp_us': timestamp,
        'kind': name,
        'before_new_bytes': values[0],
        'after_new_bytes': values[1],
        'before_old_bytes': values[2],
        'after_old_bytes': values[3],
      });
      reclaimed = _sum(reclaimed, values[0] - values[1]);
      reclaimed = _sum(reclaimed, values[2] - values[3]);
      final counts = observed[group]!;
      observed[group as String] = (
        counts.$1 + (young ? 1 : 0),
        counts.$2 + (old ? 1 : 0),
      );
      if (young) youngEvents++;
      if (old) oldEvents++;
    }
    if (expected.keys.any((group) => expected[group] != observed[group])) {
      throw StateError('GC timeline does not match native collection counters');
    }
    final estimate = _sum(heapAfter - heapBefore, reclaimed);
    final uncertainty = unique.length * 2048;
    if (estimate < 0 || uncertainty * 100 > estimate) {
      throw StateError(
        'allocation estimate is negative or uncertainty exceeds 1%',
      );
    }
    return {
      'status': 'measured',
      'method': dartHeapAllocationMethod,
      'scope': dartHeapAllocationScope,
      'estimated_bytes': estimate,
      'rounding_error_bound_bytes': uncertainty,
      'heap_before_bytes': heapBefore,
      'heap_after_bytes': heapAfter,
      'reclaimed_bytes': reclaimed,
      'young_gc_events': youngEvents,
      'old_gc_events': oldEvents,
      'heap_group_ids': before.groups.keys.toList()..sort(),
      'start_snapshot_before_us': before.beforeMicros,
      'start_snapshot_after_us': before.afterMicros,
      'end_snapshot_before_us': after.beforeMicros,
      'end_snapshot_after_us': after.afterMicros,
      'heap_observations': {
        for (final entry in before.groups.entries)
          entry.key: {
            'before_used_bytes': entry.value.usedBytes,
            'after_used_bytes': after.groups[entry.key]!.usedBytes,
            'before_young_collections': entry.value.youngCollections,
            'after_young_collections':
                after.groups[entry.key]!.youngCollections,
            'before_old_collections': entry.value.oldCollections,
            'after_old_collections': after.groups[entry.key]!.oldCollections,
          },
      },
      'gc_observations': observations,
    };
  } on StateError catch (error) {
    return {
      'status': 'not_measured',
      'method': dartHeapAllocationMethod,
      'scope': dartHeapAllocationScope,
      'reason': error.message,
      // Failed evidence remains unavailable. Preserve the observations needed
      // to distinguish missing events from occupancy/rounding failures.
      'diagnostic_evidence': {
        'start_snapshot': _snapshotEvidence(before),
        'end_snapshot': _snapshotEvidence(after),
        'expected_collections': {
          for (final entry in expected.entries)
            entry.key: {'young': entry.value.$1, 'old': entry.value.$2},
        },
        'observed_collections': {
          for (final entry in observed.entries)
            entry.key: {'young': entry.value.$1, 'old': entry.value.$2},
        },
        'gc_observations': observations,
      },
    };
  }
}

Map<String, Object?>? _snapshotEvidence(DartHeapUsageSnapshot? snapshot) =>
    snapshot == null
    ? null
    : {
        'before_us': snapshot.beforeMicros,
        'after_us': snapshot.afterMicros,
        'groups': {
          for (final entry in snapshot.groups.entries)
            entry.key: {
              'used_bytes': entry.value.usedBytes,
              'young_collections': entry.value.youngCollections,
              'old_collections': entry.value.oldCollections,
            },
        },
      };

/// Retry only a heap snapshot crossed by GC, never the benchmark workload.
/// A later end snapshot retains every collection since the original start.
Future<DartHeapUsageSnapshot?> captureDartHeapBoundary({
  required Future<DartHeapUsageSnapshot?> Function() capture,
  required Future<List<Map<String, dynamic>>?> Function(DartHeapUsageSnapshot)
  events,
  required Future<void> Function() quiet,
}) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    final snapshot = await capture();
    if (snapshot == null) return null;
    final trace = await events(snapshot);
    if (trace == null) return null;
    var crossed = false;
    try {
      for (final event in trace) {
        if (event['cat'] != 'GC') continue;
        final args = event['args'];
        if (args is! Map ||
            !snapshot.groups.containsKey(args['isolateGroupId'])) {
          continue;
        }
        final name = event['name'];
        if (name != 'CollectNewGeneration' &&
            name != 'CollectOldGeneration' &&
            name != 'StartConcurrentMarking') {
          if (args.containsKey('Before.New.Used (kB)')) return null;
          continue;
        }
        final phase = event['ph'];
        if (phase != 'E' && phase != 'X') continue;
        final end = _sum(
          _count(event['ts'], 'GC timestamp'),
          phase == 'X' ? _count(event['dur'], 'GC duration') : 0,
        );
        if (end >= snapshot.beforeMicros && end <= snapshot.afterMicros) {
          crossed = true;
        }
      }
    } on StateError {
      return null;
    }
    if (!crossed) return snapshot;
    if (attempt < 2) await quiet();
  }
  return null;
}

import 'dart:async';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'dart_heap_allocation_volume.dart';

/// Captures Dart heap and GC counters for a supervised source WAMP worker.
///
/// The supervisor connects to the worker's VM service from a different
/// isolate/process so profiling RPCs can pause the target without pausing the
/// observer that must receive their replies.
abstract interface class DartVmMetricsObserver {
  Future<DartVmMetricsWindow> beginWindow();
  Future<DartVmMetricsResult> endWindow(
    DartVmMetricsWindow window, {
    required DartVmMetricsRssSnapshot rssSnapshot,
  });
  Future<void> close();
}

class DartVmMetricsCollector implements DartVmMetricsObserver {
  DartVmMetricsCollector._(
    this._service,
    this._pid, {
    required bool allIsolates,
  }) : _allIsolates = allIsolates {
    _gcSubscription = _service.onGCEvent.listen((_) => _gcEventGeneration++);
  }

  final VmService _service;
  final int _pid;
  final bool _allIsolates;
  late final StreamSubscription<Event> _gcSubscription;
  int _gcEventGeneration = 0;
  bool _timelineAvailable = false;
  String? _observedSdk;

  static Future<DartVmMetricsCollector> connect({
    required Uri serviceUri,
    required int pid,
    bool allIsolates = false,
  }) async {
    final websocketUri = serviceUri.replace(scheme: 'ws').resolve('ws');
    final service = await vmServiceConnectUri(websocketUri.toString());
    try {
      final vm = await service.getVM();
      if (vm.pid != pid) {
        throw StateError('VM service PID does not match the observed process');
      }
      final isolates = vm.isolates ?? const <IsolateRef>[];
      final isolateIds = selectDartVmMetricIsolateIds(
        isolates,
        allIsolates: allIsolates,
      );
      if (isolateIds.isEmpty) {
        throw StateError('Observed WAMP process has no application isolates');
      }
      final collector = DartVmMetricsCollector._(
        service,
        pid,
        allIsolates: allIsolates,
      );
      await service.streamListen('GC');
      collector._observedSdk = vm.version;
      await collector._enableGcTimeline();
      return collector;
    } catch (_) {
      await service.dispose();
      rethrow;
    }
  }

  @override
  Future<DartVmMetricsWindow> beginWindow() async {
    final isolates = (await _service.getVM()).isolates ?? const <IsolateRef>[];
    final isolateIds = selectDartVmMetricIsolateIds(
      isolates,
      allIsolates: _allIsolates,
    );
    if (isolateIds.isEmpty) {
      throw StateError('Observed WAMP process has no application isolates');
    }
    final profiledIsolateIds = selectDartVmMetricHeapRepresentativeIds(
      isolates,
      isolateIds,
    );
    if (profiledIsolateIds == null) {
      throw StateError('Observed VM has no reliable isolate-group metadata');
    }
    await _waitForGcEventDrain();
    Map<String, DartVmGcHeapSnapshot>? gcSnapshots;
    final allocationSnapshot = await captureDartHeapBoundary(
      capture: () async {
        final before = await _timelineMicros();
        gcSnapshots = await _gcHeapSnapshots(profiledIsolateIds);
        final after = await _timelineMicros();
        return _allocationSnapshot(gcSnapshots, before, after);
      },
      events: (snapshot) => _allocationEvents(snapshot, snapshot),
      quiet: () async {
        await _waitForGcEventDrain();
      },
    );
    final cpuTicks = await _readLinuxCpuTicks(_pid);
    return DartVmMetricsWindow(
      cpuUserTicks: cpuTicks?.user,
      cpuSystemTicks: cpuTicks?.system,
      isolateIds: isolateIds,
      gcSnapshots: gcSnapshots,
      profiledIsolateIds: profiledIsolateIds,
      allocationSnapshot: allocationSnapshot,
    );
  }

  @override
  Future<DartVmMetricsResult> endWindow(
    DartVmMetricsWindow window, {
    required DartVmMetricsRssSnapshot rssSnapshot,
  }) async {
    final cpuAfter = await _readLinuxCpuTicks(_pid);
    final isolateIds = await _currentIsolateIds();
    requireStableDartVmMetricIsolates(window.isolateIds, isolateIds);
    final profiledIsolateIds = window.profiledIsolateIds;
    final gcStable = await _waitForGcEventDrain();
    Map<String, DartVmGcHeapSnapshot>? gcSnapshots;
    final allocationAfter = await captureDartHeapBoundary(
      capture: () async {
        final before = await _timelineMicros();
        gcSnapshots = profiledIsolateIds == null || profiledIsolateIds.isEmpty
            ? null
            : await _gcHeapSnapshots(profiledIsolateIds);
        final after = await _timelineMicros();
        return _allocationSnapshot(gcSnapshots, before, after);
      },
      events: (snapshot) => _allocationEvents(snapshot, snapshot),
      quiet: () async {
        await _waitForGcEventDrain();
      },
    );
    final events = await _allocationEvents(
      window.allocationSnapshot,
      allocationAfter,
    );
    final allocation = dartHeapAllocationVolume(
      gcStable && events != null ? window.allocationSnapshot : null,
      allocationAfter,
      events ?? const [],
    );
    allocation.addAll({
      'sdk_version': _observedSdk,
      'observed_pid': _pid,
      'observer_pid': pid,
      'capture_strategy': pid == _pid ? 'self_observed' : 'external_process',
    });
    final userTicks = window.cpuUserTicks == null || cpuAfter == null
        ? null
        : cpuAfter.user - window.cpuUserTicks!;
    final systemTicks = window.cpuSystemTicks == null || cpuAfter == null
        ? null
        : cpuAfter.system - window.cpuSystemTicks!;
    final tickRate = userTicks == null || systemTicks == null
        ? null
        : await _linuxClockTicksPerSecond();
    final gcMetrics = gcStable
        ? dartVmGcHeapDelta(window.gcSnapshots, gcSnapshots)
        : null;
    return DartVmMetricsResult(
      allocatedBytes: allocation['estimated_bytes'] as int?,
      allocationMeasurement: allocation,
      gcCount: gcMetrics?.count,
      gcPauseMicros: gcMetrics?.pauseMicros,
      cpuUserMicros: userTicks == null || tickRate == null || userTicks < 0
          ? null
          : (userTicks * 1000000 / tickRate).round(),
      cpuSystemMicros:
          systemTicks == null || tickRate == null || systemTicks < 0
          ? null
          : (systemTicks * 1000000 / tickRate).round(),
      currentRssBytes: rssSnapshot.currentRssBytes,
      peakRssBytes: rssSnapshot.peakRssBytes,
    );
  }

  Future<void> _enableGcTimeline() async {
    try {
      final flags = await _service.getVMTimelineFlags();
      final streams = flags.recordedStreams;
      if (streams == null) return;
      if (!streams.contains('GC')) {
        await _service.setVMTimelineFlags([...streams, 'GC']);
      }
      _timelineAvailable =
          (await _service.getVMTimelineFlags()).recordedStreams?.contains(
            'GC',
          ) ==
          true;
    } on RPCError {
      _timelineAvailable = false;
    }
  }

  Future<int?> _timelineMicros() async {
    if (!_timelineAvailable) return null;
    try {
      return (await _service.getVMTimelineMicros()).timestamp;
    } on RPCError {
      return null;
    }
  }

  DartHeapUsageSnapshot? _allocationSnapshot(
    Map<String, DartVmGcHeapSnapshot>? snapshots,
    int? before,
    int? after,
  ) {
    if (snapshots == null ||
        before == null ||
        after == null ||
        snapshots.values.any((snapshot) => snapshot.heapUsedBytes == null)) {
      return null;
    }
    return DartHeapUsageSnapshot(
      beforeMicros: before,
      afterMicros: after,
      groups: {
        for (final entry in snapshots.entries)
          entry.key: (
            usedBytes: entry.value.heapUsedBytes!,
            youngCollections: entry.value.newCollections,
            oldCollections: entry.value.oldCollections,
          ),
      },
    );
  }

  Future<List<Map<String, dynamic>>?> _allocationEvents(
    DartHeapUsageSnapshot? before,
    DartHeapUsageSnapshot? after,
  ) async {
    if (before == null ||
        after == null ||
        after.afterMicros < before.beforeMicros) {
      return null;
    }
    try {
      final timeline = await _service.getVMTimeline(
        timeOriginMicros: before.beforeMicros,
        timeExtentMicros: after.afterMicros - before.beforeMicros,
      );
      return timeline.traceEvents?.map((event) => event.toJson()).toList();
    } on RPCError {
      return null;
    }
  }

  Future<Map<String, DartVmGcHeapSnapshot>?> _gcHeapSnapshots(
    List<String> isolateIds,
  ) async {
    final snapshots = <String, DartVmGcHeapSnapshot>{};
    for (final id in isolateIds) {
      final isolate = await _service.getIsolate(id);
      final groupId = isolate.isolateGroupId;
      if (groupId == null || groupId.isEmpty) return null;
      if (snapshots.containsKey(groupId)) continue;
      final snapshot = DartVmGcHeapSnapshot.parse(isolate.json);
      if (snapshot == null) return null;
      snapshots[groupId] = snapshot;
    }
    return snapshots;
  }

  Future<List<String>> _currentIsolateIds() async =>
      selectDartVmMetricIsolateIds(
        (await _service.getVM()).isolates ?? const <IsolateRef>[],
        allIsolates: _allIsolates,
      );

  Future<bool> _waitForGcEventDrain() async {
    final elapsed = Stopwatch()..start();
    var previousGeneration = _gcEventGeneration;
    var lastEventAt = Duration.zero;
    const quietPeriod = Duration(milliseconds: 50);
    const maximumWait = Duration(milliseconds: 250);
    while (elapsed.elapsed < maximumWait) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final generation = _gcEventGeneration;
      if (generation != previousGeneration) {
        previousGeneration = generation;
        lastEventAt = elapsed.elapsed;
      }
      if (elapsed.elapsed - lastEventAt >= quietPeriod) return true;
    }
    return false;
  }

  @override
  Future<void> close() async {
    await _gcSubscription.cancel();
    await _service.dispose();
  }
}

class DartVmMetricsWindow {
  const DartVmMetricsWindow({
    required this.cpuUserTicks,
    required this.cpuSystemTicks,
    required this.isolateIds,
    this.gcSnapshots,
    this.profiledIsolateIds,
    this.allocationSnapshot,
  });

  final int? cpuUserTicks;
  final int? cpuSystemTicks;
  final List<String> isolateIds;
  final Map<String, DartVmGcHeapSnapshot>? gcSnapshots;
  final List<String>? profiledIsolateIds;
  final DartHeapUsageSnapshot? allocationSnapshot;
}

/// Cumulative GC statistics for one shared VM isolate-group heap.
///
/// The pinned VM exposes its native collection count and foreground GC time
/// through `_heaps`. Unsupported/malformed fields remain unavailable. Isolates
/// sharing one group must use one representative snapshot to avoid counting the
/// same heap twice; GC stream notifications are duplicated for every isolate.
class DartVmGcHeapSnapshot {
  const DartVmGcHeapSnapshot({
    required this.newCollections,
    required this.oldCollections,
    required this.newPauseMicros,
    required this.oldPauseMicros,
    this.heapUsedBytes,
  });

  final int newCollections;
  final int oldCollections;
  final int newPauseMicros;
  final int oldPauseMicros;
  final int? heapUsedBytes;

  static DartVmGcHeapSnapshot? parse(Map<String, dynamic>? isolate) {
    final heaps = isolate?['_heaps'];
    if (heaps is! Map) return null;
    (int, int)? space(Object? value) {
      if (value is! Map) return null;
      final count = value['collections'];
      final seconds = value['time'];
      if (count is! int ||
          count < 0 ||
          seconds is! num ||
          !seconds.isFinite ||
          seconds < 0) {
        return null;
      }
      final micros = seconds * 1000000;
      if (!micros.isFinite || micros > (1 << 62)) return null;
      return (count, micros.round());
    }

    final young = space(heaps['new']);
    final old = space(heaps['old']);
    if (young == null || old == null) return null;
    int? used(Object? raw) {
      if (raw is! Map) return null;
      final value = raw['used'];
      return value is int && value >= 0 && value <= 9007199254740991
          ? value
          : null;
    }

    final newUsed = used(heaps['new']);
    final oldUsed = used(heaps['old']);
    return DartVmGcHeapSnapshot(
      heapUsedBytes: newUsed == null || oldUsed == null
          ? null
          : newUsed + oldUsed,
      newCollections: young.$1,
      oldCollections: old.$1,
      newPauseMicros: young.$2,
      oldPauseMicros: old.$2,
    );
  }
}

/// Sums native GC counter deltas once per observed isolate group.
/// Missing groups, unsupported fields or a rewound counter cannot become zero.
({int count, int pauseMicros})? dartVmGcHeapDelta(
  Map<String, DartVmGcHeapSnapshot>? before,
  Map<String, DartVmGcHeapSnapshot>? after,
) {
  if (before == null ||
      after == null ||
      before.isEmpty ||
      before.length != after.length ||
      before.keys.any((group) => !after.containsKey(group))) {
    return null;
  }
  var count = 0;
  var pauseMicros = 0;
  for (final entry in before.entries) {
    final current = after[entry.key]!;
    final old = entry.value;
    final youngCount = current.newCollections - old.newCollections;
    final oldCount = current.oldCollections - old.oldCollections;
    final youngPause = current.newPauseMicros - old.newPauseMicros;
    final oldPause = current.oldPauseMicros - old.oldPauseMicros;
    if (youngCount < 0 || oldCount < 0 || youngPause < 0 || oldPause < 0) {
      return null;
    }
    count += youngCount + oldCount;
    pauseMicros += youngPause + oldPause;
  }
  return (count: count, pauseMicros: pauseMicros);
}

/// Chooses one representative for each shared application heap.
/// All selected isolate IDs are still retained for lifecycle validation.
List<String>? selectDartVmMetricHeapRepresentativeIds(
  List<IsolateRef> isolates,
  List<String> selectedIds,
) {
  final references = {for (final isolate in isolates) isolate.id: isolate};
  final groups = <String>{};
  final result = <String>[];
  for (final id in selectedIds) {
    final groupId = references[id]?.isolateGroupId;
    if (groupId == null || groupId.isEmpty) return null;
    if (groups.add(groupId)) result.add(id);
  }
  return result;
}

/// Returns all application isolate IDs monitored in a WAMP process.
///
/// The client worker normally profiles only its main isolate. The router
/// benchmark profiles every live isolate because routing work runs in the
/// configured worker pool.
List<String> selectDartVmMetricIsolateIds(
  List<IsolateRef> isolates, {
  required bool allIsolates,
}) {
  final applicationIsolates = isolates.where(
    (candidate) => candidate.isSystemIsolate != true,
  );
  final candidates = allIsolates
      ? applicationIsolates
      : applicationIsolates.where((candidate) => candidate.name == 'main');
  final ids =
      candidates
          .map((candidate) => candidate.id)
          .whereType<String>()
          .toSet()
          .toList()
        ..sort();
  if (ids.isNotEmpty || allIsolates || applicationIsolates.isEmpty) return ids;

  final fallbackId = applicationIsolates.first.id;
  return fallbackId == null ? const <String>[] : <String>[fallbackId];
}

/// Fails closed when a benchmark's profiled isolate set changes mid-window.
void requireStableDartVmMetricIsolates(
  List<String> before,
  List<String> after,
) {
  final beforeIds = before.toSet();
  final afterIds = after.toSet();
  if (beforeIds.length != afterIds.length || !beforeIds.containsAll(afterIds)) {
    throw StateError(
      'Dart VM isolate set changed during metrics window '
      '(before: ${beforeIds.toList()..sort()}, after: ${afterIds.toList()..sort()})',
    );
  }
}

class DartVmMetricsResult {
  const DartVmMetricsResult({
    required this.allocatedBytes,
    required this.gcCount,
    required this.gcPauseMicros,
    required this.cpuUserMicros,
    required this.cpuSystemMicros,
    required this.currentRssBytes,
    required this.peakRssBytes,
    this.allocationMeasurement,
  });

  final int? allocatedBytes;
  final Map<String, Object?>? allocationMeasurement;
  final int? gcCount;
  final int? gcPauseMicros;
  final int? cpuUserMicros;
  final int? cpuSystemMicros;
  final int? currentRssBytes;
  final int? peakRssBytes;
}

class DartVmMetricsRssSnapshot {
  const DartVmMetricsRssSnapshot({
    required this.currentRssBytes,
    required this.peakRssBytes,
    this.lifetimeMaxRssBytes,
    this.lifetimeMaxReadAttemptsBytes = const [],
  });

  final int? currentRssBytes;
  final int? peakRssBytes;
  // A fresh OS lifetime high-water value, captured after the final live sample.
  final int? lifetimeMaxRssBytes;
  final List<int?> lifetimeMaxReadAttemptsBytes;
}

/// The two process RSS fields read from one procfs status snapshot.
typedef DartVmMetricsRssEndpoint = ({
  int? currentRssBytes,
  int? lifetimeMaxRssBytes,
});

class DartVmMetricsRssSampler {
  DartVmMetricsRssSampler(
    int pid, {
    Future<int?> Function()? readRssBytes,
    Future<int?> Function()? readMaxRssBytes,
    // An explicit endpoint reader overrides the default paired procfs read.
    // Individual legacy overrides keep their separate final-read behavior.
    Future<DartVmMetricsRssEndpoint> Function()? readFinalRss,
  }) : _readRssBytes = readRssBytes ?? (() => _readLinuxRssBytes(pid)),
       _readMaxRssBytes =
           readMaxRssBytes ?? (() => _readLinuxStatusBytes(pid, 'VmHWM:')),
       _readFinalRss =
           readFinalRss ??
           (readRssBytes == null && readMaxRssBytes == null
               ? () => _readLinuxRssEndpoint(pid)
               : null) {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _sample());
    _sample();
  }

  final Future<int?> Function() _readRssBytes;
  final Future<int?> Function() _readMaxRssBytes;
  final Future<DartVmMetricsRssEndpoint> Function()? _readFinalRss;
  bool _lastReadSucceeded = false;
  late final Timer _timer;
  bool _stopped = false;
  Future<void>? _sampleInFlight;
  Future<DartVmMetricsRssSnapshot>? _stopFuture;
  int? currentRssBytes;
  int? peakRssBytes;

  void _sample() {
    if (_stopped || _sampleInFlight != null) return;
    unawaited(_startSample());
  }

  Future<void> _startSample() {
    late final Future<void> sample;
    sample = _readAndRecordSample().whenComplete(() {
      if (identical(_sampleInFlight, sample)) _sampleInFlight = null;
    });
    _sampleInFlight = sample;
    return sample;
  }

  Future<void> _readAndRecordSample() async {
    _lastReadSucceeded = false;
    try {
      _recordRss(await _readRssBytes());
    } on FileSystemException {
      // The child may have exited between a timer tick and its final sample.
    }
  }

  void _recordRss(int? bytes) {
    if (bytes == null || bytes <= 0 || bytes > 9007199254740991) return;
    _lastReadSucceeded = true;
    currentRssBytes = bytes;
    if (bytes > (peakRssBytes ?? 0)) peakRssBytes = bytes;
  }

  Future<DartVmMetricsRssSnapshot> stop() => _stopFuture ??= _stop();

  Future<DartVmMetricsRssSnapshot> _stop() async {
    if (!_stopped) {
      _stopped = true;
      _timer.cancel();
    }
    final inFlight = _sampleInFlight;
    if (inFlight != null) await inFlight;
    final endpointReader = _readFinalRss;
    DartVmMetricsRssEndpoint? endpoint;
    if (endpointReader == null) {
      await _startSample();
    } else {
      _lastReadSucceeded = false;
      try {
        endpoint = await endpointReader();
        _recordRss(endpoint.currentRssBytes);
      } on FileSystemException {
        // A failed endpoint must not reuse a preceding live observation.
      }
    }
    final current = _lastReadSucceeded ? currentRssBytes : null;
    int? maximum;
    final attempts = <int?>[];
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        // Linux emits VmRSS and VmHWM from the same total_rss local. Preserve
        // that endpoint pairing before any bounded, actual HWM rereads.
        maximum = attempt == 0 && endpointReader != null
            ? endpoint?.lifetimeMaxRssBytes
            : await _readMaxRssBytes();
      } on FileSystemException {
        maximum = null;
      }
      attempts.add(maximum);
      if (current == null ||
          maximum == null ||
          maximum <= 0 ||
          maximum > 9007199254740991 ||
          maximum >= (peakRssBytes ?? current)) {
        break;
      }
      // Linux RSS accounting can lag between procfs reads. Retain every actual
      // observation and reread a bounded number of times; never infer a high
      // water mark from a live sample or replace a missing process value.
      if (attempt < 2) await Future<void>.delayed(Duration.zero);
    }
    if (current == null ||
        maximum == null ||
        maximum > 9007199254740991 ||
        maximum < (peakRssBytes ?? current)) {
      maximum = null;
    }
    return DartVmMetricsRssSnapshot(
      currentRssBytes: current,
      peakRssBytes: peakRssBytes,
      lifetimeMaxRssBytes: maximum,
      lifetimeMaxReadAttemptsBytes: List.unmodifiable(attempts),
    );
  }
}

Future<int?> _readLinuxRssBytes(int pid) =>
    _readLinuxStatusBytes(pid, 'VmRSS:');

Future<DartVmMetricsRssEndpoint> _readLinuxRssEndpoint(int pid) async {
  if (Platform.isLinux) {
    try {
      final status = await File('/proc/$pid/status').readAsString();
      return (
        currentRssBytes: _parseLinuxStatusBytes(status, 'VmRSS:'),
        lifetimeMaxRssBytes: _parseLinuxStatusBytes(status, 'VmHWM:'),
      );
    } on FileSystemException {
      // The supervised process may have exited before its final read.
    }
  }
  return (currentRssBytes: null, lifetimeMaxRssBytes: null);
}

Future<int?> _readLinuxStatusBytes(int pid, String field) async {
  if (!Platform.isLinux) return null;
  try {
    final status = await File('/proc/$pid/status').readAsString();
    return _parseLinuxStatusBytes(status, field);
  } on FileSystemException {
    // The child may have exited between a timer tick and its final sample.
  }
  return null;
}

int? _parseLinuxStatusBytes(String status, String field) {
  for (final line in status.split('\n')) {
    if (!line.startsWith(field)) continue;
    final kilobytes = int.tryParse(
      line.substring(field.length).trim().split(RegExp(r'\s+')).first,
    );
    return kilobytes == null ||
            kilobytes <= 0 ||
            kilobytes > 9007199254740991 ~/ 1024
        ? null
        : kilobytes * 1024;
  }
  return null;
}

class _LinuxCpuTicks {
  const _LinuxCpuTicks(this.user, this.system);

  final int user;
  final int system;
}

Future<_LinuxCpuTicks?> _readLinuxCpuTicks(int pid) async {
  if (!Platform.isLinux) return null;
  try {
    final stat = await File('/proc/$pid/stat').readAsString();
    final closingParenthesis = stat.lastIndexOf(')');
    if (closingParenthesis < 0 || closingParenthesis + 1 >= stat.length) {
      return null;
    }
    final fields = stat
        .substring(closingParenthesis + 1)
        .trim()
        .split(RegExp(r'\s+'));
    // The substring starts at proc field 3 (state), making utime/stime 11/12.
    if (fields.length <= 12) return null;
    final user = int.tryParse(fields[11]);
    final system = int.tryParse(fields[12]);
    if (user == null || system == null || user < 0 || system < 0) return null;
    return _LinuxCpuTicks(user, system);
  } on FileSystemException {
    return null;
  }
}

Future<int?>? _clockTicksPerSecondFuture;

Future<int?> _linuxClockTicksPerSecond() {
  if (!Platform.isLinux) return Future<int?>.value(null);
  return _clockTicksPerSecondFuture ??= _loadClockTicksPerSecond();
}

Future<int?> _loadClockTicksPerSecond() async {
  try {
    final result = await Process.run('getconf', ['CLK_TCK']);
    if (result.exitCode != 0) return null;
    final value = int.tryParse('${result.stdout}'.trim());
    return value != null && value > 0 ? value : null;
  } on ProcessException {
    return null;
  }
}

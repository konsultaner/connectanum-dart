import 'dart:async';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Captures Dart heap and GC counters for a supervised source WAMP worker.
///
/// The supervisor connects to the worker's VM service from a different
/// isolate/process so profiling RPCs can pause the target without pausing the
/// observer that must receive their replies.
class DartVmMetricsCollector {
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

  static Future<DartVmMetricsCollector> connect({
    required Uri serviceUri,
    required int pid,
    bool allIsolates = false,
  }) async {
    final websocketUri = serviceUri.replace(scheme: 'ws').resolve('ws');
    final service = await vmServiceConnectUri(websocketUri.toString());
    try {
      final vm = await service.getVM();
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
      return collector;
    } catch (_) {
      await service.dispose();
      rethrow;
    }
  }

  Future<DartVmMetricsWindow> beginWindow() async {
    final isolateIds = await _currentIsolateIds();
    if (isolateIds.isEmpty) {
      throw StateError('Observed WAMP process has no application isolates');
    }
    await Future.wait(
      isolateIds.map(
        (isolateId) => _service.getAllocationProfile(isolateId, reset: true),
      ),
    );
    await _waitForGcEventDrain();
    await _service.clearVMTimeline();
    final cpuTicks = await _readLinuxCpuTicks(_pid);
    return DartVmMetricsWindow(
      cpuUserTicks: cpuTicks?.user,
      cpuSystemTicks: cpuTicks?.system,
      isolateIds: isolateIds,
    );
  }

  Future<DartVmMetricsResult> endWindow(
    DartVmMetricsWindow window, {
    required DartVmMetricsRssSnapshot rssSnapshot,
  }) async {
    final isolateIds = await _currentIsolateIds();
    requireStableDartVmMetricIsolates(window.isolateIds, isolateIds);
    var allocatedBytes = 0;
    var allocationComplete = true;
    for (final isolateId in isolateIds) {
      final allocation = await _service.getAllocationProfile(isolateId);
      final members = allocation.members;
      if (members == null) {
        allocationComplete = false;
        continue;
      }
      for (final member in members) {
        final size = member.accumulatedSize;
        if (size == null || size < 0) {
          allocationComplete = false;
          continue;
        }
        allocatedBytes = (allocatedBytes + size).clamp(0, 1 << 62).toInt();
      }
    }
    final timelineStable = await _waitForGcEventDrain();
    final timeline = await _service.getVMTimeline();
    final cpuAfter = await _readLinuxCpuTicks(_pid);
    final userTicks = window.cpuUserTicks == null || cpuAfter == null
        ? null
        : cpuAfter.user - window.cpuUserTicks!;
    final systemTicks = window.cpuSystemTicks == null || cpuAfter == null
        ? null
        : cpuAfter.system - window.cpuSystemTicks!;
    final tickRate = userTicks == null || systemTicks == null
        ? null
        : await _linuxClockTicksPerSecond();
    final gcMetrics = _gcMetricsFromTimeline(timeline, stable: timelineStable);
    return DartVmMetricsResult(
      allocatedBytes: allocationComplete ? allocatedBytes : null,
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
  });

  final int? cpuUserTicks;
  final int? cpuSystemTicks;
  final List<String> isolateIds;
}

class _DartVmGcMetrics {
  const _DartVmGcMetrics(this.count, this.pauseMicros);

  final int count;
  final int pauseMicros;
}

_DartVmGcMetrics? _gcMetricsFromTimeline(
  Timeline timeline, {
  required bool stable,
}) {
  final events = timeline.traceEvents;
  if (!stable || events == null) return null;
  var count = 0;
  var pauseMicros = 0;
  var completeDurations = true;
  for (final event in events) {
    final json = event.json;
    if (json == null) continue;
    final name = json['name'];
    final phase = json['ph'];
    if (name is! String ||
        !name.toLowerCase().contains('gc') ||
        (phase != null && phase != 'X')) {
      continue;
    }
    count++;
    final duration = json['dur'];
    if (duration is num && duration.isFinite && duration >= 0) {
      pauseMicros += duration.round();
    } else {
      completeDurations = false;
    }
  }
  return completeDurations ? _DartVmGcMetrics(count, pauseMicros) : null;
}

/// Returns the isolate IDs used for allocation profiling in a WAMP process.
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
  });

  final int? allocatedBytes;
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
  });

  final int? currentRssBytes;
  final int? peakRssBytes;
}

class DartVmMetricsRssSampler {
  DartVmMetricsRssSampler(int pid, {Future<int?> Function()? readRssBytes})
    : _readRssBytes = readRssBytes ?? (() => _readLinuxRssBytes(pid)) {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _sample());
    _sample();
  }

  final Future<int?> Function() _readRssBytes;
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
    try {
      final bytes = await _readRssBytes();
      if (bytes == null || bytes <= 0) return;
      currentRssBytes = bytes;
      if (bytes > (peakRssBytes ?? 0)) peakRssBytes = bytes;
    } on FileSystemException {
      // The child may have exited between a timer tick and its final sample.
    }
  }

  Future<DartVmMetricsRssSnapshot> stop() => _stopFuture ??= _stop();

  Future<DartVmMetricsRssSnapshot> _stop() async {
    if (!_stopped) {
      _stopped = true;
      _timer.cancel();
    }
    final inFlight = _sampleInFlight;
    if (inFlight != null) await inFlight;
    await _startSample();
    return DartVmMetricsRssSnapshot(
      currentRssBytes: currentRssBytes,
      peakRssBytes: peakRssBytes,
    );
  }
}

Future<int?> _readLinuxRssBytes(int pid) async {
  if (!Platform.isLinux) return null;
  try {
    final status = await File('/proc/$pid/status').readAsString();
    for (final line in status.split('\n')) {
      if (!line.startsWith('VmRSS:')) continue;
      final kilobytes = int.tryParse(
        line.substring('VmRSS:'.length).trim().split(RegExp(r'\s+')).first,
      );
      return kilobytes == null || kilobytes <= 0 ? null : kilobytes * 1024;
    }
  } on FileSystemException {
    // The child may have exited between a timer tick and its final sample.
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

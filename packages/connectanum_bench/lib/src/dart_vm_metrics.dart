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
  DartVmMetricsCollector._(this._service, this._isolateId, this._pid) {
    _gcSubscription = _service.onGCEvent.listen((_) => _gcEvents++);
  }

  final VmService _service;
  final String _isolateId;
  final int _pid;
  late final StreamSubscription<Event> _gcSubscription;
  int _gcEvents = 0;

  static Future<DartVmMetricsCollector> connect({
    required Uri serviceUri,
    required int pid,
  }) async {
    final websocketUri = serviceUri.replace(scheme: 'ws').resolve('ws');
    final service = await vmServiceConnectUri(websocketUri.toString());
    try {
      final vm = await service.getVM();
      final isolates = vm.isolates ?? const <IsolateRef>[];
      IsolateRef? isolate;
      for (final candidate in isolates) {
        if (candidate.name == 'main') {
          isolate = candidate;
          break;
        }
      }
      isolate ??= isolates.isEmpty ? null : isolates.first;
      final isolateId = isolate?.id;
      if (isolateId == null) {
        throw StateError('Observed WAMP worker has no main isolate');
      }
      final collector = DartVmMetricsCollector._(service, isolateId, pid);
      await service.streamListen('GC');
      return collector;
    } catch (_) {
      await service.dispose();
      rethrow;
    }
  }

  Future<DartVmMetricsWindow> beginWindow() async {
    await _service.clearVMTimeline();
    await _service.getAllocationProfile(_isolateId, reset: true);
    final cpuTicks = await _readLinuxCpuTicks(_pid);
    return DartVmMetricsWindow(
      gcEvents: _gcEvents,
      cpuUserTicks: cpuTicks?.user,
      cpuSystemTicks: cpuTicks?.system,
    );
  }

  Future<DartVmMetricsResult> endWindow(
    DartVmMetricsWindow window, {
    required int? peakRssBytes,
  }) async {
    // Let the service event stream deliver collections that ended with the
    // workload before taking the final counter value.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final allocation = await _service.getAllocationProfile(_isolateId);
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
    final allocatedBytes = allocation.members?.fold<int>(
      0,
      (sum, member) =>
          sum + (member.accumulatedSize ?? 0).clamp(0, 1 << 62).toInt(),
    );
    var gcPauseMicros = 0;
    for (final event in timeline.traceEvents ?? const <TimelineEvent>[]) {
      final json = event.json;
      if (json == null) continue;
      final name = json['name'];
      final duration = json['dur'];
      final phase = json['ph'];
      if (name is String &&
          name.toLowerCase().contains('gc') &&
          (phase == null || phase == 'X') &&
          duration is num &&
          duration.isFinite &&
          duration > 0) {
        gcPauseMicros += duration.round();
      }
    }
    return DartVmMetricsResult(
      allocatedBytes: allocatedBytes,
      gcCount: (_gcEvents - window.gcEvents).clamp(0, 1 << 62).toInt(),
      gcPauseMicros: gcPauseMicros,
      cpuUserMicros: userTicks == null || tickRate == null || userTicks < 0
          ? null
          : (userTicks * 1000000 / tickRate).round(),
      cpuSystemMicros:
          systemTicks == null || tickRate == null || systemTicks < 0
          ? null
          : (systemTicks * 1000000 / tickRate).round(),
      peakRssBytes: peakRssBytes,
    );
  }

  Future<void> close() async {
    await _gcSubscription.cancel();
    await _service.dispose();
  }
}

class DartVmMetricsWindow {
  const DartVmMetricsWindow({
    required this.gcEvents,
    required this.cpuUserTicks,
    required this.cpuSystemTicks,
  });

  final int gcEvents;
  final int? cpuUserTicks;
  final int? cpuSystemTicks;
}

class DartVmMetricsResult {
  const DartVmMetricsResult({
    required this.allocatedBytes,
    required this.gcCount,
    required this.gcPauseMicros,
    required this.cpuUserMicros,
    required this.cpuSystemMicros,
    required this.peakRssBytes,
  });

  final int? allocatedBytes;
  final int? gcCount;
  final int? gcPauseMicros;
  final int? cpuUserMicros;
  final int? cpuSystemMicros;
  final int? peakRssBytes;
}

class DartVmMetricsRssSampler {
  DartVmMetricsRssSampler(int pid) : _file = File('/proc/$pid/status') {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _sample());
    _sample();
  }

  final File _file;
  late final Timer _timer;
  bool _stopped = false;
  bool _sampling = false;
  int? peakRssBytes;

  void _sample() {
    unawaited(_sampleNow());
  }

  Future<void> _sampleNow({bool finalSample = false}) async {
    if ((_stopped && !finalSample) || _sampling || !Platform.isLinux) return;
    _sampling = true;
    try {
      final status = await _file.readAsString();
      for (final line in status.split('\n')) {
        if (!line.startsWith('VmRSS:')) continue;
        final kilobytes = int.tryParse(
          line.substring('VmRSS:'.length).trim().split(RegExp(r'\s+')).first,
        );
        if (kilobytes == null || kilobytes <= 0) return;
        final bytes = kilobytes * 1024;
        if (bytes > (peakRssBytes ?? 0)) peakRssBytes = bytes;
        return;
      }
    } on FileSystemException {
      // The child may have exited between a timer tick and its final sample.
    } finally {
      _sampling = false;
    }
  }

  Future<int?> stop() async {
    if (!_stopped) {
      _stopped = true;
      _timer.cancel();
      await _sampleNow(finalSample: true);
    }
    return peakRssBytes;
  }
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

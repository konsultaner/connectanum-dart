import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_bench/src/dart_vm_metrics.dart';
import 'package:connectanum_bench/src/dart_vm_metrics_external.dart';
import 'package:vm_service/vm_service_io.dart';

List<Uint8List> _retainedBuffers = <Uint8List>[];

Future<void> main() async {
  final messages = ReceivePort();
  final workerReady = Completer<SendPort>();
  final allocationComplete = Completer<void>();
  final workerStopped = Completer<void>();
  messages.listen((message) {
    if (message is SendPort) {
      workerReady.complete(message);
    } else if (message == 256) {
      allocationComplete.complete();
    } else if (message == 'stopped') {
      workerStopped.complete();
    }
  });
  final worker = await Isolate.spawn(_allocationWorker, messages.sendPort);
  final workerPort = await workerReady.future.timeout(
    const Duration(seconds: 5),
  );
  final serviceUri = (await developer.Service.getInfo()).serverUri;
  if (serviceUri == null) {
    throw StateError('Probe has no Dart VM service URI');
  }
  final collector = await ExternalDartVmMetricsCollector.connect(
    serviceUri: serviceUri,
    pid: pid,
    allIsolates: true,
  );

  try {
    final window = await collector.beginWindow();
    workerPort.send('allocate');
    await allocationComplete.future.timeout(const Duration(seconds: 5));
    // Force actual collections after allocation so zero is not a valid result.
    final observer = await vmServiceConnectUri(
      serviceUri.replace(scheme: 'ws').resolve('ws').toString(),
    );
    try {
      final isolates = (await observer.getVM()).isolates!;
      for (final isolate in isolates) {
        if (isolate.isSystemIsolate != true) {
          await observer.getAllocationProfile(isolate.id!, gc: true);
        }
      }
    } finally {
      await observer.dispose();
    }
    final rssBytes = ProcessInfo.currentRss;
    final metrics = await collector.endWindow(
      window,
      rssSnapshot: DartVmMetricsRssSnapshot(
        currentRssBytes: rssBytes,
        peakRssBytes: rssBytes,
      ),
    );
    final historyObserver = await vmServiceConnectUri(
      serviceUri.replace(scheme: 'ws').resolve('ws').toString(),
    );
    var previousTimelineCleared = false;
    try {
      final cutoff = (await historyObserver.getVMTimelineMicros()).timestamp!;
      await collector.beginWindow();
      final timeline = await historyObserver.getVMTimeline();
      previousTimelineCleared = timeline.traceEvents!.every((event) {
        final json = event.toJson();
        if (json['cat'] != 'GC') return true;
        final timestamp = json['ts'];
        return timestamp is int && timestamp >= cutoff;
      });
    } finally {
      await historyObserver.dispose();
    }
    final missingMetadata = await collector.endWindow(
      DartVmMetricsWindow(
        cpuUserTicks: null,
        cpuSystemTicks: null,
        isolateIds: window.isolateIds,
      ),
      rssSnapshot: DartVmMetricsRssSnapshot(
        currentRssBytes: rssBytes,
        peakRssBytes: rssBytes,
      ),
    );
    var mismatchRejected = false;
    try {
      final wrong = await ExternalDartVmMetricsCollector.connect(
        serviceUri: serviceUri,
        pid: pid + 1,
        allIsolates: true,
      );
      await wrong.close();
    } on StateError {
      mismatchRejected = true;
    }
    final observerPid = metrics.allocationMeasurement!['observer_pid'] as int;
    Process.killPid(observerPid, ProcessSignal.sigkill);
    var crashPropagated = false;
    try {
      await collector.beginWindow().timeout(const Duration(seconds: 3));
    } on Object {
      crashPropagated = true;
    }
    final close = collector.close();
    final idempotentClose = identical(close, collector.close());
    await close;
    stdout.writeln(
      jsonEncode({
        'allocated_bytes_delta': metrics.allocatedBytes,
        'allocation_measurement': metrics.allocationMeasurement,
        'pid_mismatch_rejected': mismatchRejected,
        'observer_crash_propagated': crashPropagated,
        'close_idempotent': idempotentClose,
        'previous_timeline_cleared': previousTimelineCleared,
        'known_payload_allocation_bytes': 80 * 1024 * 1024,
        'missing_metadata_allocated_bytes': missingMetadata.allocatedBytes,
        'missing_metadata_gc_count': missingMetadata.gcCount,
        'missing_metadata_gc_pause_us': missingMetadata.gcPauseMicros,
        'gc_count_delta': metrics.gcCount,
        'gc_pause_us_delta': metrics.gcPauseMicros,
        'current_rss_bytes': metrics.currentRssBytes,
        'peak_rss_bytes': metrics.peakRssBytes,
      }),
    );
  } finally {
    await collector.close();
    workerPort.send('stop');
    await workerStopped.future.timeout(const Duration(seconds: 5));
    worker.kill(priority: Isolate.immediate);
    messages.close();
  }
}

void _allocationWorker(SendPort parent) {
  final commands = ReceivePort();
  parent.send(commands.sendPort);
  commands.listen((command) {
    if (command == 'allocate') {
      _retainedBuffers = List<Uint8List>.generate(
        256,
        (_) => Uint8List(64 * 1024),
        growable: false,
      );
      _allocateTransientBuffers();
      parent.send(_retainedBuffers.length);
    } else if (command == 'stop') {
      commands.close();
      parent.send('stopped');
    }
  });
}

@pragma('vm:never-inline')
int _allocateTransientBuffers() {
  var checksum = 0;
  for (var i = 0; i < 64; i++) {
    final buffer = Uint8List(1024 * 1024);
    buffer[0] = i;
    checksum += buffer[0];
  }
  return checksum;
}

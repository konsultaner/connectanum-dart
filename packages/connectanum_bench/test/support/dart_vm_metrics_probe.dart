import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_bench/src/dart_vm_metrics.dart';

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
  final collector = await DartVmMetricsCollector.connect(
    serviceUri: serviceUri,
    pid: pid,
    allIsolates: true,
  );

  try {
    final window = await collector.beginWindow();
    workerPort.send('allocate');
    await allocationComplete.future.timeout(const Duration(seconds: 5));
    final rssBytes = ProcessInfo.currentRss;
    final metrics = await collector.endWindow(
      window,
      rssSnapshot: DartVmMetricsRssSnapshot(
        currentRssBytes: rssBytes,
        peakRssBytes: rssBytes,
      ),
    );
    stdout.writeln(
      jsonEncode({
        'allocated_bytes_delta': metrics.allocatedBytes,
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
      parent.send(_retainedBuffers.length);
    } else if (command == 'stop') {
      commands.close();
      parent.send('stopped');
    }
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart_vm_metrics.dart';
import 'dart_vm_metrics_wire.dart';

/// Separate process: VM-service JSON must not allocate in either measured heap.
Future<void> main(List<String> args) async {
  final config = metricsObject(jsonDecode(args.single));
  final uri = config['service_uri'];
  final targetPid = config['pid'];
  final all = config['all_isolates'];
  if (uri is! String || targetPid is! int || targetPid <= 0 || all is! bool) {
    throw const FormatException('Invalid metrics observer configuration');
  }
  final collector = await DartVmMetricsCollector.connect(
    serviceUri: Uri.parse(uri),
    pid: targetPid,
    allIsolates: all,
  );
  stdout.writeln('READY');
  try {
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      final request = metricsObject(jsonDecode(line));
      final id = request['id'];
      if (id is! int || id <= 0) {
        throw const FormatException('Invalid observer request id');
      }
      try {
        final Object? result;
        switch (request['command']) {
          case 'begin':
            result = encodeMetricsWindow(await collector.beginWindow());
          case 'end':
            final rss = metricsObject(request['rss']);
            result = encodeMetricsResult(
              await collector.endWindow(
                decodeMetricsWindow(request['window']),
                rssSnapshot: DartVmMetricsRssSnapshot(
                  currentRssBytes: rss['current'] as int?,
                  peakRssBytes: rss['peak'] as int?,
                ),
              ),
            );
          case 'close':
            result = <String, Object?>{};
          default:
            throw const FormatException('Unknown metrics observer command');
        }
        stdout.writeln(jsonEncode({'id': id, 'result': result}));
        await stdout.flush();
        if (request['command'] == 'close') break;
      } catch (error) {
        stdout.writeln(jsonEncode({'id': id, 'error': error.toString()}));
        await stdout.flush();
      }
    }
  } finally {
    await collector.close();
  }
}

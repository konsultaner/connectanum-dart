// Diagnostic only: default VM, public native allocator trim, no GC requests.
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:connectanum_bench/src/mqtt_gateway_worker.dart';

Future<void> main(List<String> args) async {
  if (!Platform.isLinux || Platform.environment['DART_VM_OPTIONS'] != null) {
    throw StateError('Diagnostic requires default VM on Linux');
  }
  final library = ffi.DynamicLibrary.process();
  final trim = library
      .lookupFunction<ffi.Int32 Function(ffi.UintPtr), int Function(int)>(
        'malloc_trim',
      );
  final group = library
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(),
        ffi.Pointer<ffi.Void> Function()
      >('Dart_CurrentIsolateGroup')();
  final metrics = <String, int Function(ffi.Pointer<ffi.Void>)>{
    for (final part in [
      'OldUsed',
      'OldCapacity',
      'OldExternal',
      'NewCapacity',
      'NewExternal',
    ])
      part: library
          .lookupFunction<
            ffi.Int64 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)
          >('Dart_IsolateGroupHeap${part}Metric'),
  };
  GatewayBenchmarkServer? server;
  await runGatewayBenchmarkWorker(
    args,
    serverFactory: (config) async =>
        server = await NativeGatewayBenchmarkServer.start(config),
    input: stdin.transform(utf8.decoder).transform(const LineSplitter()).map((
      line,
    ) {
      final command = jsonDecode(line) as Map<String, dynamic>;
      if (args.first == 'server' && command['op'] == 'sample')
        command['op'] = 'collect';
      return jsonEncode(command);
    }),
    emit: (value) {
      if (value['kind'] == 'collected') value['kind'] = 'sampled';
      stdout.writeln(jsonEncode(value));
    },
    collectMemory: () async {
      final queues = await server!.sampleQueues();
      if (queues['active_connections'] != 0 ||
          queues['broker_connected_peers'] != 0 ||
          queues['pending_operations'] != 0)
        return;
      final heap = {
        for (final entry in metrics.entries) entry.key: entry.value(group),
      };
      final before = ProcessInfo.currentRss;
      final result = trim(0);
      final after = ProcessInfo.currentRss;
      stderr.writeln(
        jsonEncode({
          'kind': 'idle-native-trim',
          'before_rss_bytes': before,
          'after_rss_bytes': after,
          'trim_result': result,
          'heap': heap,
          'queues': queues,
        }),
      );
    },
  );
}

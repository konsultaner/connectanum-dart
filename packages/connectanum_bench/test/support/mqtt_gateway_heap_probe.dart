import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:connectanum_bench/src/mqtt_gateway_worker.dart';

typedef _GroupNative = Pointer<Void> Function();
typedef _Group = Pointer<Void> Function();
typedef _MetricNative = Int64 Function(Pointer<Void>);
typedef _Metric = int Function(Pointer<Void>);
Future<void> main(List<String> args) async {
  final library = DynamicLibrary.process();
  final group = library.lookupFunction<_GroupNative, _Group>(
    'Dart_CurrentIsolateGroup',
  );
  final metrics = <String, _Metric>{
    for (final name in [
      'HeapNewCapacity',
      'HeapOldCapacity',
      'HeapOldUsed',
      'HeapOldExternal',
      'HeapNewExternal',
    ])
      name: library.lookupFunction<_MetricNative, _Metric>(
        'Dart_IsolateGroup${name}Metric',
      ),
  };
  await runGatewayBenchmarkWorker(
    args,
    emit: (message) {
      stdout.writeln(
        jsonEncode({
          ...message,
          'diagnostic_time_us': DateTime.now().microsecondsSinceEpoch,
          if (message['memory'] != null)
            'diagnostic_proc_rss': File(
              '/proc/self/status',
            ).readAsLinesSync().firstWhere((s) => s.startsWith('VmRSS:')),
          if (message['memory'] != null)
            'diagnostic_heap': {
              for (final entry in metrics.entries)
                entry.key: entry.value(group()),
            },
        }),
      );
    },
  );
}

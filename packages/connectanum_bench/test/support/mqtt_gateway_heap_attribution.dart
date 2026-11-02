import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:connectanum_bench/src/mqtt_gateway_worker.dart';

typedef _GroupNative = Pointer<Void> Function();
typedef _Group = Pointer<Void> Function();
typedef _MetricNative = Int64 Function(Pointer<Void>);
typedef _Metric = int Function(Pointer<Void>);

final class MallInfo extends Struct {
  @UintPtr()
  external int arena;
  @UintPtr()
  external int ordblks;
  @UintPtr()
  external int smblks;
  @UintPtr()
  external int hblks;
  @UintPtr()
  external int hblkhd;
  @UintPtr()
  external int usmblks;
  @UintPtr()
  external int fsmblks;
  @UintPtr()
  external int uordblks;
  @UintPtr()
  external int fordblks;
  @UintPtr()
  external int keepcost;
}

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
  final mallinfo = library
      .lookupFunction<MallInfo Function(), MallInfo Function()>('mallinfo2');
  await runGatewayBenchmarkWorker(
    args,
    emit: (message) {
      final result = <String, Object?>{...message};
      if (message['memory'] != null) {
        result['diagnostic_heap'] = {
          for (final entry in metrics.entries) entry.key: entry.value(group()),
        };
        final m = mallinfo();
        result['diagnostic_allocator'] = {
          'arena': m.arena,
          'hblkhd': m.hblkhd,
          'uordblks': m.uordblks,
          'fordblks': m.fordblks,
          'keepcost': m.keepcost,
        };
        result['diagnostic_proc_status_after_metrics'] =
            File('/proc/self/status')
                .readAsLinesSync()
                .where((s) => s.startsWith('VmRSS:') || s.startsWith('VmHWM:'))
                .toList();
      }
      stdout.writeln(jsonEncode(result));
    },
  );
}

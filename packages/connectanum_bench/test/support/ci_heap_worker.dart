import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:convert';

import 'package:connectanum_bench/src/mqtt_gateway_worker.dart';

final class Mallinfo extends ffi.Struct {
  @ffi.UintPtr()
  external int arena;
  @ffi.UintPtr()
  external int ordblks;
  @ffi.UintPtr()
  external int smblks;
  @ffi.UintPtr()
  external int hblks;
  @ffi.UintPtr()
  external int hblkhd;
  @ffi.UintPtr()
  external int usmblks;
  @ffi.UintPtr()
  external int fsmblks;
  @ffi.UintPtr()
  external int uordblks;
  @ffi.UintPtr()
  external int fordblks;
  @ffi.UintPtr()
  external int keepcost;
}

Future<void> main(List<String> args) async {
  final lib = ffi.DynamicLibrary.process();
  final group = lib
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(),
        ffi.Pointer<ffi.Void> Function()
      >('Dart_CurrentIsolateGroup')();
  final metrics = {
    for (final name in [
      'NewCapacity',
      'NewUsed',
      'NewExternal',
      'OldCapacity',
      'OldUsed',
      'OldExternal',
    ])
      name: lib
          .lookupFunction<
            ffi.Int64 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)
          >('Dart_IsolateGroupHeap${name}Metric'),
  };
  final malloc = lib.lookupFunction<Mallinfo Function(), Mallinfo Function()>(
    'mallinfo2',
  );
  await runGatewayBenchmarkWorker(
    args,
    emit: (event) {
      stdout.writeln(jsonEncode(event));
      if (args.first == 'server' && event['kind'] == 'sampled') {
        final m = malloc();
        final smaps = File('/proc/self/smaps_rollup').readAsStringSync();
        final status = File('/proc/self/status').readAsStringSync();
        stderr.writeln(
          jsonEncode({
            'kind': 'heap',
            'rss': ProcessInfo.currentRss,
            'cpus': Platform.numberOfProcessors,
            for (final e in metrics.entries) e.key: e.value(group),
            'malloc_allocated': m.uordblks,
            'malloc_free': m.fordblks,
            'malloc_mmaps': m.hblkhd,
            'malloc_arena': m.arena,
            'smaps': smaps
                .split('\n')
                .where(
                  (s) =>
                      RegExp(r'^(Rss|Anonymous|Private_Dirty|AnonHugePages):')
                          .hasMatch(s),
                )
                .join('; '),
            'threads': RegExp(r'Threads:\s+(\d+)').firstMatch(status)?.group(1),
          }),
        );
      }
    },
  );
}

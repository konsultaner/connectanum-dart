// Diagnostic only: no GC or VM flags; parent requests cleanup only after close.
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:connectanum_bench/src/mqtt_gateway_worker.dart';

Future<void> main(List<String> args) async {
  if (!Platform.isLinux || Platform.environment['DART_VM_OPTIONS'] != null)
    throw StateError('Requires default VM on Linux');
  final config = jsonDecode(args[1]) as Map<String, dynamic>;
  final library = ffi.DynamicLibrary.process();
  final trim = library
      .lookupFunction<ffi.Int32 Function(ffi.UintPtr), int Function(int)>(
        'malloc_trim',
      );
  final getpid = library.lookupFunction<ffi.Int32 Function(), int Function()>(
    'getpid',
  );
  await runGatewayBenchmarkWorker(
    args,
    collectMemory: () async {
      final before = ProcessInfo.currentRss;
      final value = config['allocator_probe_mode'] == 'trim'
          ? trim(0)
          : getpid();
      final after = ProcessInfo.currentRss;
      stderr.writeln(
        jsonEncode({
          'kind': 'idle-native-probe',
          'mode': config['allocator_probe_mode'],
          'before_rss_bytes': before,
          'after_rss_bytes': after,
          'result': value,
        }),
      );
    },
  );
}

// Internal verification executable. Never use this SDK test hook in a runtime.
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_bench/src/mqtt_gateway_worker.dart';
import 'package:ffi/ffi.dart';

typedef _CollectNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Void>,
    );
typedef _CollectDart =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Void>,
    );

final class RetentionCollector {
  RetentionCollector({
    required void Function() collect,
    required void Function() clearCaches,
    int Function()? readYoungCapacity,
    bool Function() Function()? witnessFactory,
    this.settle = const Duration(milliseconds: 50),
  }) : _collect = collect,
       _clearCaches = clearCaches,
       _readYoungCapacity = readYoungCapacity ?? (() => 0),
       _witnessFactory = witnessFactory ?? _collectionWitness;

  factory RetentionCollector.forPinnedSdk() {
    validateSdk(Platform.version);
    validateHost(Platform.operatingSystem);
    validateVmOptions(Platform.environment['DART_VM_OPTIONS']);
    final library = ffi.DynamicLibrary.process();
    final command = library.lookupFunction<_CollectNative, _CollectDart>(
      'Dart_ExecuteInternalCommand',
    );
    final clearCaches = library
        .lookupFunction<ffi.Void Function(), void Function()>(
          'Dart_NotifyLowMemory',
        );
    final group = library
        .lookupFunction<
          ffi.Pointer<ffi.Void> Function(),
          ffi.Pointer<ffi.Void> Function()
        >(
          'Dart_CurrentIsolateGroup',
        )();
    final youngCapacity = library
        .lookupFunction<
          ffi.Int64 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('Dart_IsolateGroupHeapNewCapacityMetric');
    final release = library
        .lookupFunction<ffi.Int32 Function(ffi.UintPtr), int Function(int)>(
          'malloc_trim',
        );
    return RetentionCollector(
      collect: () {
        final name = 'gc-now'.toNativeUtf8();
        try {
          command(name, ffi.nullptr);
        } finally {
          calloc.free(name);
        }
      },
      clearCaches: () {
        clearCaches();
        release(0);
      },
      readYoungCapacity: () => youngCapacity(group),
    );
  }

  static void validateSdk(String version) {
    if (!version.startsWith('3.13.1 (stable)')) {
      throw UnsupportedError('Retention test hook requires Dart 3.13.1 stable');
    }
  }

  static void validateHost(String operatingSystem) {
    if (operatingSystem != 'linux') {
      throw UnsupportedError(
        'Retention stress requires the qualified glibc Linux host',
      );
    }
  }

  static void validateVmOptions(String? value) {
    if (value != '--new_gen_semi_max_size=1') {
      throw UnsupportedError(
        'Retention stress requires a 1 MiB nursery semispace',
      );
    }
  }

  final void Function() _collect;
  final void Function() _clearCaches;
  final int Function() _readYoungCapacity;
  final bool Function() Function() _witnessFactory;
  final Duration settle;
  int collections = 0;
  int maxYoungCapacityBytes = 0;

  Future<void> collect() async {
    final collected = _witnessFactory();
    // Fixed passes allow asynchronous sweeping and external finalizers to run.
    // This never changes the VM's allocation/GC settings during a workload.
    for (var i = 0; i < 2; i++) {
      _collect();
      await Future<void>.delayed(settle);
      _clearCaches();
      collections++;
    }
    if (!collected()) {
      throw StateError('Collection did not clear its weak witness');
    }
    final young = _readYoungCapacity();
    if (young > 2 * 1024 * 1024 || young < 0) {
      throw StateError('Retention nursery bound was not applied');
    }
    if (young > maxYoungCapacityBytes) maxYoungCapacityBytes = young;
  }

  Future<Map<String, int>> verifyNative() async {
    final before = ProcessInfo.currentRss;
    final blocks = <ffi.Pointer<ffi.Uint8>>[];
    late final int rooted;
    try {
      for (var n = 0; n < 512; n++) {
        final block = calloc<ffi.Uint8>(65536);
        blocks.add(block);
        for (var offset = 0; offset < 65536; offset += 4096) {
          block[offset] = 17;
        }
      }
      await collect();
      for (final block in blocks) {
        for (var offset = 0; offset < 65536; offset += 4096) {
          if (block[offset] != 17)
            throw StateError('Live native memory changed');
        }
      }
      rooted = ProcessInfo.currentRss;
    } finally {
      for (final block in blocks) {
        calloc.free(block);
      }
    }
    await collect();
    return {
      'before_rss_bytes': before,
      'rooted_rss_bytes': rooted,
      'released_rss_bytes': ProcessInfo.currentRss,
    };
  }

  Future<Map<String, int>> verify({int witnessBytes = 32}) async {
    final before = ProcessInfo.currentRss;
    final witness = _Witness(witnessBytes);
    // Keep the witness rooted through two full collections before releasing it.
    await collect();
    if (witness.gone) throw StateError('Collection reclaimed a live witness');
    final rooted = ProcessInfo.currentRss;
    witness.release();
    await Future<void>.delayed(Duration.zero);
    await collect();
    if (!witness.gone) throw StateError('Collection left an unrooted witness');
    return {
      'before_rss_bytes': before,
      'rooted_rss_bytes': rooted,
      'released_rss_bytes': ProcessInfo.currentRss,
    };
  }
}

@pragma('vm:never-inline')
bool Function() _collectionWitness() {
  final weak = WeakReference(Object());
  return () => weak.target == null;
}

final class _Witness {
  _Witness(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i += 4096) {
      bytes[i] = 1;
    }
    _root = bytes;
    _weak = WeakReference(bytes);
  }
  Uint8List? _root;
  late final WeakReference<Uint8List> _weak;
  @pragma('vm:never-inline')
  bool get gone {
    final target = _weak.target;
    if (_root != null && !identical(target, _root)) {
      throw StateError('Collection reclaimed a rooted witness');
    }
    return target == null;
  }

  @pragma('vm:never-inline')
  void release() => _root = null;
}

Future<void> main(List<String> arguments) async {
  final collector = RetentionCollector.forPinnedSdk();
  await collector.verify();
  if (arguments.length == 1 && arguments.single == '--self-test') {
    final memory = await collector.verify(witnessBytes: 32 * 1024 * 1024);
    final native = await collector.verifyNative();
    final growth = memory['rooted_rss_bytes']! - memory['before_rss_bytes']!;
    final nativeGrowth =
        native['rooted_rss_bytes']! - native['before_rss_bytes']!;
    final nativeDrop =
        native['rooted_rss_bytes']! - native['released_rss_bytes']!;
    if (growth < 24 * 1024 * 1024 ||
        nativeGrowth < 24 * 1024 * 1024 ||
        nativeDrop < 24 * 1024 * 1024) {
      throw StateError(
        'Retention negative control did not expose its allocation: '
        'managed=$growth native=$nativeGrowth nativeReleased=$nativeDrop '
        'managedMemory=$memory nativeMemory=$native',
      );
    }
    stdout.writeln(
      jsonEncode({
        'kind': 'retention-self-test',
        'protocol': 'bounded_nursery_v1',
        'dart_version': Platform.version,
        'collections': collector.collections,
        'live_and_released_witnesses_verified': true,
        'rooted_witness_bytes': 32 * 1024 * 1024,
        'rooted_witness_rss_growth_bytes': growth,
        'negative_control_memory': memory,
        'native_witness_bytes': 32 * 1024 * 1024,
        'native_witness_rss_growth_bytes': nativeGrowth,
        'native_witness_rss_drop_bytes': nativeDrop,
        'negative_control_native_memory': native,
        'max_young_capacity_bytes': collector.maxYoungCapacityBytes,
      }),
    );
    return;
  }
  await runGatewayBenchmarkWorker(arguments, collectMemory: collector.collect);
}

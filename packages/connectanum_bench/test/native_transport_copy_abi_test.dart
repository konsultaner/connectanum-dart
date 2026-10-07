@TestOn('vm')
library;

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:connectanum_client/src/transport/native/ffi_bindings.dart'
    as client_ffi;
import 'package:connectanum_client/src/transport/native/runtime.dart' as client;
import 'package:connectanum_router/src/native/ffi_bindings.dart' as router_ffi;
import 'package:connectanum_router/src/native/runtime.dart' as router;
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'support/native_library.dart';

void _equal(Object? actual, Object? expected) {
  if (actual != expected) throw StateError('$actual != $expected');
}

void main() async {
  if (Platform.environment['CONNECTANUM_TRANSPORT_COPY_PROBE'] == '1') {
    _probe();
    print('isolated transport copy snapshot passed');
    return;
  }
  test(
    'transport copy snapshots preserve the legacy ABI and optional counters',
    () async {
      final path = nativeBenchTestLibrary();
      expect(
        path,
        isNotNull,
        reason: 'Requires the canonical native test library',
      );
      final source = await Isolate.resolvePackageUri(
        Uri.parse('package:connectanum_bench/connectanum_bench.dart'),
      );
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          source!
              .resolve('../test/native_transport_copy_abi_test.dart')
              .toFilePath(),
        ],
        environment: {
          'CONNECTANUM_NATIVE_LIB': path!,
          'CONNECTANUM_TRANSPORT_COPY_PROBE': '1',
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains('isolated transport copy snapshot passed'),
      );
    },
  );
}

// Exact comparisons run outside the test runner's shared process-wide counters.
void _probe() {
  _equal(ffi.sizeOf<client_ffi.CtTransportCopyMetricsInfo>(), 24);
  _equal(ffi.sizeOf<router_ffi.CtTransportCopyMetricsInfo>(), 24);
  _equal(ffi.sizeOf<client_ffi.CtTransportCopyMetricsInfoV2>(), 40);
  _equal(ffi.sizeOf<router_ffi.CtTransportCopyMetricsInfoV2>(), 40);

  final path = client.NativeLibraryLoader.resolvePath();
  final library = ffi.DynamicLibrary.open(path);
  final nativeClient = client.NativeClientRuntime.instance(
    libraryPath: path,
  );

  final nativeRouter = router.NativeTransportRuntime(libraryPath: path);

  try {
    final clientMetrics = nativeClient.transportCopyMetricsSnapshot();
    final routerMetrics = nativeRouter.transportCopyMetricsSnapshot();

    final legacy = calloc<client_ffi.CtTransportCopyMetricsInfo>();
    try {
      final snapshot = library
          .lookupFunction<
            client_ffi.CtTransportCopyMetricsSnapshotNative,
            client_ffi.CtTransportCopyMetricsSnapshotDart
          >(
            'ct_transport_copy_metrics_snapshot',
          );
      _equal(snapshot(legacy), 0);
      _equal(
        clientMetrics.websocketMaskCopyBytesTotal,
        legacy.ref.websocketMaskCopyBytesTotal,
      );
      _equal(
        routerMetrics.websocketCoalesceCopyBytesTotal,
        legacy.ref.websocketCoalesceCopyBytesTotal,
      );
      _equal(
        clientMetrics.tlsPlaintextAcceptedBytesTotal,
        legacy.ref.tlsPlaintextAcceptedBytesTotal,
      );
    } finally {
      calloc.free(legacy);
    }

    if (library.providesSymbol('ct_transport_copy_metrics_snapshot_v2')) {
      final info = calloc<client_ffi.CtTransportCopyMetricsInfoV2>();
      try {
        final snapshot = library
            .lookupFunction<
              client_ffi.CtTransportCopyMetricsSnapshotV2Native,
              client_ffi.CtTransportCopyMetricsSnapshotV2Dart
            >(
              'ct_transport_copy_metrics_snapshot_v2',
            );
        _equal(snapshot(info), 0);
        _equal(
          clientMetrics.ioBufferFrontCopyBytesTotal,
          info.ref.ioBufferFrontCopyBytesTotal,
        );
        _equal(
          clientMetrics.ioBufferedReadCopyBytesTotal,
          info.ref.ioBufferedReadCopyBytesTotal,
        );
        _equal(
          routerMetrics.ioBufferFrontCopyBytesTotal,
          info.ref.ioBufferFrontCopyBytesTotal,
        );
        _equal(
          routerMetrics.ioBufferedReadCopyBytesTotal,
          info.ref.ioBufferedReadCopyBytesTotal,
        );
      } finally {
        calloc.free(info);
      }
    } else {
      _equal(clientMetrics.ioBufferFrontCopyBytesTotal, null);
      _equal(clientMetrics.ioBufferedReadCopyBytesTotal, null);
      _equal(routerMetrics.ioBufferFrontCopyBytesTotal, null);
      _equal(routerMetrics.ioBufferedReadCopyBytesTotal, null);
    }
  } finally {
    nativeRouter.dispose();
    client.NativeClientRuntime.shutdownShared();
  }
}

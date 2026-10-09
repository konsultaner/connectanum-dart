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

  _equal(ffi.sizeOf<client_ffi.CtRustlsCopyMetricsInfo>(), 48);
  _equal(ffi.sizeOf<router_ffi.CtRustlsCopyMetricsInfo>(), 48);

  final path = client.NativeLibraryLoader.resolvePath();
  final library = ffi.DynamicLibrary.open(path);
  final nativeClient = client.NativeClientRuntime.instance(
    libraryPath: path,
  );

  final nativeRouter = router.NativeTransportRuntime(libraryPath: path);

  try {
    final clientMetrics = nativeClient.transportCopyMetricsSnapshot();
    final routerMetrics = nativeRouter.transportCopyMetricsSnapshot();

    if (library.providesSymbol('ct_rustls_copy_metrics_snapshot')) {
      final info = calloc<client_ffi.CtRustlsCopyMetricsInfo>();
      try {
        final snapshot = library
            .lookupFunction<
              client_ffi.CtRustlsCopyMetricsSnapshotNative,
              client_ffi.CtRustlsCopyMetricsSnapshotDart
            >('ct_rustls_copy_metrics_snapshot');
        _equal(snapshot(info), 0);
        _equal(
          clientMetrics.rustlsOutboundChunkCopyBytesTotal,
          info.ref.outboundChunkCopyBytesTotal,
        );
        _equal(
          routerMetrics.rustlsOutboundChunkCopyBytesTotal,
          info.ref.outboundChunkCopyBytesTotal,
        );
        _equal(
          clientMetrics.rustlsQueueReadCopyBytesTotal,
          info.ref.queueReadCopyBytesTotal,
        );
        _equal(
          routerMetrics.rustlsQueueReadCopyBytesTotal,
          info.ref.queueReadCopyBytesTotal,
        );
        _equal(
          clientMetrics.rustlsDeframerAppendCopyBytesTotal,
          info.ref.deframerAppendCopyBytesTotal,
        );
        _equal(
          routerMetrics.rustlsDeframerAppendCopyBytesTotal,
          info.ref.deframerAppendCopyBytesTotal,
        );
        _equal(
          clientMetrics.rustlsDeframerMoveCopyBytesTotal,
          info.ref.deframerMoveCopyBytesTotal,
        );
        _equal(
          routerMetrics.rustlsDeframerMoveCopyBytesTotal,
          info.ref.deframerMoveCopyBytesTotal,
        );
        _equal(
          clientMetrics.rustlsRecordBufferCopyBytesTotal,
          info.ref.recordBufferCopyBytesTotal,
        );
        _equal(
          routerMetrics.rustlsRecordBufferCopyBytesTotal,
          info.ref.recordBufferCopyBytesTotal,
        );
        _equal(
          clientMetrics.rustlsRecordAppendCopyBytesTotal,
          info.ref.recordAppendCopyBytesTotal,
        );
        _equal(
          routerMetrics.rustlsRecordAppendCopyBytesTotal,
          info.ref.recordAppendCopyBytesTotal,
        );
      } finally {
        calloc.free(info);
      }
    } else {
      _equal(clientMetrics.rustlsOutboundChunkCopyBytesTotal, null);
      _equal(routerMetrics.rustlsOutboundChunkCopyBytesTotal, null);
      _equal(
        clientMetrics
            .deltaFrom(clientMetrics)
            .rustlsOutboundChunkCopyBytesTotal,
        null,
      );
      _equal(
        routerMetrics
            .deltaFrom(routerMetrics)
            .rustlsOutboundChunkCopyBytesTotal,
        null,
      );
      _equal(clientMetrics.rustlsQueueReadCopyBytesTotal, null);
      _equal(routerMetrics.rustlsQueueReadCopyBytesTotal, null);
      _equal(
        clientMetrics.deltaFrom(clientMetrics).rustlsQueueReadCopyBytesTotal,
        null,
      );
      _equal(
        routerMetrics.deltaFrom(routerMetrics).rustlsQueueReadCopyBytesTotal,
        null,
      );
      _equal(clientMetrics.rustlsDeframerAppendCopyBytesTotal, null);
      _equal(routerMetrics.rustlsDeframerAppendCopyBytesTotal, null);
      _equal(
        clientMetrics
            .deltaFrom(clientMetrics)
            .rustlsDeframerAppendCopyBytesTotal,
        null,
      );
      _equal(
        routerMetrics
            .deltaFrom(routerMetrics)
            .rustlsDeframerAppendCopyBytesTotal,
        null,
      );
      _equal(clientMetrics.rustlsDeframerMoveCopyBytesTotal, null);
      _equal(routerMetrics.rustlsDeframerMoveCopyBytesTotal, null);
      _equal(
        clientMetrics.deltaFrom(clientMetrics).rustlsDeframerMoveCopyBytesTotal,
        null,
      );
      _equal(
        routerMetrics.deltaFrom(routerMetrics).rustlsDeframerMoveCopyBytesTotal,
        null,
      );
      _equal(clientMetrics.rustlsRecordBufferCopyBytesTotal, null);
      _equal(routerMetrics.rustlsRecordBufferCopyBytesTotal, null);
      _equal(
        clientMetrics.deltaFrom(clientMetrics).rustlsRecordBufferCopyBytesTotal,
        null,
      );
      _equal(
        routerMetrics.deltaFrom(routerMetrics).rustlsRecordBufferCopyBytesTotal,
        null,
      );
      _equal(clientMetrics.rustlsRecordAppendCopyBytesTotal, null);
      _equal(routerMetrics.rustlsRecordAppendCopyBytesTotal, null);
      _equal(
        clientMetrics.deltaFrom(clientMetrics).rustlsRecordAppendCopyBytesTotal,
        null,
      );
      _equal(
        routerMetrics.deltaFrom(routerMetrics).rustlsRecordAppendCopyBytesTotal,
        null,
      );
    }

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

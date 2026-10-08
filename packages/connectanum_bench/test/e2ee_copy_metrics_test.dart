@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:connectanum_bench/src/e2ee_copy_metrics.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:connectanum_core/src/message/e2ee_copy_metrics.dart';
import 'package:test/test.dart';

import 'support/native_library.dart';

void main() {
  final nativeLibrary = nativeBenchTestLibrary();
  group('native ciphertext coercion copy evidence', () {
    tearDown(NativeClientRuntime.shutdownShared);
    for (final serializer in ['cbor', 'flatbuffers']) {
      for (final aes in [false, true]) {
        for (final representation in [
          'uint8list',
          'uint8list-subview',
          'int-list',
          'dynamic-list',
        ]) {
          test(
            '$serializer aes=$aes $representation counts actual conversion',
            () {
              final runtime = NativeClientRuntime.instance(
                libraryPath: nativeLibrary,
              );
              final key = List<int>.generate(32, (index) => index + 1);
              final provider = _nativeProvider(
                serializer,
                aes,
                key,
                nativeLibrary,
              );
              addTearDown(provider.release);
              final application = Uint8List.fromList([0, 255, 128, 37]);
              final options = PublishOptions();
              final wire =
                  provider.packPayload([application], null, options).single
                      as Uint8List;
              final Object input = switch (representation) {
                'int-list' => List<int>.of(wire),
                'dynamic-list' => <dynamic>[...wire],
                'uint8list-subview' => Uint8List.sublistView(
                  Uint8List.fromList([99, ...wire, 98]),
                  1,
                  wire.length + 1,
                ).asUnmodifiableView(),
                _ => wire.asUnmodifiableView(),
              };
              final before = runtime.e2eeCopyMetricsSnapshot();
              final decoded = provider.unpackPayload([input], options);
              final delta = runtime.e2eeCopyMetricsSnapshot().deltaFrom(before);
              final expectedCoercion = representation.startsWith('uint8list')
                  ? 0
                  : wire.length;
              expect(delta.ciphertextCoercionCopyBytesTotal, expectedCoercion);
              expect(decoded.arguments!.single, orderedEquals(application));
              final result = e2eeCopyMetricsFor(_scenario('wamp'), delta);
              final bridgeAndStaging =
                  delta.dartToNativeCopiedBytesTotal +
                  delta.nativeToDartCopiedBytesTotal +
                  (delta.plaintextStagingCopyBytesTotal ?? 0) +
                  (delta.ciphertextStagingCopyBytesTotal ?? 0);
              expect(
                (result['known_e2ee_staging_copy_bytes'] as int) -
                    bridgeAndStaging,
                expectedCoercion,
                reason:
                    'The list conversion is separate from native bridge and staging copies',
              );
              expect(
                (result['e2ee_copy_bytes'] as Map)['status'],
                'not_measured',
              );
            },
            skip: nativeLibrary == null
                ? 'Native transport artifact unavailable'
                : false,
          );
        }
      }
    }

    for (final aes in [false, true]) {
      for (final invalid in [-1, 256, 'not a byte']) {
        test(
          'typed aes=$aes counts only the copied prefix before $invalid',
          () {
            final runtime = NativeClientRuntime.instance(
              libraryPath: nativeLibrary,
            );
            final provider = _nativeProvider(
              'flatbuffers',
              aes,
              List<int>.generate(32, (index) => index + 1),
              nativeLibrary,
            );
            addTearDown(provider.release);
            for (final prefix in [
              <dynamic>[],
              <dynamic>[0, 255, 128],
            ]) {
              final before = runtime.e2eeCopyMetricsSnapshot();
              expect(
                () => provider.unpackPayload([
                  [...prefix, invalid, 37],
                ], PublishOptions()),
                throwsA(isA<WampE2eeInvalidPayloadException>()),
              );
              final delta = runtime.e2eeCopyMetricsSnapshot().deltaFrom(before);
              expect(delta.ciphertextCoercionCopyBytesTotal, prefix.length);
              expect(delta.dartToNativeCopiedBytesTotal, 0);
              expect(delta.nativeToDartCopiedBytesTotal, 0);
            }
          },
          skip: nativeLibrary == null
              ? 'Native transport artifact unavailable'
              : false,
        );
      }
    }
  });

  test('cleartext workloads do not report crypto copies', () {
    final result = e2eeCopyMetricsFor(_scenario(null), _metrics(10, 20));
    expect((result['e2ee_copy_bytes'] as Map)['status'], 'not_applicable');
    expect(result, isNot(contains('known_e2ee_staging_copy_bytes')));
  });

  test('known staging copies cannot certify an encrypted pipeline', () {
    final result = e2eeCopyMetricsFor(_scenario('wamp'), _metrics(10, 20));
    expect(result['known_e2ee_staging_copy_bytes'], 37);
    expect((result['e2ee_copy_bytes'] as Map)['status'], 'not_measured');
    final breakdown = result['e2ee_copy_breakdown'] as Map;
    expect(breakdown['coverage'], 'known_staging_only');
    expect(breakdown['excludes'], contains('other isolate Dart bridges'));
  });

  test('missing native ABI leaves native measurements unavailable', () {
    final result = e2eeCopyMetricsFor(
      _scenario('wamp'),
      _metrics(null, null, coercion: 13),
    );
    expect(result['known_e2ee_staging_copy_bytes'], 20);
    final breakdown = result['e2ee_copy_breakdown'] as Map;
    expect(
      breakdown['client_worker_isolate_native_provider_ciphertext_coercion_copy_bytes'],
      13,
    );
    for (final key in [
      'client_process_plaintext_staging_copy_bytes',
      'client_process_ciphertext_staging_copy_bytes',
    ]) {
      expect((breakdown[key] as Map)['status'], 'not_measured');
    }
  });

  test('deltas preserve unavailable counters across capability changes', () {
    final delta = _metrics(10, 20).deltaFrom(_metrics(null, 5));
    expect(delta.plaintextStagingCopyBytesTotal, isNull);
    expect(delta.ciphertextStagingCopyBytesTotal, 15);
    expect(delta.dartToNativeCopiedBytesTotal, 0);
    final reset = _metrics(10, 20).deltaFrom(_metrics(30, 40));
    expect(reset.plaintextStagingCopyBytesTotal, 10);
    expect(reset.ciphertextStagingCopyBytesTotal, 20);
    expect(
      _metrics(null, null, coercion: 13)
          .deltaFrom(_metrics(null, null, coercion: 8))
          .ciphertextCoercionCopyBytesTotal,
      5,
    );
    expect(
      _metrics(null, null, coercion: 4)
          .deltaFrom(_metrics(null, null, coercion: 13))
          .ciphertextCoercionCopyBytesTotal,
      4,
    );
  });

  test(
    'portable wrapper measurements add to the lower bound with their scope',
    () {
      final result = e2eeCopyMetricsFor(
        _scenario('wamp'),
        _metrics(10, 20),
        portableMetrics: const PortableE2eeCopyMetricsSnapshot(
          plaintextWrappingCopyBytes: 0,
          ciphertextWrappingCopyBytes: 105,
          ciphertextAssemblyCopyBytes: 0,
          ciphertextCoercionCopyBytes: 2,
        ),
      );
      expect(result['known_e2ee_staging_copy_bytes'], 144);
      expect((result['e2ee_copy_bytes'] as Map)['status'], 'not_measured');
      final breakdown = result['e2ee_copy_breakdown'] as Map;
      expect(breakdown['client_worker_isolate_portable_provider'], {
        'plaintext_wrapping_copy_bytes': 0,
        'ciphertext_wrapping_copy_bytes': 105,
        'ciphertext_assembly_copy_bytes': 0,
        'ciphertext_coercion_copy_bytes': 2,
      });
      expect(breakdown['excludes'], contains('crypto dependency internals'));
    },
  );

  test('an absent portable window cannot become a measured zero', () {
    final result = e2eeCopyMetricsFor(_scenario('wamp'), _metrics(0, 0));
    final breakdown = result['e2ee_copy_breakdown'] as Map;
    expect(
      (breakdown['client_worker_isolate_portable_provider'] as Map)['status'],
      'not_measured',
    );
    expect((result['e2ee_copy_bytes'] as Map)['status'], 'not_measured');
  });
}

NativeE2eeCopyMetrics _metrics(
  int? plaintext,
  int? ciphertext, {
  int coercion = 0,
}) => NativeE2eeCopyMetrics(
  dartToNativeCopiedBytesTotal: 3,
  nativeToDartCopiedBytesTotal: 4,
  plaintextStagingCopyBytesTotal: plaintext,
  ciphertextStagingCopyBytesTotal: ciphertext,
  ciphertextCoercionCopyBytesTotal: coercion,
);

WampScenario _scenario(String? scheme) => WampScenario(
  transport: WampTransport.rawsocket,
  serializer: WampSerializer.flatbuffers,
  mode: WampMode.rpc,
  uri: 'com.example.echo',
  iterations: 1,
  concurrency: 1,
  payloadBytes: 65536,
  pptScheme: scheme,
);

DisposableWampE2eeProvider _nativeProvider(
  String serializer,
  bool aes,
  List<int> key,
  String? libraryPath,
) => switch ((serializer, aes)) {
  ('flatbuffers', true) => NativeWampFlatBuffersAes256GcmProvider.single(
    keyId: 'metrics',
    key: key,
    libraryPath: libraryPath,
  ),
  ('flatbuffers', false) =>
    NativeWampFlatBuffersXsalsa20Poly1305Provider.single(
      keyId: 'metrics',
      key: key,
      libraryPath: libraryPath,
    ),
  (_, true) => NativeWampCborAes256GcmProvider.single(
    keyId: 'metrics',
    key: key,
    libraryPath: libraryPath,
  ),
  (_, false) => NativeWampCborXsalsa20Poly1305Provider.single(
    keyId: 'metrics',
    key: key,
    libraryPath: libraryPath,
  ),
};
